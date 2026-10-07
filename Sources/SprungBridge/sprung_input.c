// Keyboard and mouse input. Every send runs under inputLock so it can never race the
// transport teardown in freerdp_disconnect.
#include "sprung_internal.h"

#include <string.h>

#include <freerdp/input.h>
#include <freerdp/scancode.h>

#define WHEEL_NOTCH 120

static bool input_begin(SprungSession *session) {
    if (!session)
        return false;
    pthread_mutex_lock(&session->inputLock);
    if (session->inputReady)
        return true;
    pthread_mutex_unlock(&session->inputLock);
    return false;
}

static void input_end(SprungSession *session) {
    pthread_mutex_unlock(&session->inputLock);
}

void sprung_input_set_ready(SprungSession *session, bool ready) {
    pthread_mutex_lock(&session->inputLock);
    session->inputReady = ready;
    memset(session->keysDown, 0, sizeof(session->keysDown));
    pthread_mutex_unlock(&session->inputLock);
}

// MARK: - Keyboard

static bool key_is_down(const SprungSession *session, unsigned index) {
    return (session->keysDown[index / 8] >> (index % 8)) & 1;
}

static void key_set_down(SprungSession *session, unsigned index, bool down) {
    if (down)
        session->keysDown[index / 8] |= (uint8_t)(1u << (index % 8));
    else
        session->keysDown[index / 8] &= (uint8_t)~(1u << (index % 8));
}

void sprung_session_send_scancode(SprungSession *session, uint16_t code, bool extended, bool down) {
    if (!input_begin(session))
        return;
    rdpInput *input = session->context->input;
    const uint32_t scancode = MAKE_RDP_SCANCODE(code & 0xFF, extended);
    const unsigned index = (code & 0xFF) | (extended ? 0x100u : 0u);

    if (down) {
        const bool repeat = key_is_down(session, index);
        key_set_down(session, index, true);
        (void)freerdp_input_send_keyboard_event_ex(input, TRUE, repeat, scancode);
    } else if (key_is_down(session, index)) {
        key_set_down(session, index, false);
        (void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, scancode);
    }
    input_end(session);
}

void sprung_session_send_pause(SprungSession *session) {
    if (!input_begin(session))
        return;
    (void)freerdp_input_send_keyboard_pause_event(session->context->input);
    input_end(session);
}

void sprung_session_send_unicode(SprungSession *session, uint16_t codeUnit, bool down) {
    if (!input_begin(session))
        return;
    (void)freerdp_input_send_unicode_keyboard_event(session->context->input,
                                                    down ? 0 : KBD_FLAGS_RELEASE, codeUnit);
    input_end(session);
}

void sprung_session_send_sync(SprungSession *session, bool capsLock, bool numLock, bool scrollLock) {
    if (!input_begin(session))
        return;
    const UINT32 flags = (capsLock ? KBD_SYNC_CAPS_LOCK : 0) | (numLock ? KBD_SYNC_NUM_LOCK : 0) |
                         (scrollLock ? KBD_SYNC_SCROLL_LOCK : 0);
    (void)freerdp_input_send_synchronize_event(session->context->input, flags);
    input_end(session);
}

void sprung_session_release_all_keys(SprungSession *session) {
    if (!input_begin(session))
        return;
    for (unsigned index = 0; index < sizeof(session->keysDown) * 8; index++) {
        if (!key_is_down(session, index))
            continue;
        key_set_down(session, index, false);
        (void)freerdp_input_send_keyboard_event_ex(
            session->context->input, FALSE, FALSE, MAKE_RDP_SCANCODE(index & 0xFF, index > 0xFF));
    }
    input_end(session);
}

// MARK: - Mouse

static UINT16 clamp_coordinate(int32_t value, uint32_t size) {
    if (value < 0 || size == 0)
        return 0;
    return (UINT16)((uint32_t)value >= size ? size - 1 : (uint32_t)value);
}

static void send_mouse(SprungSession *session, UINT16 flags, int32_t x, int32_t y, bool extended) {
    const rdpSettings *settings = session->context->settings;
    const UINT16 cx = clamp_coordinate(x, freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth));
    const UINT16 cy = clamp_coordinate(y, freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight));
    rdpInput *input = session->context->input;
    if (extended)
        (void)freerdp_input_send_extended_mouse_event(input, flags, cx, cy);
    else
        (void)freerdp_input_send_mouse_event(input, flags, cx, cy);
}

void sprung_session_send_mouse_move(SprungSession *session, int32_t x, int32_t y) {
    if (!input_begin(session))
        return;
    send_mouse(session, PTR_FLAGS_MOVE, x, y, false);
    input_end(session);
}

void sprung_session_send_mouse_button(SprungSession *session, SprungMouseButton button, bool down,
                                      int32_t x, int32_t y) {
    if (!input_begin(session))
        return;
    switch (button) {
    case SprungMouseButtonLeft:
        send_mouse(session, PTR_FLAGS_BUTTON1 | (down ? PTR_FLAGS_DOWN : 0), x, y, false);
        break;
    case SprungMouseButtonRight:
        send_mouse(session, PTR_FLAGS_BUTTON2 | (down ? PTR_FLAGS_DOWN : 0), x, y, false);
        break;
    case SprungMouseButtonMiddle:
        send_mouse(session, PTR_FLAGS_BUTTON3 | (down ? PTR_FLAGS_DOWN : 0), x, y, false);
        break;
    case SprungMouseButtonX1:
        send_mouse(session, PTR_XFLAGS_BUTTON1 | (down ? PTR_XFLAGS_DOWN : 0), x, y, true);
        break;
    case SprungMouseButtonX2:
        send_mouse(session, PTR_XFLAGS_BUTTON2 | (down ? PTR_XFLAGS_DOWN : 0), x, y, true);
        break;
    }
    input_end(session);
}

// Sends `delta` in steps of at most one notch; the 9-bit rotation field is two's complement.
static void send_wheel_axis(SprungSession *session, UINT16 axisFlag, int32_t delta, int32_t x, int32_t y) {
    while (delta != 0) {
        const int32_t step = delta > WHEEL_NOTCH ? WHEEL_NOTCH
                             : (delta < -WHEEL_NOTCH ? -WHEEL_NOTCH : delta);
        const UINT16 rotation = (UINT16)step & WheelRotationMask;
        send_mouse(session, axisFlag | rotation, x, y, false);
        delta -= step;
    }
}

void sprung_session_send_mouse_wheel(SprungSession *session, int32_t vertical, int32_t horizontal,
                                     int32_t x, int32_t y) {
    if (!input_begin(session))
        return;
    send_wheel_axis(session, PTR_FLAGS_WHEEL, vertical, x, y);
    send_wheel_axis(session, PTR_FLAGS_HWHEEL, horizontal, x, y);
    input_end(session);
}

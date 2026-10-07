// Dynamic resolution through the display control channel (MS-RDPEDISP).
#include "sprung_internal.h"

#include <winpr/sysinfo.h>
#include <winpr/wlog.h>

// A resize the server never answers (e.g. identical layout) must not block later requests.
#define RESIZE_ANSWER_TIMEOUT_MS 1500
#define RESIZE_POLL_MS 50
// A layout the server ignored is resent a few times.
#define RESIZE_MAX_RETRIES 3
// Layouts sent right after the display-control caps are dropped too; wait this long first.
#define RESIZE_CAPS_SETTLE_MS 1000

// Only the size we asked for counts as the answer: the initial graphics reset can arrive after
// an early request and must not end the wait (the request may have been dropped).
void sprung_resolution_answered(SprungSession *session, uint32_t width, uint32_t height) {
    pthread_mutex_lock(&session->displayLock);
    if (width == session->sentLayout.Width && height == session->sentLayout.Height)
        session->resizeInFlight = false;
    pthread_mutex_unlock(&session->displayLock);
    (void)SetEvent(session->wakeEvent);
}

static UINT on_display_control_caps(DispClientContext *disp, UINT32 maxMonitors, UINT32 factorA,
                                    UINT32 factorB) {
    (void)factorA;
    (void)factorB;
    SprungSession *session = disp->custom;
    pthread_mutex_lock(&session->displayLock);
    session->dispReady = true;
    session->dispReadyAtMs = GetTickCount64();
    pthread_mutex_unlock(&session->displayLock);
    WLog_INFO(SPRUNG_TAG, "display control ready (max %" PRIu32 " monitors)", maxMonitors);
    (void)SetEvent(session->wakeEvent);
    return CHANNEL_RC_OK;
}

void sprung_resolution_channel_connected(SprungSession *session, DispClientContext *disp) {
    pthread_mutex_lock(&session->displayLock);
    disp->custom = session;
    disp->DisplayControlCaps = on_display_control_caps;
    session->disp = disp;
    session->dispReady = false;
    pthread_mutex_unlock(&session->displayLock);
}

void sprung_resolution_channel_disconnected(SprungSession *session) {
    pthread_mutex_lock(&session->displayLock);
    session->disp = NULL;
    session->dispReady = false;
    pthread_mutex_unlock(&session->displayLock);
}

static uint32_t clamp_size(uint32_t value) {
    return value < 200 ? 200 : (value > 8192 ? 8192 : value);
}

void sprung_session_set_resolution(SprungSession *session, uint32_t width, uint32_t height,
                                   uint32_t desktopScaleFactor, uint32_t deviceScaleFactor) {
    if (!session)
        return;
    const DISPLAY_CONTROL_MONITOR_LAYOUT layout = {
        .Flags = DISPLAY_CONTROL_MONITOR_PRIMARY,
        .Width = clamp_size(width) & ~1u,
        .Height = clamp_size(height),
        .Orientation = ORIENTATION_LANDSCAPE,
        .DesktopScaleFactor = desktopScaleFactor < 100 ? 100 : (desktopScaleFactor > 500 ? 500 : desktopScaleFactor),
        .DeviceScaleFactor = deviceScaleFactor ? deviceScaleFactor : 100,
    };
    pthread_mutex_lock(&session->displayLock);
    session->pendingLayout = layout;
    session->resizePending = true;
    session->resizeRetries = 0;
    pthread_mutex_unlock(&session->displayLock);
    (void)SetEvent(session->wakeEvent);
}

static bool layout_is_current(SprungSession *session, const DISPLAY_CONTROL_MONITOR_LAYOUT *layout) {
    const rdpSettings *settings = session->context->settings;
    return layout->Width == freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth) &&
           layout->Height == freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight) &&
           layout->DesktopScaleFactor == session->desktopScaleFactor &&
           layout->DeviceScaleFactor == session->deviceScaleFactor;
}

void sprung_resolution_service(SprungSession *session) {
    pthread_mutex_lock(&session->displayLock);
    const uint64_t now = GetTickCount64();
    if (session->resizeInFlight && now - session->resizeSentAtMs >= RESIZE_ANSWER_TIMEOUT_MS) {
        session->resizeInFlight = false;
        if (!session->resizePending && session->resizeRetries < RESIZE_MAX_RETRIES) {
            session->resizeRetries++;
            session->pendingLayout = session->sentLayout;
            session->resizePending = true;
            WLog_INFO(SPRUNG_TAG, "no answer to the resize request, retry %u", session->resizeRetries);
        }
    }

    const bool settled = session->dispReady && now - session->dispReadyAtMs >= RESIZE_CAPS_SETTLE_MS;
    if (session->resizePending && session->disp && settled && !session->resizeInFlight) {
        DISPLAY_CONTROL_MONITOR_LAYOUT layout = session->pendingLayout;
        session->resizePending = false;
        if (!layout_is_current(session, &layout)) {
            WLog_INFO(SPRUNG_TAG, "requesting desktop %" PRIu32 "x%" PRIu32 " at %" PRIu32 "%%", layout.Width,
                      layout.Height, layout.DesktopScaleFactor);
            const UINT rc = session->disp->SendMonitorLayout(session->disp, 1, &layout);
            if (rc == CHANNEL_RC_OK) {
                session->resizeInFlight = true;
                session->resizeSentAtMs = now;
                session->sentLayout = layout;
                session->desktopScaleFactor = layout.DesktopScaleFactor;
                session->deviceScaleFactor = layout.DeviceScaleFactor;
            } else {
                WLog_WARN(SPRUNG_TAG, "SendMonitorLayout failed: 0x%08x", rc);
            }
        }
    }
    pthread_mutex_unlock(&session->displayLock);
}

DWORD sprung_resolution_wait_timeout(SprungSession *session) {
    pthread_mutex_lock(&session->displayLock);
    // Poll while a resize waits for its answer or for the caps to settle; all else sets wakeEvent.
    const bool polling = session->resizeInFlight || (session->resizePending && session->dispReady);
    pthread_mutex_unlock(&session->displayLock);
    return polling ? RESIZE_POLL_MS : INFINITE;
}

// The connection thread: connect, run the event loop, reconnect after a network drop, report the end.
//
// Reconnects reuse the FreeRDP context (freerdp_reconnect, as FreeRDP's own clients do): the
// framebuffer and settings survive, channels are torn down and come up again, and the server
// takes the client back into the same Windows session with the auto-reconnect cookie.
#include "sprung_internal.h"

#include <stdio.h>

#include <freerdp/error.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>

#define RECONNECT_MAX_ATTEMPTS 10

/// Wait before attempt n: 1, 2, 4, 8, then 15 s. A failed attempt itself can take up to the
/// TCP connect timeout (15 s) when the host does not answer.
static DWORD reconnect_delay_ms(uint32_t attempt) {
    return attempt >= 5 ? 15000 : 1000u << (attempt - 1);
}

static void run_event_loop(SprungSession *session) {
    rdpContext *context = session->context;
    HANDLE handles[MAXIMUM_WAIT_OBJECTS] = { 0 };

    while (!freerdp_shall_disconnect_context(context) && !atomic_load(&session->stopRequested)) {
        DWORD count = freerdp_get_event_handles(context, handles, ARRAYSIZE(handles) - 2);
        if (count == 0) {
            WLog_ERR(SPRUNG_TAG, "freerdp_get_event_handles failed");
            break;
        }
        handles[count++] = session->wakeEvent;
        handles[count++] = session->stopEvent;

        if (WaitForMultipleObjects(count, handles, FALSE, sprung_resolution_wait_timeout(session)) ==
            WAIT_FAILED) {
            WLog_ERR(SPRUNG_TAG, "WaitForMultipleObjects failed");
            break;
        }
        if (!freerdp_check_event_handles(context)) {
            if (freerdp_get_last_error(context) == FREERDP_ERROR_SUCCESS)
                WLog_ERR(SPRUNG_TAG, "freerdp_check_event_handles failed");
            break;
        }
        (void)ResetEvent(session->wakeEvent);
        sprung_resolution_service(session);
    }
}

/// Waits `ms` unless the session is stopped meanwhile; true if it was stopped.
static bool wait_or_stop(SprungSession *session, DWORD ms) {
    return WaitForSingleObject(session->stopEvent, ms) == WAIT_OBJECT_0 || atomic_load(&session->stopRequested);
}

static bool worth_retrying(SprungDisconnectReason reason) {
    switch (reason) {
    case SprungDisconnectHostUnreachable:
    case SprungDisconnectConnectionLost:
    case SprungDisconnectServerEnded:
    case SprungDisconnectTimeout:
    case SprungDisconnectOther:
        return true;
    default:
        return false;
    }
}

/// Tries to get the session back; true when it is up again.
static bool reconnect(SprungSession *session) {
    freerdp *instance = session->context->instance;
    const SprungCallbacks *cb = &session->callbacks;
    for (uint32_t attempt = 1; attempt <= RECONNECT_MAX_ATTEMPTS; attempt++) {
        if (cb->reconnecting)
            cb->reconnecting(cb->userData, attempt);
        if (wait_or_stop(session, reconnect_delay_ms(attempt)))
            return false;
        WLog_INFO(SPRUNG_TAG, "reconnect attempt %" PRIu32, attempt);
        const bool up = freerdp_reconnect(instance);
        if (atomic_load(&session->stopRequested))
            return false;
        if (up)
            return true;
        const uint32_t error = freerdp_get_last_error(session->context);
        WLog_INFO(SPRUNG_TAG, "reconnect attempt %" PRIu32 " failed: %s", attempt, freerdp_get_last_error_name(error));
        if (!worth_retrying(sprung_disconnect_reason(session, error, false)))
            return false;
    }
    return false;
}

static void report_disconnect(SprungSession *session, uint32_t error, bool wasConnected, bool reconnecting) {
    const SprungCallbacks *cb = &session->callbacks;
    if (!cb->disconnected)
        return;
    SprungDisconnectReason reason = sprung_disconnect_reason(session, error, wasConnected);
    // Giving up on reconnecting: the session was lost, whatever the last attempt said.
    if (reconnecting && worth_retrying(reason))
        reason = SprungDisconnectConnectionLost;
    if (reason == SprungDisconnectRequested) {
        cb->disconnected(cb->userData, reason, 0, "disconnected");
        return;
    }
    char detail[512];
    snprintf(detail, sizeof(detail), "%s (%s, 0x%08x)", freerdp_get_last_error_string(error),
             freerdp_get_last_error_name(error), error);
    cb->disconnected(cb->userData, reason, error, detail);
}

void *sprung_session_thread(void *arg) {
    SprungSession *session = arg;
    freerdp *instance = session->context->instance;
    const SprungCallbacks *cb = &session->callbacks;

    const bool connected = freerdp_connect(instance);
    bool reconnecting = false;
    if (connected) {
        sprung_input_set_ready(session, true);
        if (cb->connected)
            cb->connected(cb->userData);
        for (;;) {
            run_event_loop(session);
            const uint32_t error = freerdp_get_last_error(session->context);
            if (!session->autoReconnect || !sprung_disconnect_is_network_loss(session, error))
                break;
            WLog_WARN(SPRUNG_TAG, "connection lost (%s), reconnecting", freerdp_get_last_error_name(error));
            sprung_input_set_ready(session, false);
            reconnecting = true;
            if (!reconnect(session))
                break;
            reconnecting = false;
            sprung_input_set_ready(session, true);
            if (cb->reconnected)
                cb->reconnected(cb->userData);
        }
    }

    const uint32_t error = freerdp_get_last_error(session->context);
    sprung_input_set_ready(session, false);
    (void)freerdp_disconnect(instance);
    report_disconnect(session, error, connected, reconnecting);
    return NULL;
}

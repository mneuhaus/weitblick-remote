// Private session state shared by the bridge's translation units.
#ifndef WB_INTERNAL_H
#define WB_INTERNAL_H

#include "WeitblickBridge.h"

#include <pthread.h>
#include <stdatomic.h>

#include <freerdp/client.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/disp.h>
#include <freerdp/codec/region.h>
#include <freerdp/freerdp.h>

#define WB_TAG "weitblick.bridge"

typedef struct {
    rdpClientContext common; // must stay first: FreeRDP casts rdpContext* to this
    WBSession *session;
} WBContext;

struct WBSession {
    WBCallbacks callbacks;
    rdpContext *context;

    pthread_t thread;
    bool threadStarted;
    HANDLE wakeEvent; // wakes the event loop for pending display work
    // Set by wb_session_disconnect. FreeRDP's own abort flag is reset by every reconnect
    // attempt, so the request is remembered here as well.
    HANDLE stopEvent;
    atomic_bool stopRequested;
    bool autoReconnect;
    atomic_bool certificateRejected;

    // Input may be sent only between connect and disconnect.
    pthread_mutex_t inputLock;
    bool inputReady;
    uint8_t keysDown[512 / 8]; // bit per (code | extended << 8)

    // Guarded by the FreeRDP update lock (rdp_update_lock), like the GDI framebuffer.
    REGION16 dirty;
    WBRect *rectScratch;
    size_t rectScratchCapacity;
    atomic_bool framePending;

    // Display control. Written from the channel threads and the API, read by the event loop.
    pthread_mutex_t displayLock;
    DispClientContext *disp;
    bool dispReady;
    uint64_t dispReadyAtMs;
    bool resizePending;
    DISPLAY_CONTROL_MONITOR_LAYOUT pendingLayout;
    bool resizeInFlight;
    uint64_t resizeSentAtMs;
    DISPLAY_CONTROL_MONITOR_LAYOUT sentLayout; // resent if the server does not answer
    unsigned resizeRetries;
    uint32_t desktopScaleFactor; // last scale the server was asked for
    uint32_t deviceScaleFactor;

    atomic_uint_fast64_t nextPointerId;

    // Clipboard channel, set while it is connected.
    pthread_mutex_t clipboardLock;
    CliprdrClientContext *cliprdr;
};

static inline WBSession *wb_session_from_context(rdpContext *context) {
    return context ? ((WBContext *)context)->session : NULL;
}

// wb_session_thread.c
void *wb_session_thread(void *arg);

// wb_display.c
bool wb_display_install(WBSession *session);   // PostConnect: GDI, pointers, update hooks
void wb_display_uninstall(WBSession *session); // PostDisconnect

// wb_pointer.c
void wb_pointer_register(rdpContext *context);

// wb_resolution.c
void wb_resolution_channel_connected(WBSession *session, DispClientContext *disp);
void wb_resolution_channel_disconnected(WBSession *session);
void wb_resolution_answered(WBSession *session, uint32_t width, uint32_t height);
void wb_resolution_service(WBSession *session);       // event loop: send pending layout
DWORD wb_resolution_wait_timeout(WBSession *session); // event loop wait in ms

// wb_input.c
void wb_input_set_ready(WBSession *session, bool ready);

// wb_clipboard.c
void wb_clipboard_channel_connected(WBSession *session, CliprdrClientContext *cliprdr);
void wb_clipboard_channel_disconnected(WBSession *session);

// wb_disconnect.c
/// Why the session ended, from FreeRDP's last error. `wasConnected`: the session had been up.
WBDisconnectReason wb_disconnect_reason(WBSession *session, uint32_t error, bool wasConnected);
/// Whether a dropped session should be reconnected (network loss, not a deliberate end).
bool wb_disconnect_is_network_loss(WBSession *session, uint32_t error);

// wb_settings.c
bool wb_settings_apply(rdpSettings *settings, const WBSessionConfig *config);

// wb_redirection.c
/// Drives, printers, audio and microphone settings.
bool wb_redirection_apply(rdpSettings *settings, const WBSessionConfig *config);

static inline uint32_t wb_clamp_u32(uint32_t value, uint32_t min, uint32_t max) {
    return value < min ? min : (value > max ? max : value);
}

#endif

// Private session state shared by the bridge's translation units.
#ifndef SPRUNG_INTERNAL_H
#define SPRUNG_INTERNAL_H

#include "SprungBridge.h"

#include <pthread.h>
#include <stdatomic.h>

#include <freerdp/client.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/disp.h>
#include <freerdp/codec/region.h>
#include <freerdp/freerdp.h>

#define SPRUNG_TAG "sprung.bridge"

typedef struct {
    rdpClientContext common; // must stay first: FreeRDP casts rdpContext* to this
    SprungSession *session;
} SprungContext;

struct SprungSession {
    SprungCallbacks callbacks;
    rdpContext *context;

    pthread_t thread;
    bool threadStarted;
    HANDLE wakeEvent; // wakes the event loop for pending display work
    // Set by sprung_session_disconnect. FreeRDP's own abort flag is reset by every reconnect
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
    SprungRect *rectScratch;
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

static inline SprungSession *sprung_session_from_context(rdpContext *context) {
    return context ? ((SprungContext *)context)->session : NULL;
}

// sprung_session_thread.c
void *sprung_session_thread(void *arg);

// sprung_display.c
bool sprung_display_install(SprungSession *session);   // PostConnect: GDI, pointers, update hooks
void sprung_display_uninstall(SprungSession *session); // PostDisconnect

// sprung_pointer.c
void sprung_pointer_register(rdpContext *context);

// sprung_resolution.c
void sprung_resolution_channel_connected(SprungSession *session, DispClientContext *disp);
void sprung_resolution_channel_disconnected(SprungSession *session);
void sprung_resolution_answered(SprungSession *session, uint32_t width, uint32_t height);
void sprung_resolution_service(SprungSession *session);       // event loop: send pending layout
DWORD sprung_resolution_wait_timeout(SprungSession *session); // event loop wait in ms

// sprung_input.c
void sprung_input_set_ready(SprungSession *session, bool ready);

// sprung_clipboard.c
void sprung_clipboard_channel_connected(SprungSession *session, CliprdrClientContext *cliprdr);
void sprung_clipboard_channel_disconnected(SprungSession *session);

// sprung_disconnect.c
/// Why the session ended, from FreeRDP's last error. `wasConnected`: the session had been up.
SprungDisconnectReason sprung_disconnect_reason(SprungSession *session, uint32_t error, bool wasConnected);
/// Whether a dropped session should be reconnected (network loss, not a deliberate end).
bool sprung_disconnect_is_network_loss(SprungSession *session, uint32_t error);

// sprung_settings.c
bool sprung_settings_apply(rdpSettings *settings, const SprungSessionConfig *config);

// sprung_redirection.c
/// Drives, printers, audio and microphone settings.
bool sprung_redirection_apply(rdpSettings *settings, const SprungSessionConfig *config);

static inline uint32_t sprung_clamp_u32(uint32_t value, uint32_t min, uint32_t max) {
    return value < min ? min : (value > max ? max : value);
}

#endif

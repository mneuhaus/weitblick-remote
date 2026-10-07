// SprungBridge: a small C API around libfreerdp for the Sprung app.
//
// Threading: every session runs its own event-loop thread. Callbacks fire on that
// thread and must return quickly (no blocking on the main thread). All other
// functions may be called from any thread; input functions are no-ops unless the
// session is connected.
#ifndef SPRUNG_BRIDGE_H
#define SPRUNG_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SprungSession SprungSession;

typedef struct {
    const char *host;
    uint16_t port;
    const char *username;
    const char *domain;
    const char *password;
    /// Initial desktop size in remote pixels.
    uint32_t width;
    uint32_t height;
    /// Windows DPI scale in percent (100…500), e.g. 200 for a Retina window.
    uint32_t desktopScaleFactor;
    /// 100, 140 or 180.
    uint32_t deviceScaleFactor;
    /// Windows keyboard layout id (KLID), e.g. 0x0407 for German.
    uint32_t keyboardLayout;
    bool ignoreCertificate;
    bool audioPlayback;
    /// Directory for FreeRDP's own state (certificate and license stores). Keeps Sprung
    /// away from ~/.config/freerdp; NULL uses that default.
    const char *stateDirectory;
} SprungSessionConfig;

typedef struct {
    int32_t x;
    int32_t y;
    int32_t width;
    int32_t height;
} SprungRect;

typedef struct {
    const char *host;
    uint16_t port;
    const char *commonName;
    const char *subject;
    const char *issuer;
    /// SHA-256 fingerprint as colon-separated hex.
    const char *fingerprint;
    /// True if the server presented a different certificate than the stored one.
    bool changed;
} SprungCertificateInfo;

typedef struct {
    void *userData;
    /// Connection is up; input may be sent from now on.
    void (*connected)(void *userData);
    /// Session ended. `errorCode` is the FreeRDP last error (0 for a clean, user-initiated
    /// disconnect); `message` is a readable reason, valid only during the call.
    void (*disconnected)(void *userData, uint32_t errorCode, const char *message);
    /// New pixels are available. Coalesced: fires once until the framebuffer is acquired.
    void (*frameReady)(void *userData);
    /// The remote desktop changed size (pixels).
    void (*desktopResized)(void *userData, uint32_t width, uint32_t height);
    /// A new server cursor. `bgra` is BGRA32 with straight alpha, top-down, `width * 4` bytes
    /// per row, valid only during the call.
    void (*pointerNew)(void *userData, uint64_t pointerId, const uint8_t *bgra, uint32_t width,
                       uint32_t height, uint32_t hotspotX, uint32_t hotspotY);
    void (*pointerFree)(void *userData, uint64_t pointerId);
    void (*pointerSet)(void *userData, uint64_t pointerId);
    /// The server hides the cursor.
    void (*pointerSetNull)(void *userData);
    /// The server wants the system default cursor.
    void (*pointerSetDefault)(void *userData);
    /// The server moved the cursor (remote pixels).
    void (*pointerPosition)(void *userData, uint32_t x, uint32_t y);
    /// Return true to accept the certificate for this session only. NULL accepts.
    bool (*verifyCertificate)(void *userData, const SprungCertificateInfo *info);
} SprungCallbacks;

/// Locked view of the framebuffer, see sprung_session_framebuffer_acquire.
typedef struct {
    const uint8_t *pixels; ///< BGRA32, top-down
    uint32_t width;
    uint32_t height;
    uint32_t stride; ///< bytes per row
    /// Regions changed since the previous acquire, clipped to the framebuffer.
    const SprungRect *dirtyRects;
    size_t dirtyRectCount;
} SprungFramebuffer;

typedef enum {
    SprungMouseButtonLeft = 0,
    SprungMouseButtonRight = 1,
    SprungMouseButtonMiddle = 2,
    SprungMouseButtonX1 = 3, ///< "back"
    SprungMouseButtonX2 = 4, ///< "forward"
} SprungMouseButton;

/// Creates a session; nothing happens on the network until sprung_session_connect.
/// Strings are copied. Returns NULL on invalid config or allocation failure.
SprungSession *sprung_session_create(const SprungSessionConfig *config,
                                     const SprungCallbacks *callbacks);

/// Starts the event-loop thread, which connects and then runs the session.
bool sprung_session_connect(SprungSession *session);

/// Asks the session to end (also aborts a connect in progress). Returns immediately;
/// `disconnected` fires once the session is down.
void sprung_session_disconnect(SprungSession *session);

/// Disconnects if needed, joins the event-loop thread and frees everything.
/// No callback fires after this returns. Must not be called from a callback.
void sprung_session_destroy(SprungSession *session);

/// Locks the framebuffer for reading and hands over the dirty rects collected since the
/// previous call. Returns false (and nothing is locked) if there is no framebuffer yet.
/// Keep the lock short: decoding waits for it.
bool sprung_session_framebuffer_acquire(SprungSession *session, SprungFramebuffer *out);
void sprung_session_framebuffer_release(SprungSession *session);

/// Requests a new remote desktop size via the display-control channel. Width is rounded
/// down to an even value, both are clamped to 200…8192. The latest request wins; it is sent
/// once the channel is ready and no earlier resize is still in flight. Debounce in the caller.
void sprung_session_set_resolution(SprungSession *session, uint32_t width, uint32_t height,
                                   uint32_t desktopScaleFactor, uint32_t deviceScaleFactor);

// Keyboard. Scancodes are PC/AT set 1 make codes (0x01…0x7F) plus the extended (E0) flag.
// Pause/Break is (0x46, extended), as in FreeRDP; it is sent as the E1 sequence on key-down.
// A key-down for a key that is already down is sent as a repeat. Key-ups for keys that are
// not down are dropped.
void sprung_session_send_scancode(SprungSession *session, uint16_t code, bool extended, bool down);
/// UTF-16 code unit; characters outside the BMP need two calls (surrogate pair).
void sprung_session_send_unicode(SprungSession *session, uint16_t codeUnit, bool down);
/// Sets the remote lock-key state (synchronize event).
void sprung_session_send_sync(SprungSession *session, bool capsLock, bool numLock, bool scrollLock);
/// Sends key-up for every scancode currently down.
void sprung_session_release_all_keys(SprungSession *session);

// Mouse. Coordinates are remote pixels and get clamped to the desktop.
void sprung_session_send_mouse_move(SprungSession *session, int32_t x, int32_t y);
void sprung_session_send_mouse_button(SprungSession *session, SprungMouseButton button, bool down,
                                      int32_t x, int32_t y);
/// Wheel deltas in Windows units (120 = one notch). Positive vertical scrolls up (away from
/// the user), positive horizontal scrolls right. Large deltas are split into several events.
void sprung_session_send_mouse_wheel(SprungSession *session, int32_t vertical, int32_t horizontal,
                                     int32_t x, int32_t y);

#ifdef __cplusplus
}
#endif

#endif

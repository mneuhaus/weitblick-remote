// Session lifecycle: settings, create/connect/disconnect/destroy, auth and certificate hooks.
// The connection itself runs in sprung_session_thread.c.
#include "sprung_internal.h"

#include <signal.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/channels/channels.h>
#include <freerdp/client/channels.h>
#include <freerdp/constants.h>
#include <freerdp/event.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>

static void ignore_sigpipe(void) {
    // A write to a socket the server already closed must not kill the app.
    signal(SIGPIPE, SIG_IGN);
}

static void on_channel_connected(void *context, const ChannelConnectedEventArgs *e) {
    SprungSession *session = sprung_session_from_context(context);
    if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
        sprung_resolution_channel_connected(session, (DispClientContext *)e->pInterface);
    else if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
        sprung_clipboard_channel_connected(session, (CliprdrClientContext *)e->pInterface);
    else
        freerdp_client_OnChannelConnectedEventHandler(context, e);
}

static void on_channel_disconnected(void *context, const ChannelDisconnectedEventArgs *e) {
    SprungSession *session = sprung_session_from_context(context);
    if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
        sprung_resolution_channel_disconnected(session);
    else if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
        sprung_clipboard_channel_disconnected(session);
    else
        freerdp_client_OnChannelDisconnectedEventHandler(context, e);
}

static BOOL on_pre_connect(freerdp *instance) {
    rdpContext *context = instance->context;
    if (PubSub_SubscribeChannelConnected(context->pubSub, on_channel_connected) < 0)
        return FALSE;
    if (PubSub_SubscribeChannelDisconnected(context->pubSub, on_channel_disconnected) < 0)
        return FALSE;
    return TRUE;
}

static BOOL on_post_connect(freerdp *instance) {
    return sprung_display_install(sprung_session_from_context(instance->context));
}

static void on_post_disconnect(freerdp *instance) {
    rdpContext *context = instance->context;
    PubSub_UnsubscribeChannelConnected(context->pubSub, on_channel_connected);
    PubSub_UnsubscribeChannelDisconnected(context->pubSub, on_channel_disconnected);
    sprung_display_uninstall(sprung_session_from_context(context));
}

// Credentials come from the config; the app asks the user before connecting. FreeRDP only asks
// when they are missing, which ends the connection with "missing credentials".
static BOOL on_authenticate(freerdp *instance, char **username, char **password, char **domain,
                            rdp_auth_reason reason) {
    (void)username;
    (void)password;
    (void)domain;
    WLog_WARN(SPRUNG_TAG, "server asked for credentials (reason %d), none configured", (int)reason);
    freerdp_set_last_error_if_not(instance->context, FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS);
    return FALSE;
}

static DWORD verify_certificate(freerdp *instance, const char *host, UINT16 port,
                                const char *commonName, const char *subject, const char *issuer,
                                const char *fingerprint, DWORD flags) {
    SprungSession *session = sprung_session_from_context(instance->context);
    const SprungCertificateInfo info = {
        .host = host,
        .port = port,
        .commonName = commonName,
        .subject = subject,
        .issuer = issuer,
        .fingerprint = fingerprint,
        .hostnameMismatch = (flags & VERIFY_CERT_FLAG_MISMATCH) != 0,
    };
    const SprungCallbacks *cb = &session->callbacks;
    const bool accept = cb->verifyCertificate ? cb->verifyCertificate(cb->userData, &info) : true;
    if (!accept)
        atomic_store(&session->certificateRejected, true);
    return accept ? 2 : 0; // 2 = accept for this session only, never store in FreeRDP's store
}

static DWORD on_verify_certificate(freerdp *instance, const char *host, UINT16 port,
                                   const char *commonName, const char *subject, const char *issuer,
                                   const char *fingerprint, DWORD flags) {
    return verify_certificate(instance, host, port, commonName, subject, issuer, fingerprint, flags);
}

// Only reached through a stale entry in FreeRDP's store (Sprung never writes one). The app judges
// changes itself, against the fingerprints it trusts.
static DWORD on_verify_changed_certificate(freerdp *instance, const char *host, UINT16 port,
                                           const char *commonName, const char *subject,
                                           const char *issuer, const char *newFingerprint,
                                           const char *oldSubject, const char *oldIssuer,
                                           const char *oldFingerprint, DWORD flags) {
    (void)oldSubject;
    (void)oldIssuer;
    (void)oldFingerprint;
    return verify_certificate(instance, host, port, commonName, subject, issuer, newFingerprint, flags);
}

static BOOL on_client_new(freerdp *instance, rdpContext *context) {
    (void)context;
    instance->PreConnect = on_pre_connect;
    instance->PostConnect = on_post_connect;
    instance->PostDisconnect = on_post_disconnect;
    instance->AuthenticateEx = on_authenticate;
    instance->VerifyCertificateEx = on_verify_certificate;
    instance->VerifyChangedCertificateEx = on_verify_changed_certificate;
    return TRUE;
}

static uint32_t clamp_u32(uint32_t value, uint32_t min, uint32_t max) {
    return value < min ? min : (value > max ? max : value);
}

static bool apply_config(rdpSettings *s, const SprungSessionConfig *c) {
    const uint32_t width = clamp_u32(c->width, 200, 8192) & ~1u;
    const uint32_t height = clamp_u32(c->height, 200, 8192);
    if (c->stateDirectory && !freerdp_settings_set_string(s, FreeRDP_ConfigPath, c->stateDirectory))
        return false;
    return freerdp_settings_set_string(s, FreeRDP_ServerHostname, c->host) &&
           freerdp_settings_set_uint32(s, FreeRDP_ServerPort, c->port ? c->port : 3389) &&
           freerdp_settings_set_string(s, FreeRDP_Username, c->username) &&
           freerdp_settings_set_string(s, FreeRDP_Password, c->password) &&
           freerdp_settings_set_string(s, FreeRDP_Domain, c->domain) &&
           freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, width) &&
           freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, height) &&
           freerdp_settings_set_uint32(s, FreeRDP_DesktopScaleFactor,
                                       clamp_u32(c->desktopScaleFactor, 100, 500)) &&
           freerdp_settings_set_uint32(s, FreeRDP_DeviceScaleFactor,
                                       c->deviceScaleFactor ? c->deviceScaleFactor : 100) &&
           freerdp_settings_set_uint32(s, FreeRDP_KeyboardLayout, c->keyboardLayout) &&
           freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32) &&
           freerdp_settings_set_bool(s, FreeRDP_IgnoreCertificate, c->ignoreCertificate) &&
           freerdp_settings_set_bool(s, FreeRDP_CertificateCallbackPreferPEM, FALSE) &&
           sprung_redirection_apply(s, c) &&
           freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, c->clipboard) &&
           // Reconnects run in sprung_session_thread.c; the flag makes the server send its cookie.
           freerdp_settings_set_bool(s, FreeRDP_AutoReconnectionEnabled, c->autoReconnect) &&
           // Graphics pipeline with the codecs we can decode in software. No AVC: there is no
           // H.264 decoder in this build, so rdpgfx advertises AVC_DISABLED.
           freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, TRUE) &&
           freerdp_settings_set_bool(s, FreeRDP_GfxH264, FALSE) &&
           freerdp_settings_set_bool(s, FreeRDP_GfxAVC444, FALSE) &&
           freerdp_settings_set_bool(s, FreeRDP_GfxAVC444v2, FALSE) &&
           freerdp_settings_set_bool(s, FreeRDP_GfxProgressive, TRUE) &&
           freerdp_settings_set_bool(s, FreeRDP_GfxProgressiveV2, TRUE) &&
           freerdp_settings_set_bool(s, FreeRDP_GfxPlanar, TRUE) &&
           freerdp_settings_set_bool(s, FreeRDP_RemoteFxCodec, TRUE) &&
           freerdp_settings_set_bool(s, FreeRDP_SupportDisplayControl, TRUE) &&
           freerdp_settings_set_bool(s, FreeRDP_DynamicResolutionUpdate, TRUE) &&
           freerdp_set_connection_type(s, CONNECTION_TYPE_AUTODETECT) &&
           freerdp_settings_set_uint32(s, FreeRDP_OsMajorType, OSMAJORTYPE_MACINTOSH) &&
           freerdp_settings_set_uint32(s, FreeRDP_OsMinorType, OSMINORTYPE_MACINTOSH);
}

SprungSession *sprung_session_create(const SprungSessionConfig *config,
                                     const SprungCallbacks *callbacks) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, ignore_sigpipe);

    if (!config || !callbacks || !config->host || !config->host[0])
        return NULL;

    SprungSession *session = calloc(1, sizeof(*session));
    if (!session)
        return NULL;
    session->callbacks = *callbacks;
    session->autoReconnect = config->autoReconnect;
    session->desktopScaleFactor = clamp_u32(config->desktopScaleFactor, 100, 500);
    session->deviceScaleFactor = config->deviceScaleFactor ? config->deviceScaleFactor : 100;
    pthread_mutex_init(&session->inputLock, NULL);
    pthread_mutex_init(&session->displayLock, NULL);
    pthread_mutex_init(&session->clipboardLock, NULL);
    region16_init(&session->dirty);

    RDP_CLIENT_ENTRY_POINTS entry = { 0 };
    entry.Version = RDP_CLIENT_INTERFACE_VERSION;
    entry.Size = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
    entry.ContextSize = sizeof(SprungContext);
    entry.ClientNew = on_client_new;

    session->context = freerdp_client_context_new(&entry);
    session->wakeEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    session->stopEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!session->context || !session->wakeEvent || !session->stopEvent) {
        sprung_session_destroy(session);
        return NULL;
    }
    ((SprungContext *)session->context)->session = session;

    if (!apply_config(session->context->settings, config)) {
        WLog_ERR(SPRUNG_TAG, "applying settings failed");
        sprung_session_destroy(session);
        return NULL;
    }
    return session;
}

bool sprung_session_connect(SprungSession *session) {
    if (!session || session->threadStarted)
        return false;
    if (pthread_create(&session->thread, NULL, sprung_session_thread, session) != 0)
        return false;
    session->threadStarted = true;
    return true;
}

void sprung_session_disconnect(SprungSession *session) {
    if (!session || !session->context)
        return;
    atomic_store(&session->stopRequested, true);
    (void)SetEvent(session->stopEvent);
    (void)freerdp_abort_connect_context(session->context);
}

void sprung_session_destroy(SprungSession *session) {
    if (!session)
        return;
    if (session->threadStarted) {
        sprung_session_disconnect(session);
        pthread_join(session->thread, NULL);
    }
    if (session->context)
        freerdp_client_context_free(session->context);
    if (session->wakeEvent)
        (void)CloseHandle(session->wakeEvent);
    if (session->stopEvent)
        (void)CloseHandle(session->stopEvent);
    region16_uninit(&session->dirty);
    free(session->rectScratch);
    pthread_mutex_destroy(&session->displayLock);
    pthread_mutex_destroy(&session->clipboardLock);
    pthread_mutex_destroy(&session->inputLock);
    free(session);
}

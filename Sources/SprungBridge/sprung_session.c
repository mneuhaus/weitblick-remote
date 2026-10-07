// Session lifecycle: settings, connect, event loop, teardown, auth and certificate hooks.
#include "sprung_internal.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/channels/channels.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cmdline.h>
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

// Credentials come from the config. FreeRDP only asks when they are missing, and M1 has no
// prompt yet, so a request means we cannot log in.
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
                                const char *fingerprint, bool changed) {
    SprungSession *session = sprung_session_from_context(instance->context);
    const SprungCertificateInfo info = {
        .host = host,
        .port = port,
        .commonName = commonName,
        .subject = subject,
        .issuer = issuer,
        .fingerprint = fingerprint,
        .changed = changed,
    };
    const SprungCallbacks *cb = &session->callbacks;
    const bool accept = cb->verifyCertificate ? cb->verifyCertificate(cb->userData, &info) : true;
    return accept ? 2 : 0; // 2 = accept for this session only, never store in FreeRDP's store
}

static DWORD on_verify_certificate(freerdp *instance, const char *host, UINT16 port,
                                   const char *commonName, const char *subject, const char *issuer,
                                   const char *fingerprint, DWORD flags) {
    (void)flags;
    return verify_certificate(instance, host, port, commonName, subject, issuer, fingerprint, false);
}

static DWORD on_verify_changed_certificate(freerdp *instance, const char *host, UINT16 port,
                                           const char *commonName, const char *subject,
                                           const char *issuer, const char *newFingerprint,
                                           const char *oldSubject, const char *oldIssuer,
                                           const char *oldFingerprint, DWORD flags) {
    (void)oldSubject;
    (void)oldIssuer;
    (void)oldFingerprint;
    (void)flags;
    return verify_certificate(instance, host, port, commonName, subject, issuer, newFingerprint, true);
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
           freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, c->audioPlayback) &&
           freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, c->clipboard) &&
           freerdp_settings_set_bool(s, FreeRDP_AutoReconnectionEnabled, FALSE) &&
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
    if (!session->context || !session->wakeEvent) {
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

static void report_disconnect(SprungSession *session, uint32_t error) {
    const SprungCallbacks *cb = &session->callbacks;
    if (!cb->disconnected)
        return;
    if (error == FREERDP_ERROR_SUCCESS || error == FREERDP_ERROR_CONNECT_CANCELLED) {
        cb->disconnected(cb->userData, 0, "Disconnected");
        return;
    }
    char message[512];
    snprintf(message, sizeof(message), "%s (%s)", freerdp_get_last_error_string(error),
             freerdp_get_last_error_name(error));
    cb->disconnected(cb->userData, error, message);
}

static void run_event_loop(SprungSession *session) {
    rdpContext *context = session->context;
    HANDLE handles[MAXIMUM_WAIT_OBJECTS] = { 0 };

    while (!freerdp_shall_disconnect_context(context)) {
        DWORD count = freerdp_get_event_handles(context, handles, ARRAYSIZE(handles) - 1);
        if (count == 0) {
            WLog_ERR(SPRUNG_TAG, "freerdp_get_event_handles failed");
            break;
        }
        handles[count++] = session->wakeEvent;

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

static void *session_thread(void *arg) {
    SprungSession *session = arg;
    freerdp *instance = session->context->instance;

    if (freerdp_connect(instance)) {
        sprung_input_set_ready(session, true);
        if (session->callbacks.connected)
            session->callbacks.connected(session->callbacks.userData);
        run_event_loop(session);
    }

    const uint32_t error = freerdp_get_last_error(session->context);
    sprung_input_set_ready(session, false);
    (void)freerdp_disconnect(instance);
    report_disconnect(session, error);
    return NULL;
}

bool sprung_session_connect(SprungSession *session) {
    if (!session || session->threadStarted)
        return false;
    if (pthread_create(&session->thread, NULL, session_thread, session) != 0)
        return false;
    session->threadStarted = true;
    return true;
}

void sprung_session_disconnect(SprungSession *session) {
    if (session && session->context)
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
    region16_uninit(&session->dirty);
    free(session->rectScratch);
    pthread_mutex_destroy(&session->displayLock);
    pthread_mutex_destroy(&session->clipboardLock);
    pthread_mutex_destroy(&session->inputLock);
    free(session);
}

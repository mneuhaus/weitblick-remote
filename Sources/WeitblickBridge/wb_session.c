// Session lifecycle: create/connect/disconnect/destroy, auth and certificate hooks. Settings are in
// wb_settings.c, the connection itself runs in wb_session_thread.c.
#include "wb_internal.h"

#include <signal.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/channels/channels.h>
#include <freerdp/client/channels.h>
#include <freerdp/event.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>

static void ignore_sigpipe(void) {
    // A write to a socket the server already closed must not kill the app.
    signal(SIGPIPE, SIG_IGN);
}

static void on_channel_connected(void *context, const ChannelConnectedEventArgs *e) {
    WBSession *session = wb_session_from_context(context);
    if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
        wb_resolution_channel_connected(session, (DispClientContext *)e->pInterface);
    else if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
        wb_clipboard_channel_connected(session, (CliprdrClientContext *)e->pInterface);
    else
        freerdp_client_OnChannelConnectedEventHandler(context, e);
}

static void on_channel_disconnected(void *context, const ChannelDisconnectedEventArgs *e) {
    WBSession *session = wb_session_from_context(context);
    if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
        wb_resolution_channel_disconnected(session);
    else if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
        wb_clipboard_channel_disconnected(session);
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
    return wb_display_install(wb_session_from_context(instance->context));
}

static void on_post_disconnect(freerdp *instance) {
    rdpContext *context = instance->context;
    PubSub_UnsubscribeChannelConnected(context->pubSub, on_channel_connected);
    PubSub_UnsubscribeChannelDisconnected(context->pubSub, on_channel_disconnected);
    wb_display_uninstall(wb_session_from_context(context));
}

// Credentials come from the config; the app asks the user before connecting. FreeRDP only asks
// when they are missing, which ends the connection with "missing credentials".
static BOOL on_authenticate(freerdp *instance, char **username, char **password, char **domain,
                            rdp_auth_reason reason) {
    (void)username;
    (void)password;
    (void)domain;
    WLog_WARN(WB_TAG, "server asked for credentials (reason %d), none configured", (int)reason);
    freerdp_set_last_error_if_not(instance->context, FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS);
    return FALSE;
}

static DWORD verify_certificate(freerdp *instance, const char *host, UINT16 port,
                                const char *commonName, const char *subject, const char *issuer,
                                const char *fingerprint, DWORD flags) {
    WBSession *session = wb_session_from_context(instance->context);
    const WBCertificateInfo info = {
        .host = host,
        .port = port,
        .commonName = commonName,
        .subject = subject,
        .issuer = issuer,
        .fingerprint = fingerprint,
        .hostnameMismatch = (flags & VERIFY_CERT_FLAG_MISMATCH) != 0,
    };
    const WBCallbacks *cb = &session->callbacks;
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

// Only reached through a stale entry in FreeRDP's store (Weitblick Remote never writes one). The app judges
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

WBSession *wb_session_create(const WBSessionConfig *config,
                                     const WBCallbacks *callbacks) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, ignore_sigpipe);

    if (!config || !callbacks || !config->host || !config->host[0])
        return NULL;

    WBSession *session = calloc(1, sizeof(*session));
    if (!session)
        return NULL;
    session->callbacks = *callbacks;
    session->autoReconnect = config->autoReconnect;
    session->desktopScaleFactor = wb_clamp_u32(config->desktopScaleFactor, 100, 500);
    session->deviceScaleFactor = config->deviceScaleFactor ? config->deviceScaleFactor : 100;
    pthread_mutex_init(&session->inputLock, NULL);
    pthread_mutex_init(&session->displayLock, NULL);
    pthread_mutex_init(&session->clipboardLock, NULL);
    region16_init(&session->dirty);

    RDP_CLIENT_ENTRY_POINTS entry = { 0 };
    entry.Version = RDP_CLIENT_INTERFACE_VERSION;
    entry.Size = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
    entry.ContextSize = sizeof(WBContext);
    entry.ClientNew = on_client_new;

    session->context = freerdp_client_context_new(&entry);
    session->wakeEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    session->stopEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!session->context || !session->wakeEvent || !session->stopEvent) {
        wb_session_destroy(session);
        return NULL;
    }
    ((WBContext *)session->context)->session = session;

    if (!wb_settings_apply(session->context->settings, config)) {
        WLog_ERR(WB_TAG, "applying settings failed");
        wb_session_destroy(session);
        return NULL;
    }
    return session;
}

bool wb_session_connect(WBSession *session) {
    if (!session || session->threadStarted)
        return false;
    if (pthread_create(&session->thread, NULL, wb_session_thread, session) != 0)
        return false;
    session->threadStarted = true;
    return true;
}

void wb_session_disconnect(WBSession *session) {
    if (!session || !session->context)
        return;
    atomic_store(&session->stopRequested, true);
    (void)SetEvent(session->stopEvent);
    (void)freerdp_abort_connect_context(session->context);
}

void wb_session_destroy(WBSession *session) {
    if (!session)
        return;
    if (session->threadStarted) {
        wb_session_disconnect(session);
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

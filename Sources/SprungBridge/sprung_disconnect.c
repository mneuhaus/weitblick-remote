// Classifies why a session ended, so the app can tell a wrong password from a network problem.
#include "sprung_internal.h"

#include <freerdp/error.h>

static SprungDisconnectReason reason_for_error_info(uint32_t info) {
    switch (info) {
    case ERRINFO_IDLE_TIMEOUT:
    case ERRINFO_LOGON_TIMEOUT:
        return SprungDisconnectTimeout;
    case ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION:
        return SprungDisconnectTakenOver;
    case ERRINFO_SERVER_DENIED_CONNECTION:
    case ERRINFO_SERVER_INSUFFICIENT_PRIVILEGES:
        return SprungDisconnectAccessDenied;
    case ERRINFO_SERVER_FRESH_CREDENTIALS_REQUIRED:
        return SprungDisconnectMissingCredentials;
    case ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER:
    case ERRINFO_LOGOFF_BY_USER:
        return SprungDisconnectLoggedOff;
    default:
        return SprungDisconnectServerEnded;
    }
}

static SprungDisconnectReason reason_for_connect_error(uint32_t type, bool wasConnected) {
    switch (type) {
    case ERRCONNECT_DNS_ERROR:
    case ERRCONNECT_DNS_NAME_NOT_FOUND:
    case ERRCONNECT_CONNECT_FAILED:
    case ERRCONNECT_KDC_UNREACHABLE:
        return SprungDisconnectHostUnreachable;
    case ERRCONNECT_CONNECT_TRANSPORT_FAILED:
        return wasConnected ? SprungDisconnectConnectionLost : SprungDisconnectHostUnreachable;
    case ERRCONNECT_AUTHENTICATION_FAILED:
    case ERRCONNECT_LOGON_FAILURE:
    case ERRCONNECT_WRONG_PASSWORD:
        return SprungDisconnectLogonFailed;
    case ERRCONNECT_NO_OR_MISSING_CREDENTIALS:
        return SprungDisconnectMissingCredentials;
    case ERRCONNECT_ACCOUNT_LOCKED_OUT:
        return SprungDisconnectAccountLocked;
    case ERRCONNECT_ACCOUNT_DISABLED:
    case ERRCONNECT_ACCOUNT_EXPIRED:
    case ERRCONNECT_ACCOUNT_RESTRICTION:
    case ERRCONNECT_LOGON_TYPE_NOT_GRANTED:
        return SprungDisconnectAccountRestricted;
    case ERRCONNECT_PASSWORD_EXPIRED:
    case ERRCONNECT_PASSWORD_CERTAINLY_EXPIRED:
    case ERRCONNECT_PASSWORD_MUST_CHANGE:
        return SprungDisconnectPasswordExpired;
    case ERRCONNECT_ACCESS_DENIED:
    case ERRCONNECT_INSUFFICIENT_PRIVILEGES:
    case ERRCONNECT_CLIENT_REVOKED:
        return SprungDisconnectAccessDenied;
    case ERRCONNECT_TLS_CONNECT_FAILED:
    case ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED:
    case ERRCONNECT_MCS_CONNECT_INITIAL_ERROR:
        return SprungDisconnectSecurityFailed;
    case ERRCONNECT_HYBRID_REQUIRED_BY_SERVER:
        return SprungDisconnectNLARequired;
    case ERRCONNECT_ACTIVATION_TIMEOUT:
        return SprungDisconnectTimeout;
    default:
        return SprungDisconnectOther;
    }
}

SprungDisconnectReason sprung_disconnect_reason(SprungSession *session, uint32_t error, bool wasConnected) {
    if (atomic_load(&session->stopRequested))
        return SprungDisconnectRequested;
    // Rejecting the certificate surfaces as a TLS failure.
    if (atomic_load(&session->certificateRejected))
        return SprungDisconnectCertificateRejected;
    if (error == FREERDP_ERROR_SUCCESS)
        return wasConnected ? SprungDisconnectServerEnded : SprungDisconnectOther;
    switch (error >> 16) {
    case FREERDP_ERROR_ERRINFO_CLASS:
        return reason_for_error_info(error & 0xFFFF);
    case FREERDP_ERROR_CONNECT_CLASS:
        return reason_for_connect_error(error & 0xFFFF, wasConnected);
    default:
        return SprungDisconnectOther;
    }
}

bool sprung_disconnect_is_network_loss(SprungSession *session, uint32_t error) {
    if (atomic_load(&session->stopRequested))
        return false;
    // Like FreeRDP's own clients: only when the server sent no reason (or its graphics failed).
    const UINT32 info = freerdp_error_info(session->context->instance);
    if (info != ERRINFO_SUCCESS && info != ERRINFO_GRAPHICS_SUBSYSTEM_FAILED)
        return false;
    switch (sprung_disconnect_reason(session, error, true)) {
    case SprungDisconnectConnectionLost:
    case SprungDisconnectServerEnded: // socket closed without a reason
    case SprungDisconnectTimeout:
    case SprungDisconnectOther:
        return true;
    default:
        return false;
    }
}

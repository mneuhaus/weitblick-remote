// Classifies why a session ended, so the app can tell a wrong password from a network problem.
#include "wb_internal.h"

#include <freerdp/error.h>

static WBDisconnectReason reason_for_error_info(uint32_t info) {
    switch (info) {
    case ERRINFO_IDLE_TIMEOUT:
    case ERRINFO_LOGON_TIMEOUT:
        return WBDisconnectTimeout;
    case ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION:
        return WBDisconnectTakenOver;
    case ERRINFO_SERVER_DENIED_CONNECTION:
    case ERRINFO_SERVER_INSUFFICIENT_PRIVILEGES:
        return WBDisconnectAccessDenied;
    case ERRINFO_SERVER_FRESH_CREDENTIALS_REQUIRED:
        return WBDisconnectMissingCredentials;
    case ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER:
    case ERRINFO_LOGOFF_BY_USER:
        return WBDisconnectLoggedOff;
    default:
        return WBDisconnectServerEnded;
    }
}

static WBDisconnectReason reason_for_connect_error(uint32_t type, bool wasConnected) {
    switch (type) {
    case ERRCONNECT_DNS_ERROR:
    case ERRCONNECT_DNS_NAME_NOT_FOUND:
    case ERRCONNECT_CONNECT_FAILED:
    case ERRCONNECT_KDC_UNREACHABLE:
        return WBDisconnectHostUnreachable;
    case ERRCONNECT_CONNECT_TRANSPORT_FAILED:
        return wasConnected ? WBDisconnectConnectionLost : WBDisconnectHostUnreachable;
    case ERRCONNECT_AUTHENTICATION_FAILED:
    case ERRCONNECT_LOGON_FAILURE:
    case ERRCONNECT_WRONG_PASSWORD:
        return WBDisconnectLogonFailed;
    case ERRCONNECT_NO_OR_MISSING_CREDENTIALS:
        return WBDisconnectMissingCredentials;
    case ERRCONNECT_ACCOUNT_LOCKED_OUT:
        return WBDisconnectAccountLocked;
    case ERRCONNECT_ACCOUNT_DISABLED:
    case ERRCONNECT_ACCOUNT_EXPIRED:
    case ERRCONNECT_ACCOUNT_RESTRICTION:
    case ERRCONNECT_LOGON_TYPE_NOT_GRANTED:
        return WBDisconnectAccountRestricted;
    case ERRCONNECT_PASSWORD_EXPIRED:
    case ERRCONNECT_PASSWORD_CERTAINLY_EXPIRED:
    case ERRCONNECT_PASSWORD_MUST_CHANGE:
        return WBDisconnectPasswordExpired;
    case ERRCONNECT_ACCESS_DENIED:
    case ERRCONNECT_INSUFFICIENT_PRIVILEGES:
    case ERRCONNECT_CLIENT_REVOKED:
        return WBDisconnectAccessDenied;
    case ERRCONNECT_TLS_CONNECT_FAILED:
    case ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED:
    case ERRCONNECT_MCS_CONNECT_INITIAL_ERROR:
        return WBDisconnectSecurityFailed;
    case ERRCONNECT_HYBRID_REQUIRED_BY_SERVER:
        return WBDisconnectNLARequired;
    case ERRCONNECT_ACTIVATION_TIMEOUT:
        return WBDisconnectTimeout;
    default:
        return WBDisconnectOther;
    }
}

WBDisconnectReason wb_disconnect_reason(WBSession *session, uint32_t error, bool wasConnected) {
    if (atomic_load(&session->stopRequested))
        return WBDisconnectRequested;
    // Rejecting the certificate surfaces as a TLS failure.
    if (atomic_load(&session->certificateRejected))
        return WBDisconnectCertificateRejected;
    if (error == FREERDP_ERROR_SUCCESS)
        return wasConnected ? WBDisconnectServerEnded : WBDisconnectOther;
    switch (error >> 16) {
    case FREERDP_ERROR_ERRINFO_CLASS:
        return reason_for_error_info(error & 0xFFFF);
    case FREERDP_ERROR_CONNECT_CLASS:
        return reason_for_connect_error(error & 0xFFFF, wasConnected);
    default:
        return WBDisconnectOther;
    }
}

bool wb_disconnect_is_network_loss(WBSession *session, uint32_t error) {
    if (atomic_load(&session->stopRequested))
        return false;
    // Like FreeRDP's own clients: only when the server sent no reason (or its graphics failed).
    const UINT32 info = freerdp_error_info(session->context->instance);
    if (info != ERRINFO_SUCCESS && info != ERRINFO_GRAPHICS_SUBSYSTEM_FAILED)
        return false;
    switch (wb_disconnect_reason(session, error, true)) {
    case WBDisconnectConnectionLost:
    case WBDisconnectServerEnded: // socket closed without a reason
    case WBDisconnectTimeout:
    case WBDisconnectOther:
        return true;
    default:
        return false;
    }
}

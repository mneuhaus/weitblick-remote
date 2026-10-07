import WeitblickBridge

/// Why a session ended, with a message for the user.
public enum DisconnectReason: Equatable, Sendable {
    /// `RDPSession.disconnect()` or `close()`.
    case requested
    case hostUnreachable
    /// Wrong user name or password.
    case logonFailed
    case missingCredentials
    case accountLocked
    /// Disabled, expired, or not allowed to log on to this computer.
    case accountRestricted
    case passwordExpired
    case accessDenied
    case certificateRejected
    case securityNegotiationFailed
    /// NLA is off for this connection, but the server requires it.
    case nlaRequired
    /// The server or an administrator ended the session.
    case serverEnded
    /// Another connection took over the Windows session.
    case takenOver
    /// The user logged off or disconnected inside Windows.
    case loggedOff
    case timeout
    /// The network dropped (and reconnecting, if enabled, gave up).
    case connectionLost
    case other

    /// Asking for the password again can fix it.
    public var needsCredentials: Bool {
        self == .logonFailed || self == .missingCredentials
    }

    /// Ended on purpose, by the user here or in Windows: nothing to report.
    public var isDeliberate: Bool {
        self == .requested || self == .loggedOff
    }

    /// Looked up in the main bundle: the app's string catalog carries the translations
    /// (a static library has no bundle of its own; the command-line tools show English).
    public var message: String {
        switch self {
        case .requested: String(localized: "Disconnected.")
        case .hostUnreachable: String(localized: "Host unreachable.")
        case .logonFailed: String(localized: "Sign-in failed: wrong user name or password.")
        case .missingCredentials: String(localized: "Sign-in failed: credentials missing.")
        case .accountLocked: String(localized: "Account locked.")
        case .accountRestricted: String(localized: "Account disabled, expired or not allowed to sign in here.")
        case .passwordExpired: String(localized: "Password expired. Set a new password in Windows.")
        case .accessDenied: String(localized: "Access denied: the user isn’t allowed to sign in via Remote Desktop.")
        case .certificateRejected: String(localized: "Certificate rejected.")
        case .securityNegotiationFailed: String(localized: "Secure connection failed (TLS/security negotiation).")
        case .nlaRequired: String(localized: "The server requires Network Level Authentication (NLA). Turn NLA on for this connection.")
        case .serverEnded: String(localized: "The server disconnected.")
        case .takenOver: String(localized: "Another connection took over the session.")
        case .loggedOff: String(localized: "Session ended in Windows.")
        case .timeout: String(localized: "Timed out.")
        case .connectionLost: String(localized: "Connection lost.")
        case .other: String(localized: "Connection ended.")
        }
    }

    init(_ raw: WBDisconnectReason) {
        switch raw {
        case WBDisconnectRequested: self = .requested
        case WBDisconnectHostUnreachable: self = .hostUnreachable
        case WBDisconnectLogonFailed: self = .logonFailed
        case WBDisconnectMissingCredentials: self = .missingCredentials
        case WBDisconnectAccountLocked: self = .accountLocked
        case WBDisconnectAccountRestricted: self = .accountRestricted
        case WBDisconnectPasswordExpired: self = .passwordExpired
        case WBDisconnectAccessDenied: self = .accessDenied
        case WBDisconnectCertificateRejected: self = .certificateRejected
        case WBDisconnectSecurityFailed: self = .securityNegotiationFailed
        case WBDisconnectNLARequired: self = .nlaRequired
        case WBDisconnectServerEnded: self = .serverEnded
        case WBDisconnectTakenOver: self = .takenOver
        case WBDisconnectLoggedOff: self = .loggedOff
        case WBDisconnectTimeout: self = .timeout
        case WBDisconnectConnectionLost: self = .connectionLost
        default: self = .other
        }
    }
}

import SprungBridge

/// Why a session ended, with a German message for the user.
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

    public var message: String {
        switch self {
        case .requested: "Verbindung getrennt."
        case .hostUnreachable: "Host nicht erreichbar."
        case .logonFailed: "Anmeldung fehlgeschlagen: Benutzername oder Passwort falsch."
        case .missingCredentials: "Anmeldung fehlgeschlagen: Zugangsdaten fehlen."
        case .accountLocked: "Konto gesperrt."
        case .accountRestricted: "Konto deaktiviert, abgelaufen oder für diese Anmeldung nicht zugelassen."
        case .passwordExpired: "Passwort abgelaufen. Bitte unter Windows ein neues Passwort setzen."
        case .accessDenied: "Zugriff verweigert: Der Benutzer darf sich nicht per Remotedesktop anmelden."
        case .certificateRejected: "Zertifikat abgelehnt."
        case .securityNegotiationFailed: "Sichere Verbindung fehlgeschlagen (TLS/Sicherheitsaushandlung)."
        case .serverEnded: "Server hat getrennt."
        case .takenOver: "Die Sitzung wurde von einer anderen Verbindung übernommen."
        case .loggedOff: "Sitzung unter Windows beendet."
        case .timeout: "Zeitüberschreitung."
        case .connectionLost: "Verbindung unterbrochen."
        case .other: "Verbindung beendet."
        }
    }

    init(_ raw: SprungDisconnectReason) {
        switch raw {
        case SprungDisconnectRequested: self = .requested
        case SprungDisconnectHostUnreachable: self = .hostUnreachable
        case SprungDisconnectLogonFailed: self = .logonFailed
        case SprungDisconnectMissingCredentials: self = .missingCredentials
        case SprungDisconnectAccountLocked: self = .accountLocked
        case SprungDisconnectAccountRestricted: self = .accountRestricted
        case SprungDisconnectPasswordExpired: self = .passwordExpired
        case SprungDisconnectAccessDenied: self = .accessDenied
        case SprungDisconnectCertificateRejected: self = .certificateRejected
        case SprungDisconnectSecurityFailed: self = .securityNegotiationFailed
        case SprungDisconnectServerEnded: self = .serverEnded
        case SprungDisconnectTakenOver: self = .takenOver
        case SprungDisconnectLoggedOff: self = .loggedOff
        case SprungDisconnectTimeout: self = .timeout
        case SprungDisconnectConnectionLost: self = .connectionLost
        default: self = .other
        }
    }
}

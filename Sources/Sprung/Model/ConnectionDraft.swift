import ConnectionStore
import Foundation

/// What the editor works on: a copy of the connection plus the password field. Nothing is
/// stored until `saved()`.
struct ConnectionDraft {
    enum PasswordChange: Equatable {
        case keep
        case set(String)
        case remove
    }

    var connection: Connection
    let isNew: Bool
    /// A password is saved for this connection (the field then stays empty: "unverändert").
    let hasStoredPassword: Bool
    /// Typed password; empty keeps the stored one.
    var password = ""
    var removeStoredPassword = false

    init(connection: Connection, isNew: Bool, hasStoredPassword: Bool) {
        self.connection = connection
        self.isNew = isNew
        self.hasStoredPassword = hasStoredPassword
    }

    static func new() -> ConnectionDraft {
        ConnectionDraft(connection: Connection(name: "", host: ""), isNew: true, hasStoredPassword: false)
    }

    /// Why the draft cannot be saved yet; nil when it can.
    var problem: String? {
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return "Bitte einen Host angeben." }
        if host.contains(where: \.isWhitespace) { return "Der Host darf keine Leerzeichen enthalten." }
        if !(1...65535).contains(connection.port) { return "Der Port muss zwischen 1 und 65535 liegen." }
        let display = connection.display
        if !display.matchScreenResolution,
           !(200...8192).contains(display.fixedWidth) || !(200...8192).contains(display.fixedHeight) {
            return "Die feste Auflösung muss zwischen 200 und 8192 Pixeln liegen."
        }
        return nil
    }

    var passwordChange: PasswordChange {
        if !password.isEmpty { return .set(password) }
        return removeStoredPassword ? .remove : .keep
    }

    /// The connection to store: trimmed text, the host as name when the name is empty.
    func saved() -> Connection {
        var result = connection
        result.host = result.host.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.name.isEmpty { result.name = result.host }
        result.username = result.username.trimmingCharacters(in: .whitespacesAndNewlines)
        result.domain = result.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        result.advanced.wakeOnLANMACAddresses = result.advanced.wakeOnLANMACAddresses
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for keyPath in [\Connection.advanced.alternateShell, \.advanced.workingDir, \.advanced.loadBalanceInfo] {
            if result[keyPath: keyPath]?.trimmingCharacters(in: .whitespaces).isEmpty == true { result[keyPath: keyPath] = nil }
        }
        return result
    }
}

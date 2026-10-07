import Foundation

public enum RDPFileError: Error, Equatable, Sendable {
    case invalidEncoding, missingAddress, invalidAddress, invalidValue(String), unsupportedProtocol
}

public struct RDPFileImport: Sendable {
    public var connection: Connection
    public var ignoredFields: [ImportFieldIssue]
    public var warnings: [String]
}

public enum RDPFileEncoding: Sendable { case utf8, utf16LittleEndian }

public enum RDPFile {
    public static func read(_ fileURL: URL) throws -> RDPFileImport {
        try decode(Data(contentsOf: fileURL), name: fileURL.deletingPathExtension().lastPathComponent)
    }

    public static func decode(_ data: Data, name: String = "Imported RDP") throws -> RDPFileImport {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            text = String(data: data.dropFirst(3), encoding: .utf8)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text else { throw RDPFileError.invalidEncoding }
        var fields: [String: (String, String)] = [:]
        var warnings: [String] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { warnings.append("Zeile \(index + 1) unlesbar; übersprungen."); continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "password 51" || key == "password" {
                warnings.append("Gespeichertes Passwort in der Datei ignoriert; beim Verbinden wird danach gefragt.")
                continue
            }
            if fields[key] != nil { warnings.append("Feld \(key) doppelt; der letzte Wert gilt.") }
            fields[key] = (parts[1].lowercased(), parts[2])
        }
        var reader = RDPFieldReader(fields: fields)
        guard let address = try reader.string("full address"), !address.isEmpty else { throw RDPFileError.missingAddress }
        let (host, port) = try parseAddress(address)
        var connection = Connection(name: name, host: host, port: port)
        connection.username = try reader.string("username") ?? ""
        connection.domain = try reader.string("domain") ?? ""
        if let value = try reader.integer("desktopwidth") { connection.display.fixedWidth = value }
        if let value = try reader.integer("desktopheight") { connection.display.fixedHeight = value }
        if let value = try reader.integer("screen mode id") {
            guard value == 1 || value == 2 else { throw RDPFileError.invalidValue("screen mode id") }
            connection.display.startFullscreen = value == 2
        }
        if let value = try reader.boolean("dynamic resolution") { connection.display.dynamicResolution = value }
        if let value = try reader.boolean("use multimon") { connection.display.useAllMonitors = value }
        if let value = try reader.boolean("redirectclipboard") { connection.redirection.clipboard = value }
        if let value = try reader.integer("audiomode") {
            // RDP file code space IS documented and differs from Jump's tentative enum.
            switch value {
            case 0: connection.redirection.audioPlayback = .local
            case 1: connection.redirection.audioPlayback = .remote
            case 2: connection.redirection.audioPlayback = .off
            default: throw RDPFileError.invalidValue("audiomode")
            }
        }
        if let value = try reader.boolean("audiocapturemode") { connection.redirection.microphone = value }
        if let value = try reader.boolean("redirectprinters") { connection.redirection.printers = value }
        connection.advanced.rdpDriveStoreDirect = try reader.string("drivestoredirect")
        if !(connection.advanced.rdpDriveStoreDirect ?? "").isEmpty {
            warnings.append("Laufwerksauswahl der Datei (Windows-Laufwerke) nicht als Mac-Ordner übernommen; Ordner bitte selbst freigeben.")
        }
        connection.advanced.alternateShell = try reader.string("alternate shell")
        connection.advanced.workingDir = try reader.string("shell working directory")
        connection.advanced.loadBalanceInfo = try reader.string("loadbalanceinfo")
        connection.advanced.gatewayHostname = try reader.string("gatewayhostname")
        if let value = try reader.integer("authentication level") {
            guard (0...2).contains(value) else { throw RDPFileError.invalidValue("authentication level") }
            connection.security.authenticationLevel = value
            connection.security.ignoreCertificateErrors = value == 0
        }
        if let value = try reader.boolean("prompt for credentials") { connection.security.promptForCredentials = value }
        try connection.validate()
        let ignored = fields.keys.filter { !reader.consumed.contains($0) }.sorted().map {
            ImportFieldIssue($0, "Einstellung wird nicht unterstützt; nicht übernommen.")
        }
        return RDPFileImport(connection: connection, ignoredFields: ignored, warnings: warnings)
    }

    /// Export emits only explicitly supported settings, never passwords, fingerprints or local path names.
    public static func encode(_ connection: Connection, encoding: RDPFileEncoding = .utf16LittleEndian) throws -> Data {
        guard connection.protocol == .rdp else { throw RDPFileError.unsupportedProtocol }
        try connection.validate()
        var lines: [String] = []
        func string(_ key: String, _ value: String?) throws {
            guard let value else { return }
            guard !value.contains(where: { $0.isNewline || $0 == "\0" }) else { throw RDPFileError.invalidValue(key) }
            lines.append("\(key):s:\(value)")
        }
        func integer(_ key: String, _ value: Int) { lines.append("\(key):i:\(value)") }
        func boolean(_ key: String, _ value: Bool) { integer(key, value ? 1 : 0) }
        let host = connection.host.contains(":") && !connection.host.hasPrefix("[") ? "[\(connection.host)]" : connection.host
        try string("full address", "\(host):\(connection.port)")
        try string("username", connection.username)
        try string("domain", connection.domain)
        integer("desktopwidth", connection.display.fixedWidth)
        integer("desktopheight", connection.display.fixedHeight)
        integer("screen mode id", connection.display.startFullscreen ? 2 : 1)
        boolean("dynamic resolution", connection.display.dynamicResolution)
        boolean("use multimon", connection.display.useAllMonitors)
        boolean("redirectclipboard", connection.redirection.clipboard)
        integer("audiomode", connection.redirection.audioPlayback == .local ? 0 : connection.redirection.audioPlayback == .remote ? 1 : 2)
        boolean("audiocapturemode", connection.redirection.microphone)
        boolean("redirectprinters", connection.redirection.printers)
        try string("drivestoredirect", connection.advanced.rdpDriveStoreDirect ?? "")
        try string("alternate shell", connection.advanced.alternateShell)
        try string("shell working directory", connection.advanced.workingDir)
        try string("loadbalanceinfo", connection.advanced.loadBalanceInfo)
        try string("gatewayhostname", connection.advanced.gatewayHostname)
        integer("authentication level", connection.security.ignoreCertificateErrors ? 0 : connection.security.authenticationLevel)
        boolean("prompt for credentials", connection.security.promptForCredentials)
        let text = lines.joined(separator: "\r\n") + "\r\n"
        switch encoding {
        case .utf8: return Data(text.utf8)
        case .utf16LittleEndian: return Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
        }
    }

    private static func parseAddress(_ input: String) throws -> (String, Int) {
        let value = input.trimmingCharacters(in: .whitespaces)
        let host: String
        let port: Int
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { throw RDPFileError.invalidAddress }
            host = String(value[value.index(after: value.startIndex)..<close])
            let suffix = value[value.index(after: close)...]
            if suffix.isEmpty { port = 3389 }
            else {
                guard suffix.hasPrefix(":"), let parsed = Int(suffix.dropFirst()) else { throw RDPFileError.invalidAddress }
                port = parsed
            }
        } else if value.filter({ $0 == ":" }).count == 1 {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let parsed = Int(parts[1]) else { throw RDPFileError.invalidAddress }
            host = String(parts[0]); port = parsed
        } else {
            host = value; port = 3389
        }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\0" }),
              (1...65535).contains(port) else { throw RDPFileError.invalidAddress }
        return (host, port)
    }
}

private struct RDPFieldReader {
    let fields: [String: (String, String)]
    var consumed: Set<String> = []
    mutating func string(_ key: String) throws -> String? {
        guard let (type, value) = fields[key] else { return nil }
        consumed.insert(key)
        guard type == "s", !value.contains("\0") else { throw RDPFileError.invalidValue(key) }
        return value
    }
    mutating func integer(_ key: String) throws -> Int? {
        guard let (type, value) = fields[key] else { return nil }
        consumed.insert(key)
        guard type == "i", let integer = Int(value.trimmingCharacters(in: .whitespaces)) else { throw RDPFileError.invalidValue(key) }
        return integer
    }
    mutating func boolean(_ key: String) throws -> Bool? {
        guard let value = try integer(key) else { return nil }
        guard value == 0 || value == 1 else { throw RDPFileError.invalidValue(key) }
        return value == 1
    }
}

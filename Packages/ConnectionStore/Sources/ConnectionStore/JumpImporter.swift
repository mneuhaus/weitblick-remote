import Foundation
import KeyboardEngine

public struct JumpImporter: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.p5sys.jump.mac.viewer/Data/Documents/JumpDesktop/Viewer/Servers")
    }
    /// Every imported entry carries this warning; UIs may show it once instead of per entry.
    public static let passwordNotice =
        "Passwort steht nicht in der Jump-Datei; beim ersten Verbinden wird danach gefragt (Jumps Schlüsselbund bleibt unberührt)."
    public let directory: URL
    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    /// Reads only the selected directory. Never queries Jump's Keychain or writes its files.
    public func plan(existing: [Connection], importedAt: Date = Date()) throws -> JumpImportPlan {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jump" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var entries: [JumpImportEntry] = []
        var reports: [ConnectionImportReport] = []
        var seen: Set<String> = []
        let grouped = Dictionary(grouping: existing.filter { $0.importSource?.kind == "jump" }) { $0.importSource!.uniqueID }
        for file in files {
            var report = ConnectionImportReport(fileName: file.lastPathComponent)
            do {
                let data = try Data(contentsOf: file)
                guard data.count <= 4 * 1024 * 1024,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    report.warnings.append("Keine lesbare Jump-Datei (kein JSON-Objekt oder größer als 4 MiB).")
                    reports.append(report)
                    continue
                }
                var reader = JumpFieldReader(object: object, report: report)
                guard let uniqueID = reader.string("UniqueId"), !uniqueID.isEmpty else {
                    reader.report.warnings.append("UniqueId fehlt; ohne sie ließe sich ein erneuter Import nicht zuordnen. Übersprungen.")
                    reports.append(reader.finish())
                    continue
                }
                reader.report.uniqueID = uniqueID
                guard seen.insert(uniqueID).inserted else {
                    reader.report.warnings.append("Doppelte UniqueId im Jump-Ordner; diese Datei wurde übersprungen.")
                    reports.append(reader.finish())
                    continue
                }
                guard (grouped[uniqueID]?.count ?? 0) <= 1 else {
                    reader.report.warnings.append("Mehrere gespeicherte Verbindungen gehören zu dieser Jump-Verbindung; bitte zuerst bereinigen. Übersprungen.")
                    reports.append(reader.finish())
                    continue
                }
                let previous = grouped[uniqueID]?.first
                guard let protocolCode = reader.integer("ProtocolTypeCode"), protocolCode == 0 || protocolCode == 1 else {
                    reader.report.warnings.append("Unbekanntes Protokoll (ProtocolTypeCode); übersprungen statt zu raten.")
                    reports.append(reader.finish())
                    continue
                }
                let transport: ConnectionProtocol = protocolCode == 0 ? .rdp : .vnc
                let host = reader.string("TcpHostName") ?? ""
                guard !host.isEmpty else {
                    reader.report.warnings.append("Host fehlt; übersprungen.")
                    reports.append(reader.finish())
                    continue
                }
                var connection = previous ?? Connection(name: host, host: host,
                                                       port: transport == .rdp ? 3389 : 5900, protocol: transport)
                connection.host = host
                connection.protocol = transport
                connection.name = reader.string("DisplayName") ?? host
                connection.port = reader.integer("TcpPort") ?? (transport == .rdp ? 3389 : 5900)
                if reader.has("Username") { connection.username = reader.string("Username") ?? "" }
                if reader.has("Domain") { connection.domain = reader.string("Domain") ?? "" }
                mapDisplay(&connection, reader: &reader)
                mapRedirection(&connection, reader: &reader)
                mapKeyboard(&connection, reader: &reader)
                mapSecurity(&connection, reader: &reader)
                mapAdvanced(&connection, reader: &reader)
                if reader.has("Tags") { connection.tags = reader.strings("Tags") ?? [] }
                if reader.has("LastConnectedTime") {
                    // NSDate timeIntervalSinceReferenceDate, NOT Unix seconds; zero means never.
                    let seconds = reader.number("LastConnectedTime") ?? 0
                    let jumpDate = seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
                    // A connection made with Sprung after the last import must not be rolled back.
                    connection.lastConnected = [previous?.lastConnected, jumpDate].compactMap { $0 }.max()
                }
                connection.importSource = ImportSource(uniqueID: uniqueID, fileName: file.lastPathComponent,
                                                       importedAt: previous?.importSource?.importedAt ?? importedAt)
                try connection.validate()
                let action: JumpImportAction = previous == nil ? .create : (connection == previous ? .unchanged : .update)
                reader.report.connectionName = connection.name
                reader.report.action = action
                reader.report.warnings.append(Self.passwordNotice)
                entries.append(JumpImportEntry(action: action, connection: connection, previous: previous))
                reports.append(reader.finish())
            } catch {
                // Parser errors are intentionally not interpolated: they may contain source values.
                report.warnings.append("Datei nicht lesbar oder ungültig; nichts geplant.")
                reports.append(report)
            }
        }
        return JumpImportPlan(entries: entries, report: ImportReport(connections: reports))
    }

    public func apply(_ plan: JumpImportPlan, to store: ConnectionStore, selectedIDs: Set<UUID>? = nil) async throws {
        try await store.apply(plan, selectedIDs: selectedIDs)
    }

    private func mapDisplay(_ connection: inout Connection, reader: inout JumpFieldReader) {
        if let value = reader.boolean("UseDynamicResolutionUpdate") { connection.display.dynamicResolution = value }
        if let value = reader.boolean("MatchScreenResolution") { connection.display.matchScreenResolution = value }
        if let value = reader.integer("ResolutionWidth") { connection.display.fixedWidth = value }
        if let value = reader.integer("ResolutionHeight") { connection.display.fixedHeight = value }
        if let value = reader.boolean("UseHIDPIResolution") { connection.display.retina = value }
        if reader.has("DesktopScaleFactor") {
            let factor = reader.integer("DesktopScaleFactor") ?? 0
            connection.display.desktopScaleFactor = factor == 0 ? nil : factor
        }
        if let value = reader.boolean("StartInFullscreen") { connection.display.startFullscreen = value }
        if let value = reader.boolean("UseAllMonitors") { connection.display.useAllMonitors = value }
        if let value = reader.integer("MonitorCount") { connection.display.monitorCount = value }
    }

    private func mapRedirection(_ connection: inout Connection, reader: inout JumpFieldReader) {
        if let value = reader.boolean("ClipboardRedirection") { connection.redirection.clipboard = value }
        if let code = reader.integer("AudioPlaybackCode") {
            // Only 2 is corroborated by the local playback-on configuration. Do not use .rdp's code space.
            connection.redirection.audioPlayback = code == 2 ? .local : .off
            reader.report.warnings.append(code == 2
                ? "Audio: Jumps Code 2 als „auf diesem Mac abspielen“ gedeutet; bitte prüfen."
                : "Unbekannter Audio-Code \(code); Audio-Wiedergabe vorsichtshalber aus.")
            if code != 2 { reader.ignore("AudioPlaybackCode", "Unbekannter Jump-Wert; Wiedergabe aus.") }
        }
        if reader.has("AudioInputDevice") {
            let device = reader.string("AudioInputDevice")
            connection.redirection.audioInputDevice = device
            connection.redirection.microphone = !(device ?? "").isEmpty
        }
        if let value = reader.boolean("RdpPrinterRedirection") { connection.redirection.printers = value }
        if reader.has("DefaultPrinter") { connection.redirection.defaultPrinter = reader.string("DefaultPrinter") }
        if let value = reader.boolean("RdpDriveRedirection") { connection.redirection.driveRedirection = value }
        if let mappings = reader.array("DriveMappings") {
            connection.redirection.drives = mappings.enumerated().compactMap { index, object in
                guard let object = object as? [String: Any] else {
                    reader.ignore("DriveMappings[\(index)]", "Kein Objekt; Laufwerk nicht übernommen.")
                    return nil
                }
                var drive = JumpFieldReader(object: object, report: ConnectionImportReport(fileName: ""))
                let name = drive.string("DisplayName") ?? ""
                let path = drive.string("LocalPath") ?? ""
                let enabled = drive.boolean("Enabled") ?? false
                let readOnly = drive.boolean("IsReadOnly") ?? false
                let sourceID = drive.string("UniqueId")
                let driveReport = drive.finish()
                for field in driveReport.importedFields { reader.report.importedFields.append("DriveMappings[\(index)].\(field)") }
                for field in driveReport.ignoredFields { reader.ignore("DriveMappings[\(index)].\(field.field)", field.reason) }
                guard !name.isEmpty, !path.isEmpty else {
                    reader.ignore("DriveMappings[\(index)]", "Name oder Pfad fehlt; Laufwerk nicht übernommen.")
                    return nil
                }
                if readOnly, enabled {
                    reader.report.warnings.append(
                        "Laufwerk „\(name)“ ist in Jump schreibgeschützt und wird nicht freigegeben (Freigaben gehen nur mit Schreibzugriff).")
                }
                return DriveMapping(name: name, localPath: path, enabled: enabled, readOnly: readOnly, sourceID: sourceID)
            }
        }
    }

    private func mapKeyboard(_ connection: inout Connection, reader: inout JumpFieldReader) {
        if let value = reader.boolean("RdpUseUnicodeKeyboard") { connection.keyboard.unicodeTextInput = value }
        let automatic = reader.boolean("KeyboardAutomaticLocaleDetection") ?? true
        if automatic {
            connection.keyboard.layoutOverride = nil
            if reader.has("KeyboardLocaleId") { reader.ignore("KeyboardLocaleId", "Automatische Layout-Erkennung hat Vorrang.") }
        } else if let value = reader.integer("KeyboardLocaleId"), let id = UInt32(exactly: value), id > 0 {
            connection.keyboard.layoutOverride = WindowsKeyboardLayoutID(id)
        } else {
            connection.keyboard.layoutOverride = nil
            reader.report.warnings.append("Kein gültiges Tastaturlayout (KeyboardLocaleId); es wird automatisch erkannt.")
        }
        if reader.has("KeyboardInputProfileId") {
            reader.ignore("KeyboardInputProfileId", "Verweis auf ein Jump-Tastaturprofil; es gelten die eigenen Tastaturregeln.")
        }
    }

    private func mapSecurity(_ connection: inout Connection, reader: inout JumpFieldReader) {
        if let value = reader.boolean("IgnoreCertificateErrors") { connection.security.ignoreCertificateErrors = value }
        if let value = reader.boolean("RdpDisableNLA") { connection.security.disableNLA = value }
        if let value = reader.boolean("RdpConsoleSession") { connection.security.consoleSession = value }
        // Fingerprints trusted in Sprung since the last import stay; Jump's one is added.
        if reader.has("SslCertificateFingerPrint"), let fingerprint = reader.string("SslCertificateFingerPrint"),
           !fingerprint.isEmpty, !connection.security.trusts(fingerprint: fingerprint) {
            connection.security.trustedCertificateFingerprints.append(fingerprint)
        }
    }

    private func mapAdvanced(_ connection: inout Connection, reader: inout JumpFieldReader) {
        if reader.has("RdpAlternateShellPath") { connection.advanced.alternateShell = reader.string("RdpAlternateShellPath") }
        if reader.has("RdpAlternateShellWorkingDir") { connection.advanced.workingDir = reader.string("RdpAlternateShellWorkingDir") }
        if reader.has("LoadBalancerInfo") { connection.advanced.loadBalanceInfo = reader.string("LoadBalancerInfo") }
        if reader.has("RDGatewayUniqueId") {
            connection.advanced.gatewayRef = reader.string("RDGatewayUniqueId")
            if connection.advanced.gatewayRef != nil { reader.report.warnings.append("Gateway-Verweis gespeichert, die Gateway-Einstellungen selbst werden nicht übernommen.") }
        }
        if reader.has("MacAddresses") { connection.advanced.wakeOnLANMACAddresses = reader.strings("MacAddresses") ?? [] }
    }
}

private struct JumpFieldReader {
    var object: [String: Any]
    var report: ConnectionImportReport
    private var consumed: Set<String> = []
    init(object: [String: Any], report: ConnectionImportReport) { self.object = object; self.report = report }
    func has(_ key: String) -> Bool { object[key] != nil }
    mutating func read(_ key: String) -> Any? {
        guard let value = object[key] else { return nil }
        if consumed.insert(key).inserted { report.importedFields.append(key) }
        return value is NSNull ? nil : value
    }
    mutating func string(_ key: String) -> String? {
        guard let value = read(key) else { return nil }
        guard let string = value as? String else { ignore(key, "Kein Text; nicht übernommen."); return nil }
        return string
    }
    mutating func number(_ key: String) -> Double? {
        guard let value = read(key) else { return nil }
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c", number.doubleValue.isFinite else {
            ignore(key, "Keine Zahl; nicht übernommen."); return nil
        }
        return number.doubleValue
    }
    mutating func integer(_ key: String) -> Int? {
        guard let value = number(key) else { return nil }
        guard let integer = Int(exactly: value) else { ignore(key, "Keine ganze Zahl; nicht übernommen."); return nil }
        return integer
    }
    mutating func boolean(_ key: String) -> Bool? {
        guard let value = read(key) else { return nil }
        guard let number = value as? NSNumber, String(cString: number.objCType) == "c" else {
            ignore(key, "Kein Ja/Nein-Wert; nicht übernommen."); return nil
        }
        return number.boolValue
    }
    mutating func array(_ key: String) -> [Any]? {
        guard let value = read(key) else { return nil }
        guard let array = value as? [Any] else { ignore(key, "Keine Liste; nicht übernommen."); return nil }
        return array
    }
    mutating func strings(_ key: String) -> [String]? {
        guard let array = array(key) else { return nil }
        guard let strings = array as? [String] else { ignore(key, "Keine Textliste; nicht übernommen."); return nil }
        return strings
    }
    mutating func ignore(_ key: String, _ reason: String) {
        consumed.insert(key)
        report.importedFields.removeAll { $0 == key }
        report.ignoredFields.append(ImportFieldIssue(key, reason))
    }
    mutating func finish() -> ConnectionImportReport {
        let unknownEnums: Set<String> = ["ColorDepthCode", "RdpPerformanceFlags", "ConnectionTypeCode", "TypeCode",
                                        "OsTypeCode", "OSTypeCode", "GestureProfileCode"]
        for key in object.keys.sorted() where !consumed.contains(key) {
            ignore(key, unknownEnums.contains(key)
                   ? "Undokumentierter Jump-Code; nicht gedeutet, der Standard bleibt."
                   : "Keine Entsprechung; nicht übernommen.")
        }
        return report
    }
}

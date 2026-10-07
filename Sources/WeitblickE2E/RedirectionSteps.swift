import Foundation
import WeitblickKit

/// Drive redirection, printers and audio, checked from inside the session (`files.ps1`).
extension Scenario {
    static let bigShareFile = "groß-100MB.bin"

    /// The shared folder's starting content; the drive is announced at logon, so this runs first.
    static func prepareShare(_ share: URL) throws {
        try? FileManager.default.removeItem(at: share)
        try TestFiles.write("Grüße vom Mac ✓", to: share.appendingPathComponent("vom-Mac-Grüße.txt"))
        try TestFiles.write("alt", to: share.appendingPathComponent("umbenennen.txt"))
        try TestFiles.write("weg", to: share.appendingPathComponent("löschen.txt"))
        try TestFiles.writeRandom(megabytes: 100, to: share.appendingPathComponent(bigShareFile))
    }

    /// Windows reads, writes, renames and deletes in \\tsclient\weitblick-e2e and copies 100 MB both ways.
    func driveRedirection() async throws {
        let result = try await runScript("drive \(FileScript.shareName)", files: true, timeout: 240)
        var values: [String: String] = [:]
        for line in result.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            values[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        func local(_ name: String) -> URL { share.appendingPathComponent(name) }
        func text(_ name: String) -> String? { (try? Data(contentsOf: local(name))).map { String(decoding: $0, as: UTF8.self) } }
        let exists = { (name: String) in FileManager.default.fileExists(atPath: local(name).path) }

        check("drive: Windows lists the Mac folder", values["listing"]?.contains("vom-Mac-Grüße.txt") == true, values["listing"] ?? result)
        check("drive: Windows reads a Mac file (umlaut name)", values["fromMac"] == "Grüße vom Mac ✓", values["fromMac"] ?? "")
        check("drive: Mac reads a file Windows wrote", text("von-Windows-Äß.txt") == "Hallo vom Windows ✓ Äß", text("von-Windows-Äß.txt") ?? "missing")
        check("drive: folder and file created by Windows", text("Ordner-Ü/innen.txt") == "innen", "missing")
        check("drive: rename by Windows", exists("umbenannt-é.txt") && !exists("umbenennen.txt"), "rename not visible")
        check("drive: delete by Windows", !exists("löschen.txt"), "still there")

        let original = try TestFiles.sha256(of: local(Self.bigShareFile))
        check("drive: 100 MB Mac → Windows, same bytes", values["readHash"] == original, values["readHash"] ?? "")
        let back = exists("zurück-100MB.bin") ? try TestFiles.sha256(of: local("zurück-100MB.bin")) : "missing"
        check("drive: 100 MB Windows → Mac, same bytes", back == original, back)
        let read = Double(values["readSeconds"] ?? "") ?? 0
        let write = Double(values["writeSeconds"] ?? "") ?? 0
        log(String(format: "drive speed: Mac → Windows %.1f MB/s (%.1f s), Windows → Mac %.1f MB/s (%.1f s)",
                   read > 0 ? 100 / read : 0, read, write > 0 ? 100 / write : 0, write))
    }

    /// The Mac's CUPS printers reach Windows. They appear on terminal-server ports (TS…) if Windows
    /// has the driver FreeRDP names ("Microsoft Print to PDF" on macOS 14+); otherwise Windows logs
    /// event 1111 per printer ("driver unknown"), which the test VM does. Nothing is printed.
    func redirectedPrinters() async throws {
        let result = try await runScript("printers", files: true)
        if result.contains("[TS") { return check("printers: Mac printers installed in the session", true, result) }
        let refused = try vm.powershell("""
            Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-TerminalServices-Printers/Admin'; Id = 1111;
              StartTime = (Get-Date).AddMinutes(-15) } -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Message
            """).trimmingCharacters(in: .whitespacesAndNewlines)
        log("printers: none installed; Windows says: \(refused)")
        check("printers: Mac printers reach Windows (installed, or refused for a missing driver)", !refused.isEmpty, result)
    }

    /// A Windows sound reaches the Mac's audio backend (rdpsnd wave PDUs to the macOS backend) when
    /// playback is local, and nothing arrives when it stays remote or is off.
    func audioPlayback() async throws {
        let mode = probe.session.configuration.audio
        let before = logLines(containing: "Wave2PDU:") + logLines(containing: "WaveInfo:")
        _ = try await runScript("play-sound", files: true)
        try await Task.sleep(for: .seconds(1))
        let waves = logLines(containing: "Wave2PDU:") + logLines(containing: "WaveInfo:") - before
        let macBackends = logLines(containing: "Loaded mac backend for rdpsnd") - macBackendsBeforeConnect
        if mode == .local {
            check("audio local: macOS backend loaded", macBackends > 0, "no mac backend in \(freerdpLog.path)")
            check("audio local: wave data arrived (\(waves) PDUs)", waves > 0, "no wave PDUs in \(freerdpLog.path)")
        } else {
            check("audio \(mode.rawValue): no macOS backend, no wave data", macBackends == 0 && waves == 0,
                  "\(macBackends) mac backends, \(waves) wave PDUs")
        }
    }

    func logLines(containing text: String) -> Int {
        let log = (try? String(contentsOf: freerdpLog, encoding: .utf8)) ?? ""
        return log.split(whereSeparator: \.isNewline).filter { $0.contains(text) }.count
    }
}

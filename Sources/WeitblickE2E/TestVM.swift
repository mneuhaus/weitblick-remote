import Foundation

/// The Parallels test VM, driven with `prlctl exec` (runs as SYSTEM, outside the RDP session).
/// Used only to prepare the VM and to read results; everything under test goes through RDP.
struct TestVM {
    static let name = "Windows 11"
    /// Shared with the session user; the in-session scripts write their results here.
    static let directory = #"C:\weitblick-e2e"#
    /// The Windows account the tests log on with (`WEITBLICK_TEST_USER`).
    let sessionUser: String

    /// Runs PowerShell in the VM and returns its standard output.
    @discardableResult
    func powershell(_ script: String) throws -> String {
        // Errors stop the script (non-zero exit); explicit -ErrorAction SilentlyContinue still works.
        let wrapped = "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'\n\(script)\nexit 0"
        // -EncodedCommand: UTF-16LE base64, so no quoting survives prlctl's command line joining.
        let encoded = Data(wrapped.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }).base64EncodedString()
        return try prlctl(["exec", Self.name, "powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded])
    }

    /// Writes a file into the VM in pieces: `prlctl exec` hangs on command lines longer than about
    /// 2 KB (measured: 1.4 KB fine, 4 KB hangs), so keep each command around 1.3 KB.
    func write(_ data: Data, to path: String) throws {
        try powershell("[IO.File]::WriteAllBytes('\(path)', [byte[]]@())")
        for offset in stride(from: 0, to: data.count, by: 900) {
            let chunk = data[offset..<min(offset + 900, data.count)].base64EncodedString()
            try prlctl(["exec", Self.name, "powershell", "-NoProfile", "-NonInteractive", "-Command",
                        "$b=[Convert]::FromBase64String('\(chunk)');$f=[IO.File]::Open('\(path)','Append');$f.Write($b,0,$b.Length);$f.Close()"])
        }
    }

    func read(_ path: String) throws -> Data? {
        let output = try powershell("""
            if (Test-Path '\(path)') { [Convert]::ToBase64String([IO.File]::ReadAllBytes('\(path)')) } else { 'MISSING' }
            """).trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "MISSING" ? nil : Data(base64Encoded: output)
    }

    /// Polls for a file the session scripts write when they are done; returns its text.
    func waitForFile(_ path: String, timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try read(path) { return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw E2EFailure("timed out waiting for \(path) in the VM")
    }

    /// A clean slate for a run: network up, no Notepad (and no restored Notepad tabs), fresh scripts,
    /// no old results.
    func prepare(scripts: [String: Data]) throws {
        try setNetwork(connected: true)
        let notepadState = #"C:\Users\\#(sessionUser)\AppData\Local\Packages\Microsoft.WindowsNotepad_8wekyb3d8bbwe\LocalState"#
        // Two short commands: see `write` for prlctl's command-line limit.
        try powershell("""
            Get-Process notepad, powershell -IncludeUserName -ErrorAction SilentlyContinue |
              Where-Object { $_.UserName -like '*\\\(sessionUser)' } | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            foreach ($state in 'TabState', 'WindowState') {
              Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "\(notepadState)\\$state\\*"
            }
            """)
        try powershell("""
            New-Item -ItemType Directory -Force '\(Self.directory)' | Out-Null
            icacls '\(Self.directory)' /grant '\(sessionUser):(OI)(CI)M' | Out-Null
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '\(Self.directory)\\*'
            """)
        for (name, data) in scripts.sorted(by: { $0.key < $1.key }) {
            try write(data, to: "\(Self.directory)\\\(name)")
        }
    }

    func isNotepadRunning() throws -> Bool {
        try notepadProcessID() != nil
    }

    /// The session user's Notepad, if one runs.
    func notepadProcessID() throws -> Int? {
        Int(try powershell("""
            Get-Process notepad -IncludeUserName -ErrorAction SilentlyContinue |
              Where-Object { $_.UserName -like '*\\\(sessionUser)' } | Select-Object -First 1 -ExpandProperty Id
            """).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Plugs the VM's network adapter in or out (Parallels only; the Mac's networking is untouched).
    func setNetwork(connected: Bool) throws {
        // prlctl fails on a device that is already in the wanted state; `list -i` shows
        // "net0 (+) … state=disconnected" while unplugged.
        let adapter = try prlctl(["list", "-i", Self.name]).split(whereSeparator: \.isNewline)
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("net0 ") } ?? ""
        let isConnected = !adapter.contains("state=disconnected")
        guard isConnected != connected else { return }
        try prlctl(["set", Self.name, connected ? "--device-connect" : "--device-disconnect", "net0"])
    }

    @discardableResult
    private func prlctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["prlctl"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        // prlctl can hang (long command lines, guest tools busy): never wait forever.
        let watchdog = DispatchWorkItem { [process] in if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw E2EFailure("prlctl \(arguments.prefix(3).joined(separator: " ")) failed: \(text.prefix(400))")
        }
        return text
    }
}

struct E2EFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

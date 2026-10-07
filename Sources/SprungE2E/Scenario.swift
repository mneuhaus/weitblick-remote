import AppKit
import SprungKit

/// One full E2E pass in one RDP session: typing, shortcuts and clipboard in both directions.
/// Keys go through KeyboardDriver -> KeyboardEngine -> bridge; clipboard through ClipboardSync on a
/// private pasteboard. Results are read back through the clipboard or, for what Windows received,
/// from files the in-session script writes (read with prlctl).
@MainActor
final class Scenario {
    private let vm: TestVM
    private let probe: SmokeProbe
    private let keyboard: KeyboardDriver
    private let clipboard: ClipboardSync
    private let pasteboard: NSPasteboard
    private let evidence: URL
    private(set) var failures: [String] = []
    private var checks = 0

    init(vm: TestVM, probe: SmokeProbe, pasteboard: NSPasteboard, evidence: URL) throws {
        self.vm = vm
        self.probe = probe
        self.pasteboard = pasteboard
        self.evidence = evidence
        keyboard = try KeyboardDriver(remote: probe.session)
        clipboard = ClipboardSync(remote: probe.session.clipboard, pasteboard: pasteboard)
    }

    var summary: String { "\(checks - failures.count)/\(checks) checks passed" }

    func run() async throws {
        try await waitForClipboardChannel()
        keyboard.focusGained()
        try await openNotepad()
        try await typingThroughTheEngine()
        try await shortcutTranslations()
        try await textFromMacToWindows()
        try await imageFromMacToWindows()
        try await imageFromWindowsToMac()
        try await pngWithAlphaFromWindowsToMac()
        try await htmlFromMacToWindows()
        try await rtfFromMacToWindows()
        try await rtfFromWindowsToMac()
        try await htmlFromWindowsToMac()
        clipboard.sessionWillEnd()
    }

    // MARK: Steps

    private func waitForClipboardChannel() async throws {
        // The initial (empty) announcement is the first thing the channel accepts.
        try await probe.wait("clipboard channel", timeout: 20) { self.clipboard.acceptedAnnouncements > 0 }
        log("clipboard channel ready")
    }

    private func openNotepad() async throws {
        try await runDialog("notepad")
        let deadline = Date().addingTimeInterval(20)
        while try !vm.isNotepadRunning() {
            guard Date() < deadline else { throw E2EFailure("Notepad did not start") }
        }
        try await Task.sleep(for: .seconds(2.5)) // window up and focused
        snapshot("notepad-open")
    }

    /// German stress text typed through the engine: ⇧ and ⌥ characters, dead keys composed by
    /// Windows (^ ´ `) and by the engine (⌥N ~), capitals, a line break; copied back with ⌘A ⌘C.
    private func typingThroughTheEngine() async throws {
        let text = "Größe Äpfel Übermut ÖL Straße: ß @ € { } [ ] | \\ ~ ^ ° < > \" § $ % & / ( ) = ? ` ´\n"
            + "Akzente: ê é à ô Ê Ñ ñ, Mac + Windows = Sprung!"
        try await keyboard.type(text)
        snapshot("typed")
        check("typing: German stress text arrives exactly", try await copyAll(), equals: text)
    }

    private func shortcutTranslations() async throws {
        let cases: [(String, String, [KeyboardDriver.Stroke], String, String)] = [
            ("⌘← = Pos1", "eins zwei drei", [stroke(.command, KeyboardDriver.leftArrow)], "X", "Xeins zwei drei"),
            ("⌘→ = Ende", "eins zwei drei", [stroke(.command, KeyboardDriver.leftArrow), stroke(.command, KeyboardDriver.rightArrow)],
             "Y", "eins zwei dreiY"),
            ("⌥← = Strg+←", "eins zwei drei", [stroke(.option, KeyboardDriver.leftArrow)], "X", "eins zwei Xdrei"),
            ("⌥⌫ = Strg+Rück", "eins zwei drei", [stroke(.option, KeyboardDriver.backspace)], "", "eins zwei "),
            ("⌘⌫ = bis Zeilenanfang löschen", "erste\nzweite Zeile", [stroke(.command, KeyboardDriver.backspace)], "", "erste\n"),
        ]
        for (name, start, strokes, typed, expected) in cases {
            try await clearNotepad()
            try await keyboard.type(start)
            for stroke in strokes { try await keyboard.press(stroke) }
            try await keyboard.type(typed)
            check("shortcut \(name)", try await copyAll(), equals: expected)
        }

        // ⌘Z / ⌘⇧Z (Ctrl+Z / Ctrl+Y): undo a cut, then redo it.
        try await clearNotepad()
        try await keyboard.type("abc")
        try await keyboard.shortcut([.command], "a")
        try await keyboard.shortcut([.command], "x")
        try await keyboard.shortcut([.command], "z")
        check("shortcut ⌘Z = Strg+Z", try await copyAll(), equals: "abc")
        try await keyboard.press(stroke(.command, KeyboardDriver.rightArrow))
        try await keyboard.shortcut([.command, .shift], "z")
        try await keyboard.type("Q")
        check("shortcut ⌘⇧Z = Strg+Y", try await copyAll(), equals: "Q")
    }

    private func textFromMacToWindows() async throws {
        try await clearNotepad()
        let text = "Grüße vom Mac 😀\r\nZeile 2\nZeile 3\rEnde ✓ – Tab\tEnde"
        try await announce { $0.setString(text, forType: .string) }
        try await keyboard.shortcut([.command], "v")
        check("Mac → Windows text (emoji, CRLF/LF/CR)", try await copyAll(),
              equals: "Grüße vom Mac 😀\nZeile 2\nZeile 3\nEnde ✓ – Tab\tEnde")
    }

    private func imageFromMacToWindows() async throws {
        let expected = Pixels(width: 97, height: 61) { x, y in (UInt8(x * 5 % 256), UInt8(y * 7 % 256), UInt8(x * y % 256), 255) }
        guard let png = expected.png() else { throw E2EFailure("cannot encode the test PNG") }
        try await announce { $0.setData(png, forType: .png) }
        let result = try await runScript("save-image")
        guard let data = try vm.read(TestVM.directory + #"\image.png"#) else {
            return check("Mac → Windows image arrives", false, "nothing saved: \(result)")
        }
        try data.write(to: evidence.appendingPathComponent("mac-to-windows.png"))
        guard let received = Pixels(file: data) else { return check("Mac → Windows image decodes", false, result) }
        let mismatches = received.mismatches(against: expected, compareAlpha: false)
        check("Mac → Windows image \(received.width)x\(received.height), exact pixels", mismatches == 0,
              "\(mismatches.map(String.init) ?? "size differs") mismatching pixels; \(result)")
    }

    private func imageFromWindowsToMac() async throws {
        let before = clipboard.publishedRemoteChanges
        let result = try await runScript("set-image")
        try await waitForRemoteClipboard(after: before)
        let size = SessionScript.imageSize
        let expected = Pixels(width: size.width, height: size.height) { x, y in
            let p = SessionScript.imagePixel(x: x, y: y)
            return (p.r, p.g, p.b, 255)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let data = pasteboard.data(forType: type)
            if let data { try data.write(to: evidence.appendingPathComponent("windows-to-mac.\(type == .png ? "png" : "tiff")")) }
            let mismatches = data.flatMap(Pixels.init(file:)).flatMap { $0.mismatches(against: expected) }
            check("Windows → Mac image as \(type.rawValue), exact pixels", mismatches == 0,
                  "\(mismatches.map(String.init) ?? "no/undecodable data"); \(result)")
        }
        // No echo: our own publication must not go back to the server.
        let accepted = clipboard.acceptedAnnouncements
        clipboard.checkPasteboard()
        try await Task.sleep(for: .seconds(1))
        check("no echo of received clipboard", clipboard.acceptedAnnouncements == accepted, "re-announced")
    }

    private func pngWithAlphaFromWindowsToMac() async throws {
        let before = clipboard.publishedRemoteChanges
        let result = try await runScript("set-png")
        try await waitForRemoteClipboard(after: before)
        let size = SessionScript.pngSize
        let expected = Pixels(width: size.width, height: size.height) { x, y in SessionScript.pngPixel(x: x, y: y) }
        let data = pasteboard.data(forType: .png)
        let mismatches = data.flatMap(Pixels.init(file:)).flatMap { $0.mismatches(against: expected) }
        check("Windows → Mac \"PNG\" with alpha, exact pixels", mismatches == 0,
              "\(mismatches.map(String.init) ?? "no/undecodable data"); \(result)")
    }

    private func htmlFromMacToWindows() async throws {
        let fragment = "<b>Grüße</b> &amp; <i>Welt</i> 😀"
        try await announce {
            $0.setString(fragment, forType: .html)
            $0.setString("Grüße & Welt 😀", forType: .string)
        }
        let result = try await runScript(#"dump "HTML Format""#)
        guard let base64 = try vm.read(TestVM.directory + #"\dump.b64"#), let bytes = Data(base64Encoded: base64) else {
            return check("Mac → Windows HTML arrives", false, result)
        }
        try bytes.write(to: evidence.appendingPathComponent("mac-to-windows.cfhtml"))
        check("Mac → Windows CF_HTML offsets and fragment", Self.cfHTMLFragment(bytes) == fragment,
              "fragment \(Self.cfHTMLFragment(bytes) ?? "unreadable"); \(result)")
    }

    private func rtfFromMacToWindows() async throws {
        let text = NSAttributedString(string: "Grüße vom Mac", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        guard let rtf = text.rtf(from: NSRange(location: 0, length: text.length)) else { throw E2EFailure("no RTF") }
        try await announce { $0.setData(rtf, forType: .rtf) }
        let result = try await runScript(#"dump "Rich Text Format""#)
        let received = try vm.read(TestVM.directory + #"\dump.b64"#).flatMap { Data(base64Encoded: $0) }
        check("Mac → Windows RTF bytes", received.map { Data($0.prefix { $0 != 0 }) } == rtf, result)
    }

    private func rtfFromWindowsToMac() async throws {
        let before = clipboard.publishedRemoteChanges
        let result = try await runScript("set-rtf")
        try await waitForRemoteClipboard(after: before)
        let data = pasteboard.data(forType: .rtf)
        check("Windows → Mac RTF bytes", data == Data(SessionScript.rtf.utf8), result)
        let text = data.flatMap { try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) }
        let bold = (text?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold)
        check("Windows → Mac RTF reads as bold \"Grüße\"", text?.string.hasPrefix("Grüße aus RTF") == true && bold == true,
              text?.string ?? "unreadable")
    }

    private func htmlFromWindowsToMac() async throws {
        let before = clipboard.publishedRemoteChanges
        let result = try await runScript("set-html")
        try await waitForRemoteClipboard(after: before)
        let html = pasteboard.string(forType: .html) ?? ""
        try Data(html.utf8).write(to: evidence.appendingPathComponent("windows-to-mac.html"))
        check("Windows → Mac HTML fragment (UTF-8)", html.contains(SessionScript.htmlFragment) && html.contains("charset"),
              "\(html.prefix(300)); \(result)")
        check("Windows → Mac HTML with plain text", pasteboard.string(forType: .string) == SessionScript.htmlText, result)
    }

    // MARK: Helpers

    private func stroke(_ modifier: KeyboardDriver.Modifier, _ keyCode: UInt16) -> KeyboardDriver.Stroke {
        KeyboardDriver.Stroke(keyCode: keyCode, modifiers: [modifier])
    }

    private func clearNotepad() async throws {
        try await keyboard.shortcut([.command], "a")
        try await keyboard.press(KeyboardDriver.Stroke(keyCode: KeyboardDriver.backspace))
    }

    /// ⌘A ⌘C in the session, then the text as it arrives on the Mac pasteboard.
    private func copyAll() async throws -> String {
        let before = clipboard.publishedRemoteChanges
        try await keyboard.shortcut([.command], "a")
        try await keyboard.shortcut([.command], "c")
        try await waitForRemoteClipboard(after: before)
        return pasteboard.string(forType: .string) ?? "<no text>"
    }

    private func waitForRemoteClipboard(after count: Int) async throws {
        try await probe.wait("server clipboard", timeout: 15) { self.clipboard.publishedRemoteChanges > count }
    }

    /// Puts content on the private pasteboard and waits until the server took the format list.
    private func announce(_ write: (NSPasteboard) -> Void) async throws {
        let before = clipboard.acceptedAnnouncements
        pasteboard.clearContents()
        write(pasteboard)
        clipboard.checkPasteboard()
        try await probe.wait("format list accepted", timeout: 10) { self.clipboard.acceptedAnnouncements > before }
    }

    private func runDialog(_ command: String) async throws {
        try await keyboard.tap("win+r")
        try await Task.sleep(for: .seconds(1.5))
        try await keyboard.type(command + "\n")
    }

    /// Runs `clip.ps1 <action>` in the session and returns what it reported.
    private func runScript(_ action: String) async throws -> String {
        let name = action.split(separator: " ").first.map(String.init) ?? action
        let done = TestVM.directory + "\\\(name).done"
        try vm.powershell("Remove-Item -Force -ErrorAction SilentlyContinue '\(done)', '\(TestVM.directory)\\dump.b64', '\(TestVM.directory)\\image.png'")
        try await runDialog(SessionScript.command(action))
        let result = try await vm.waitForFile(done, timeout: 45)
        log("\(name): \(result)")
        if result.hasPrefix("error") { throw E2EFailure("\(name) failed in the session: \(result)") }
        return result
    }

    private func snapshot(_ name: String) {
        guard let snapshot = FramebufferSnapshot(session: probe.session) else { return }
        try? snapshot.writePNG(to: evidence.appendingPathComponent("\(name).png"))
    }

    private func check(_ name: String, _ actual: String, equals expected: String) {
        check(name, actual == expected, "expected \(expected.debugDescription), got \(actual.debugDescription)")
    }

    private func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String) {
        checks += 1
        if passed {
            log("PASS \(name)")
        } else {
            let message = "\(name): \(detail())"
            failures.append(message)
            log("FAIL \(message)")
            snapshot("fail-\(checks)")
        }
    }

    /// The bytes between StartFragment and EndFragment, if every offset in the header is consistent.
    static func cfHTMLFragment(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        let header = String(decoding: bytes.prefix(200), as: UTF8.self)
        func offset(_ key: String) -> Int? {
            guard let range = header.range(of: key + ":") else { return nil }
            return Int(header[range.upperBound...].prefix(10))
        }
        guard let startHTML = offset("StartHTML"), let endHTML = offset("EndHTML"),
              let start = offset("StartFragment"), let end = offset("EndFragment"),
              startHTML < start, start <= end, end <= endHTML, endHTML <= bytes.count,
              bytes[startHTML..<endHTML].starts(with: Array("<html".utf8)),
              bytes[..<endHTML].reversed().starts(with: Array(">lmth/<".utf8)),
              bytes[..<start].reversed().starts(with: Array(">--tnemgarFtratS--!<".utf8)),
              bytes[end...].starts(with: Array("<!--EndFragment-->".utf8))
        else { return nil }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }
}

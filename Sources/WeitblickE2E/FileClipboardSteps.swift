import AppKit
import Foundation

/// Files over the clipboard, both directions: files and folders with umlaut names, an empty file
/// and folder, and a 50 MB file.
extension Scenario {
    /// Mac "Finder copy" (file URLs on the pasteboard) → Explorer paste in the session.
    func filesFromMacToWindows() async throws {
        let source = scratch.appendingPathComponent("send", isDirectory: true)
        try? FileManager.default.removeItem(at: source)
        try TestFiles.write("Grüße vom Mac ✓", to: source.appendingPathComponent("Grüße-vom-Mac.txt"))
        try TestFiles.write("innen", to: source.appendingPathComponent("Mac-Ordner-Ä/innen-ö.txt"))
        try TestFiles.writeRandom(megabytes: 1, to: source.appendingPathComponent("Mac-Ordner-Ä/tief/daten.bin"))
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Mac-Ordner-Ä/leer"), withIntermediateDirectories: true)
        try TestFiles.writeRandom(megabytes: 50, to: source.appendingPathComponent("groß-50MB.bin"))
        try TestFiles.write("", to: source.appendingPathComponent("leer.txt"))
        let items = ["Grüße-vom-Mac.txt", "Mac-Ordner-Ä", "groß-50MB.bin", "leer.txt"].map { source.appendingPathComponent($0) }
        let expected = try TestFiles.manifest(of: items)
        let files = expected.values.filter { $0 != "dir" }
        let bytes = files.compactMap { $0.split(separator: " ").first.flatMap { Int($0) } }.reduce(0, +)

        try await announce { $0.writeObjects(items.map { $0 as NSURL }) }
        let result = try await runScript("paste \(files.count) \(bytes)", files: true, timeout: 300)
        let pasted = try vm.read(TestVM.directory + #"\paste.manifest"#).map { TestFiles.parse(String(decoding: $0, as: UTF8.self)) } ?? [:]
        check("files Mac → Windows: \(expected.count) files and folders, 50 MB, umlauts, same bytes",
              pasted == expected, "\(TestFiles.difference(pasted, expected)); \(result)")
    }

    /// Explorer copy (CF_HDROP) in the session → the Mac reads the items' file URLs like Finder does.
    func filesFromWindowsToMac() async throws {
        let before = clipboard.publishedRemoteChanges
        let result = try await runScript("copy-files", files: true, timeout: 120)
        try await probe.wait("server file list", timeout: 20) { self.clipboard.publishedRemoteChanges > before }
        let expected = try vm.read(TestVM.directory + #"\copy.manifest"#).map { TestFiles.parse(String(decoding: $0, as: UTF8.self)) } ?? [:]
        let items = pasteboard.pasteboardItems ?? []
        check("files Windows → Mac: one pasteboard item per copied item", items.count == 3, "\(items.count) items; \(result)")

        let started = Date()
        let urls = items.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)) }
        let seconds = Date().timeIntervalSince(started)
        let received = try TestFiles.manifest(of: urls)
        check("files Windows → Mac: folders, 50 MB, umlauts, same bytes", received == expected,
              "\(TestFiles.difference(received, expected)); urls \(urls.map(\.lastPathComponent))")
        log(String(format: "files Windows → Mac: %.1f s for about 51 MB (%.1f MB/s)", seconds, seconds > 0 ? 51 / seconds : 0))
    }
}

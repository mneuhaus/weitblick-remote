import CryptoKit
import Foundation

/// Test files on the Mac side and the manifests both sides compare ("relative\path" → size and
/// SHA-256; folders map to "dir").
enum TestFiles {
    typealias Manifest = [String: String]

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func writeRandom(megabytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var chunk = Data(count: 1 << 20)
        for _ in 0..<megabytes {
            chunk.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
            try handle.write(contentsOf: chunk)
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The manifest of `items` as copied together: each item and, for folders, everything inside.
    static func manifest(of items: [URL]) throws -> Manifest {
        var manifest: Manifest = [:]
        for item in items {
            let name = item.lastPathComponent
            try add(item, as: name, to: &manifest)
            guard isDirectory(item), let walker = FileManager.default.enumerator(atPath: item.path) else { continue }
            for case let relative as String in walker {
                try add(item.appendingPathComponent(relative), as: name + "\\" + relative.replacingOccurrences(of: "/", with: "\\"), to: &manifest)
            }
        }
        return manifest
    }

    /// Parses `files.ps1` manifest lines.
    static func parse(_ text: String) -> Manifest {
        var manifest: Manifest = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            manifest[parts[0].precomposedStringWithCanonicalMapping] = parts[1] == "dir" ? "dir" : "\(parts[1]) \(parts[2])"
        }
        return manifest
    }

    /// What differs, for a failure message ("" when equal).
    static func difference(_ actual: Manifest, _ expected: Manifest) -> String {
        let missing = expected.keys.filter { actual[$0] == nil }.sorted()
        let extra = actual.keys.filter { expected[$0] == nil }.sorted()
        let wrong = expected.keys.filter { actual[$0] != nil && actual[$0] != expected[$0] }.sorted()
        return [("missing", missing), ("unexpected", extra), ("different", wrong)]
            .filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1.joined(separator: ", "))" }.joined(separator: "; ")
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func add(_ url: URL, as path: String, to manifest: inout Manifest) throws {
        let key = path.precomposedStringWithCanonicalMapping
        if isDirectory(url) {
            manifest[key] = "dir"
        } else if url.lastPathComponent != ".DS_Store" {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            manifest[key] = "\(size) \(try sha256(of: url))"
        }
    }
}

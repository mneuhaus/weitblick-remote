import Foundation

/// Credentials of the development VM from `.testvm.env` (gitignored, KEY=VALUE lines).
/// Used by the smoke test and by DEBUG builds to prefill the connect form.
public struct TestVMEnvironment: Sendable {
    public let host: String
    public let username: String
    public let password: String

    public init(contentsOf url: URL) throws {
        let values = try Self.parse(String(contentsOf: url, encoding: .utf8))
        guard let host = values["WEITBLICK_TEST_HOST"], let username = values["WEITBLICK_TEST_USER"],
              let password = values["WEITBLICK_TEST_PASS"]
        else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        self.host = host
        self.username = username
        self.password = password
    }

    /// `$WEITBLICK_TESTVM_ENV`, else the first `.testvm.env` found walking up from the
    /// working directory or from this source file (the repository in local builds).
    public static func locate(sourceFile: String = #filePath) -> URL? {
        if let explicit = ProcessInfo.processInfo.environment["WEITBLICK_TESTVM_ENV"] {
            return URL(fileURLWithPath: explicit)
        }
        let starts = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: sourceFile).deletingLastPathComponent(),
        ]
        for start in starts {
            var directory = start
            while directory.path != "/" {
                let candidate = directory.appendingPathComponent(".testvm.env")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }

    private static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }
}

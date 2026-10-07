import ConnectionStore
import Foundation

/// Where the app reads and writes its data. Tests and dry runs point it elsewhere with
/// `--store <file>` / `--jump-dir <folder>` / `--jump-profile <file>` or the environment variables
/// `WEITBLICK_STORE`, `WEITBLICK_JUMP_DIR`, `WEITBLICK_JUMP_PROFILE`.
struct LaunchOptions {
    var storeURL = ConnectionStore.defaultFileURL
    var jumpDirectory = JumpImporter.defaultDirectory
    var jumpInputProfileURL = JumpInputProfileImporter.defaultFileURL
    /// All command-line arguments, for the DEBUG hooks.
    var arguments: [String]

    init(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.arguments = arguments
        if let path = Self.value(of: "--store", in: arguments) ?? environment["WEITBLICK_STORE"] {
            storeURL = URL(fileURLWithPath: path)
        }
        if let path = Self.value(of: "--jump-dir", in: arguments) ?? environment["WEITBLICK_JUMP_DIR"] {
            jumpDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = Self.value(of: "--jump-profile", in: arguments) ?? environment["WEITBLICK_JUMP_PROFILE"] {
            jumpInputProfileURL = URL(fileURLWithPath: path)
        }
    }

    /// The argument following `flag`, if any.
    static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

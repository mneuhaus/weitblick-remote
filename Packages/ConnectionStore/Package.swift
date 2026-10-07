// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConnectionStore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConnectionStore", targets: ["ConnectionStore"]),
        .executable(name: "connection-store-dry-run", targets: ["ConnectionStoreDryRun"]),
    ],
    dependencies: [.package(path: "../KeyboardEngine")],
    targets: [
        // User-facing import notes are localized (German in the catalog). SwiftPM on the command line
        // copies the catalog without compiling it, so `swift test` always sees the English text.
        .target(name: "ConnectionStore", dependencies: ["KeyboardEngine"],
                resources: [.process("Localizable.xcstrings")]),
        .executableTarget(name: "ConnectionStoreDryRun", dependencies: ["ConnectionStore"]),
        .testTarget(name: "ConnectionStoreTests", dependencies: ["ConnectionStore"],
                    resources: [.copy("Fixtures")]),
    ]
)

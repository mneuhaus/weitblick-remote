// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConnectionStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConnectionStore", targets: ["ConnectionStore"]),
        .executable(name: "connection-store-dry-run", targets: ["ConnectionStoreDryRun"]),
    ],
    dependencies: [.package(path: "../KeyboardEngine")],
    targets: [
        .target(name: "ConnectionStore", dependencies: ["KeyboardEngine"]),
        .executableTarget(name: "ConnectionStoreDryRun", dependencies: ["ConnectionStore"]),
        .testTarget(name: "ConnectionStoreTests", dependencies: ["ConnectionStore"],
                    resources: [.copy("Fixtures")]),
    ]
)

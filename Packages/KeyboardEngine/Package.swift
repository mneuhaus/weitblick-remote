// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyboardEngine", targets: ["KeyboardEngine", "KeyboardEngineCarbon"]),
    ],
    targets: [
        // Pure Swift: no Foundation, AppKit or Carbon. All translation logic lives here.
        .target(name: "KeyboardEngine"),
        // macOS glue: UCKeyTranslate layout provider and input source (TIS) helpers.
        .target(
            name: "KeyboardEngineCarbon",
            dependencies: ["KeyboardEngine"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "KeyboardEngineTests",
            dependencies: ["KeyboardEngine", "KeyboardEngineCarbon"]
        ),
    ]
)

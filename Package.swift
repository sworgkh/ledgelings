// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ledgelings",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic: no AppKit, no window. Everything worth unit-testing lives here.
        .target(name: "LedgelingsCore"),
        .executableTarget(
            name: "Ledgelings",
            dependencies: ["LedgelingsCore"],
            resources: [.copy("Resources/sprites")]
        ),
        .testTarget(name: "LedgelingsCoreTests", dependencies: ["LedgelingsCore"]),
        .testTarget(name: "LedgelingsTests", dependencies: ["Ledgelings"]),
    ]
)

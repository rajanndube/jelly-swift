// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jelly",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .visionOS(.v1),
        // SDK no-ops on macOS — UIKit isn't available, so `canImport(UIKit)`
        // gates compile out. Listed for SwiftPM resolution only.
        .macOS(.v13),
    ],
    products: [
        .library(name: "Jelly", targets: ["Jelly"]),
    ],
    targets: [
        .target(
            name: "Jelly",
            path: "Sources/Jelly"
        ),
        .testTarget(
            name: "JellyTests",
            dependencies: ["Jelly"],
            path: "Tests/JellyTests",
            resources: [.process("Fixtures")]
        ),
    ]
)

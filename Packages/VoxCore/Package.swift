// swift-tools-version:5.10
// VoxCore: all platform-independent logic (config, parsing, routing, safety,
// tmux control, engine). No AppKit/SwiftUI here, so `swift test` runs anywhere.
import PackageDescription

let package = Package(
    name: "VoxCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"])
    ],
    targets: [
        .target(name: "VoxCore"),
        // Real-machine checks (tmux, your config, your tools). Run: scripts/Verify-Tools.command
        .executableTarget(name: "VoxSelfTest", dependencies: ["VoxCore"]),
        .testTarget(name: "VoxCoreTests", dependencies: ["VoxCore"])
    ]
)

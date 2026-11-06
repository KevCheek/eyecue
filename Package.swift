// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SnowpineCue",
    platforms: [.macOS(.v14)],
    targets: [
        // Script parsing, layout and the voice tracker. No AppKit, so it is easy to test.
        .target(name: "SnowpineCueCore", path: "Sources/SnowpineCueCore"),
        // The menu bar app: prompter panel, speech input, hotkeys.
        .executableTarget(name: "SnowpineCue", dependencies: ["SnowpineCueCore"], path: "Sources/SnowpineCue"),
        .testTarget(name: "SnowpineCueCoreTests", dependencies: ["SnowpineCueCore"], path: "Tests/SnowpineCueCoreTests"),
    ]
)

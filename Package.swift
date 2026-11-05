// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EyeCue",
    platforms: [.macOS(.v14)],
    targets: [
        // Script parsing, layout and the voice tracker. No AppKit, so it is easy to test.
        .target(name: "EyeCueCore", path: "Sources/EyeCueCore"),
        // The menu bar app: prompter panel, speech input, hotkeys.
        .executableTarget(name: "EyeCue", dependencies: ["EyeCueCore"], path: "Sources/EyeCue"),
        .testTarget(name: "EyeCueCoreTests", dependencies: ["EyeCueCore"], path: "Tests/EyeCueCoreTests"),
    ]
)

// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SnowpineCue",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates: the one third-party dependency, pinned to an exact version.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Script parsing, layout and the voice tracker. No AppKit, so it is easy to test.
        .target(name: "SnowpineCueCore", path: "Sources/SnowpineCueCore"),
        // The menu bar app: prompter panel, speech input, hotkeys.
        .executableTarget(name: "SnowpineCue", dependencies: ["SnowpineCueCore", .product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/SnowpineCue"),
        .testTarget(name: "SnowpineCueCoreTests", dependencies: ["SnowpineCueCore"], path: "Tests/SnowpineCueCoreTests"),
    ]
)

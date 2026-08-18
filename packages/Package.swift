// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "UtataneKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UtataneCore", targets: ["UtataneCore"]),
        .library(name: "UtataneBalloon", targets: ["UtataneBalloon"]),
        .library(name: "UtataneSakuraScript", targets: ["UtataneSakuraScript"]),
        .library(name: "UtataneGhostKit", targets: ["UtataneGhostKit"]),
        .library(name: "UtataneShell", targets: ["UtataneShell"]),
        .library(name: "UtataneRuntime", targets: ["UtataneRuntime"]),
        .library(name: "UtatanePlatformMacOS", targets: ["UtatanePlatformMacOS"]),
        .library(name: "UtataneSatoriConverter", targets: ["UtataneSatoriConverter"]),
        .executable(name: "utatane-satori-convert", targets: ["UtataneSatoriConvertCLI"])
    ],
    targets: [
        .target(
            name: "UtataneCore",
            path: "core/Sources"
        ),
        .target(
            name: "UtataneBalloon",
            path: "balloon/Sources"
        ),
        .target(
            name: "UtataneSakuraScript",
            path: "sakura-script/Sources"
        ),
        .target(
            name: "UtataneRuntime",
            dependencies: ["UtataneCore", "UtataneSakuraScript"],
            path: "runtime/Sources"
        ),
        .target(
            name: "UtataneGhostKit",
            dependencies: ["UtataneCore", "UtataneRuntime"],
            path: "ghost-kit/Sources"
        ),
        .target(
            name: "UtataneShell",
            dependencies: ["UtataneCore"],
            path: "shell/Sources"
        ),
        .target(
            name: "UtatanePlatformMacOS",
            dependencies: [
                "UtataneBalloon",
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShell"
            ],
            path: "platform-macos/Sources"
        ),
        .target(
            name: "UtataneSatoriConverter",
            dependencies: ["UtataneRuntime"],
            path: "satori-converter/Sources"
        ),
        .executableTarget(
            name: "UtataneSatoriConvertCLI",
            dependencies: ["UtataneSatoriConverter"],
            path: "satori-converter/CLI"
        ),
        .testTarget(
            name: "UtataneBalloonTests",
            dependencies: ["UtataneBalloon"],
            path: "balloon/Tests"
        ),
        .testTarget(
            name: "UtataneCoreTests",
            dependencies: ["UtataneCore"],
            path: "core/Tests"
        ),
        .testTarget(
            name: "UtataneRuntimeTests",
            dependencies: ["UtataneCore", "UtataneRuntime"],
            path: "runtime/Tests"
        ),
        .testTarget(
            name: "UtataneGhostKitTests",
            dependencies: ["UtataneGhostKit"],
            path: "ghost-kit/Tests"
        ),
        .testTarget(
            name: "UtataneShellTests",
            dependencies: ["UtataneShell"],
            path: "shell/Tests"
        ),
        .testTarget(
            name: "UtataneSakuraScriptTests",
            dependencies: ["UtataneSakuraScript"],
            path: "sakura-script/Tests"
        ),
        .testTarget(
            name: "UtatanePlatformMacOSTests",
            dependencies: ["UtataneCore", "UtatanePlatformMacOS"],
            path: "platform-macos/Tests"
        ),
        .testTarget(
            name: "UtataneSatoriConverterTests",
            dependencies: ["UtataneSatoriConverter"],
            path: "satori-converter/Tests"
        )
    ],
    swiftLanguageModes: [.v6]
)

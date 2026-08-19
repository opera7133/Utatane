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
        .library(name: "UtataneContent", targets: ["UtataneContent"]),
        .library(name: "UtataneShell", targets: ["UtataneShell"]),
        .library(name: "UtataneRuntime", targets: ["UtataneRuntime"]),
        .library(name: "UtataneShiori", targets: ["UtataneShiori"]),
        .library(name: "UtataneYaya", targets: ["UtataneYaya"]),
        .library(name: "UtataneYayaNative", targets: ["UtataneYayaNative"]),
        .library(name: "UtatanePlatformMacOS", targets: ["UtatanePlatformMacOS"]),
        .library(name: "UtataneSatoriConverter", targets: ["UtataneSatoriConverter"]),
        .executable(name: "utatane-satori-convert", targets: ["UtataneSatoriConvertCLI"]),
        .executable(name: "utatane-yaya-audit", targets: ["UtataneYayaAuditCLI"])
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
            name: "UtataneContent",
            path: "content/Sources"
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
        .target(
            name: "UtataneShiori",
            dependencies: ["UtataneCore"],
            path: "shiori/Sources"
        ),
        .target(
            name: "UtataneYaya",
            dependencies: ["UtataneShiori"],
            path: "yaya/Sources"
        ),
        .target(
            name: "CYayaNative",
            path: "yaya-native/Sources/CYayaNative",
            exclude: ["Vendor/YAYA/LICENSE"],
            publicHeadersPath: "Include",
            cSettings: [.define("POSIX")],
            cxxSettings: [
                .define("POSIX"),
                .headerSearchPath("Vendor/YAYA")
            ]
        ),
        .target(
            name: "UtataneYayaNative",
            dependencies: [
                "CYayaNative",
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "yaya-native/Sources/UtataneYayaNative"
        ),
        .executableTarget(
            name: "UtataneSatoriConvertCLI",
            dependencies: ["UtataneSatoriConverter"],
            path: "satori-converter/CLI"
        ),
        .executableTarget(
            name: "UtataneYayaAuditCLI",
            dependencies: ["UtataneYaya"],
            path: "yaya/CLI"
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
            name: "UtataneContentTests",
            dependencies: ["UtataneContent"],
            path: "content/Tests"
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
        ),
        .testTarget(
            name: "UtataneShioriTests",
            dependencies: ["UtataneCore", "UtataneShiori"],
            path: "shiori/Tests"
        ),
        .testTarget(
            name: "UtataneYayaTests",
            dependencies: ["UtataneYaya"],
            path: "yaya/Tests"
        ),
        .testTarget(
            name: "UtataneYayaNativeTests",
            dependencies: ["UtataneShiori", "UtataneYayaNative"],
            path: "yaya-native/Tests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)

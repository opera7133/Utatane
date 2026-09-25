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
        .library(name: "UtataneNetwork", targets: ["UtataneNetwork"]),
        .library(name: "UtataneModuleCatalog", targets: ["UtataneModuleCatalog"]),
        .library(name: "UtataneShell", targets: ["UtataneShell"]),
        .library(name: "UtataneRuntime", targets: ["UtataneRuntime"]),
        .library(name: "UtataneAI", targets: ["UtataneAI"]),
        .library(name: "UtataneRealtime", targets: ["UtataneRealtime"]),
        .library(name: "UtataneShiori", targets: ["UtataneShiori"]),
        .library(name: "UtataneMakoto", targets: ["UtataneMakoto"]),
        .library(name: "UtataneWindowsShiori", targets: ["UtataneWindowsShiori"]),
        .library(name: "UtatanePOSIXShiori", targets: ["UtatanePOSIXShiori"]),
        .library(name: "UtataneModuleHost", targets: ["UtataneModuleHost"]),
        .library(name: "UtatanePlugin", targets: ["UtatanePlugin"]),
        .library(name: "UtataneFirstNative", targets: ["UtataneFirstNative"]),
        .library(name: "UtataneNativeSaori", targets: ["UtataneNativeSaori"]),
        .library(name: "UtatanePlatformMacOS", targets: ["UtatanePlatformMacOS"]),
        .executable(name: "utatane-mcp", targets: ["UtataneMCP"]),
        .executable(name: "utatane-validate", targets: ["UtataneValidate"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "UtataneCore",
            dependencies: ["UtataneLegacyTextCodec"],
            path: "core/Sources"
        ),
        .target(
            name: "UtataneLegacyTextCodec",
            path: "legacy-text-codec/Sources",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("iconv", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "UtataneBalloon",
            dependencies: ["UtataneCore"],
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
            name: "UtataneAI",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript"],
            path: "ai/Sources"
        ),
        .target(
            name: "UtataneRealtime",
            path: "realtime/Sources"
        ),
        .target(
            name: "UtataneGhostKit",
            dependencies: ["UtataneCore", "UtataneRuntime"],
            path: "ghost-kit/Sources"
        ),
        .target(
            name: "UtataneContent",
            dependencies: ["UtataneCore"],
            path: "content/Sources"
        ),
        .target(
            name: "UtataneNetwork",
            path: "network/Sources"
        ),
        .target(
            name: "UtataneModuleCatalog",
            dependencies: ["UtataneCore", "UtataneNetwork", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "module-catalog/Sources"
        ),
        .executableTarget(
            name: "UtataneMCP",
            path: "mcp-server/Sources"
        ),
        .target(
            name: "UtataneContentValidator",
            dependencies: [
                "UtataneCore",
                "UtataneGhostKit",
                "UtataneSakuraScript",
                "UtataneShell",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "content-validator/Sources"
        ),
        .executableTarget(
            name: "UtataneValidate",
            dependencies: ["UtataneContentValidator"],
            path: "content-validator-cli/Sources"
        ),
        .target(
            name: "UtataneShell",
            dependencies: ["UtataneCore"],
            path: "shell/Sources"
        ),
        .target(
            name: "CNicxliveRenderer",
            path: "platform-macos-nicxlive/Sources",
            publicHeadersPath: "Include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ]
        ),
        .target(
            name: "UtatanePlatformMacOS",
            dependencies: [
                "CNicxliveRenderer",
                "UtataneBalloon",
                "UtataneContentValidator",
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShell"
            ],
            path: "platform-macos/Sources",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        ),
        .target(
            name: "UtataneShiori",
            dependencies: ["UtataneCore"],
            path: "shiori/Sources"
        ),
        .target(
            name: "UtataneMakoto",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript"],
            path: "makoto/Sources"
        ),
        .target(
            name: "UtataneWindowsShiori",
            dependencies: [
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori",
                "UtataneNetwork"
            ],
            path: "shiori/external/windows/Sources"
        ),
        .target(
            name: "UtatanePOSIXShiori",
            dependencies: [
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "shiori/external/posix/Sources"
        ),
        .target(
            name: "UtatanePlugin",
            dependencies: ["UtataneCore", "UtataneShiori", "UtataneModuleHost", "UtataneNativeSaori"],
            path: "plugin/Sources"
        ),
        .target(
            name: "UtataneFirstNative",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript"],
            path: "shiori/native/first/Sources"
        ),
        .target(
            name: "UtataneNativeSaori",
            path: "native-saori/Sources"
        ),
        .target(
            name: "CMisakaHostBridge",
            path: "shiori/external/module/MisakaBridge",
            exclude: ["LICENSE"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "UtataneModuleHost",
            dependencies: ["CMisakaHostBridge", "UtataneCore", "UtataneNativeSaori", "UtataneShiori"],
            path: "shiori/external/module/Sources"
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
            name: "UtataneAITests",
            dependencies: ["UtataneAI", "UtataneCore"],
            path: "ai/Tests"
        ),
        .testTarget(
            name: "UtataneRealtimeTests",
            dependencies: ["UtataneRealtime"],
            path: "realtime/Tests"
        ),
        .testTarget(
            name: "UtataneGhostKitTests",
            dependencies: ["UtataneGhostKit"],
            path: "ghost-kit/Tests"
        ),
        .testTarget(
            name: "UtataneContentTests",
            dependencies: ["UtataneContent", "UtataneCore"],
            path: "content/Tests"
        ),
        .testTarget(
            name: "UtataneNetworkTests",
            dependencies: ["UtataneNetwork"],
            path: "network/Tests"
        ),
        .testTarget(
            name: "UtataneModuleCatalogTests",
            dependencies: ["UtataneCore", "UtataneModuleCatalog", "UtataneNetwork", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "module-catalog/Tests"
        ),
        .testTarget(
            name: "UtataneMCPTests",
            dependencies: ["UtataneMCP"],
            path: "mcp-server/Tests"
        ),
        .testTarget(
            name: "UtataneContentValidatorTests",
            dependencies: [
                "UtataneContentValidator",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "content-validator/Tests"
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
            name: "UtataneShioriTests",
            dependencies: ["UtataneCore", "UtataneShiori"],
            path: "shiori/Tests"
        ),
        .testTarget(
            name: "UtataneMakotoTests",
            dependencies: ["UtataneMakoto"],
            path: "makoto/Tests"
        ),
        .testTarget(
            name: "UtataneWindowsShioriTests",
            dependencies: ["UtataneWindowsShiori"],
            path: "shiori/external/windows/Tests"
        ),
        .testTarget(
            name: "UtatanePOSIXShioriTests",
            dependencies: ["UtatanePOSIXShiori"],
            path: "shiori/external/posix/Tests"
        ),
        .testTarget(
            name: "UtatanePluginTests",
            dependencies: ["UtatanePlugin"],
            path: "plugin/Tests"
        ),
        .testTarget(
            name: "UtataneFirstNativeTests",
            dependencies: ["UtataneFirstNative"],
            path: "shiori/native/first/Tests"
        ),
        .testTarget(
            name: "UtataneNativeSaoriTests",
            dependencies: ["UtataneNativeSaori"],
            path: "native-saori/Tests"
        ),
        .testTarget(
            name: "UtataneModuleHostTests",
            dependencies: ["UtataneModuleHost", "UtataneNativeSaori", "UtataneShiori"],
            path: "shiori/external/module/Tests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)

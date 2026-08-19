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
        .library(name: "UtataneShell", targets: ["UtataneShell"]),
        .library(name: "UtataneRuntime", targets: ["UtataneRuntime"]),
        .library(name: "UtataneShiori", targets: ["UtataneShiori"]),
        .library(name: "UtataneYayaNative", targets: ["UtataneYayaNative"]),
        .library(name: "UtataneSatoriNative", targets: ["UtataneSatoriNative"]),
        .library(name: "UtatanePlatformMacOS", targets: ["UtatanePlatformMacOS"])
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
            name: "UtataneNetwork",
            path: "network/Sources"
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
            name: "UtataneShiori",
            dependencies: ["UtataneCore"],
            path: "shiori/Sources"
        ),
        .target(
            name: "CYayaNative",
            path: "yaya-native/Sources/CYayaNative",
            sources: [
                "YayaBridge.cpp",
                "Vendor/YAYA/aya5.cpp",
                "Vendor/YAYA/ayavm.cpp",
                "Vendor/YAYA/basis.cpp",
                "Vendor/YAYA/ccct.cpp",
                "Vendor/YAYA/comment.cpp",
                "Vendor/YAYA/crc32.c",
                "Vendor/YAYA/dir_enum.cpp",
                "Vendor/YAYA/duplevinfo.cpp",
                "Vendor/YAYA/file.cpp",
                "Vendor/YAYA/file1.cpp",
                "Vendor/YAYA/function.cpp",
                "Vendor/YAYA/globalvariable.cpp",
                "Vendor/YAYA/lib.cpp",
                "Vendor/YAYA/lib1.cpp",
                "Vendor/YAYA/localvariable.cpp",
                "Vendor/YAYA/log.cpp",
                "Vendor/YAYA/logexcode.cpp",
                "Vendor/YAYA/manifest.cpp",
                "Vendor/YAYA/md5c.c",
                "Vendor/YAYA/messages.cpp",
                "Vendor/YAYA/misc.cpp",
                "Vendor/YAYA/mt19937ar.cpp",
                "Vendor/YAYA/parser0.cpp",
                "Vendor/YAYA/parser1.cpp",
                "Vendor/YAYA/posix_utils.cpp",
                "Vendor/YAYA/selecter.cpp",
                "Vendor/YAYA/sha1.c",
                "Vendor/YAYA/sysfunc.cpp",
                "Vendor/YAYA/value.cpp",
                "Vendor/YAYA/valuesub.cpp",
                "Vendor/YAYA/variable.cpp",
                "Vendor/YAYA/wsex.cpp"
            ],
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
        .target(
            name: "CSatoriNative",
            path: "satori-native/Sources/CSatoriNative",
            sources: [
                "SatoriBridge.cpp",
                "CharsetPOSIX.cpp",
                "Vendor/_/Sender.cpp",
                "Vendor/_/Utilities.cpp",
                "Vendor/_/calc.cpp",
                "Vendor/_/calc_float.cpp",
                "Vendor/_/stltool.cpp",
                "Vendor/_/random.cpp",
                "Vendor/_/mt19937ar.cpp",
                "Vendor/satori/SakuraCS.cpp",
                "Vendor/satori/SakuraClient.cpp",
                "Vendor/satori/SakuraDLLClient.cpp",
                "Vendor/satori/SakuraDLLHost.cpp",
                "Vendor/satori/SaoriClient.cpp",
                "Vendor/satori/satori.cpp",
                "Vendor/satori/satoriTranslate.cpp",
                "Vendor/satori/satori_AnalyzeRequest.cpp",
                "Vendor/satori/satori_CreateResponce.cpp",
                "Vendor/satori/satori_EventOperation.cpp",
                "Vendor/satori/satori_Kakko.cpp",
                "Vendor/satori/satori_load_dict.cpp",
                "Vendor/satori/satori_load_unload.cpp",
                "Vendor/satori/satori_sentence.cpp",
                "Vendor/satori/satori_tool.cpp",
                "Vendor/satori/shiori_plugin.cpp",
                "Vendor/satori/ssu.cpp"
            ],
            publicHeadersPath: "Include",
            cxxSettings: [
                .define("POSIX"),
                .define("SATORI_DLL"),
                .headerSearchPath("Vendor/satori"),
                .headerSearchPath("Vendor/_")
            ],
            linkerSettings: [.linkedLibrary("iconv")]
        ),
        .target(
            name: "UtataneSatoriNative",
            dependencies: [
                "CSatoriNative",
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "satori-native/Sources/UtataneSatoriNative"
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
            name: "UtataneNetworkTests",
            dependencies: ["UtataneNetwork"],
            path: "network/Tests"
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
            name: "UtataneYayaNativeTests",
            dependencies: ["UtataneCore", "UtataneShiori", "UtataneYayaNative"],
            path: "yaya-native/Tests"
        ),
        .testTarget(
            name: "UtataneSatoriNativeTests",
            dependencies: ["UtataneCore", "UtataneShiori", "UtataneSatoriNative"],
            path: "satori-native/Tests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)

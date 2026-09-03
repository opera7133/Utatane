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
        .library(name: "UtataneAI", targets: ["UtataneAI"]),
        .library(name: "UtataneRealtime", targets: ["UtataneRealtime"]),
        .library(name: "UtataneShiori", targets: ["UtataneShiori"]),
        .library(name: "UtataneMakoto", targets: ["UtataneMakoto"]),
        .library(name: "UtataneWindowsShiori", targets: ["UtataneWindowsShiori"]),
        .library(name: "UtatanePOSIXShiori", targets: ["UtatanePOSIXShiori"]),
        .library(name: "UtatanePlugin", targets: ["UtatanePlugin"]),
        .library(name: "UtataneKawariNative", targets: ["UtataneKawariNative"]),
        .library(name: "UtataneYayaNative", targets: ["UtataneYayaNative"]),
        .library(name: "UtataneSatoriNative", targets: ["UtataneSatoriNative"]),
        .library(name: "UtataneFirstNative", targets: ["UtataneFirstNative"]),
        .library(name: "UtataneNativeSaori", targets: ["UtataneNativeSaori"]),
        .library(name: "UtataneMisakaNative", targets: ["UtataneMisakaNative"]),
        .library(name: "UtataneAkariNative", targets: ["UtataneAkariNative"]),
        .library(name: "UtataneEseShioriNative", targets: ["UtataneEseShioriNative"]),
        .library(name: "UtataneNiseShioriNative", targets: ["UtataneNiseShioriNative"]),
        .library(name: "UtataneShinoNative", targets: ["UtataneShinoNative"]),
        .library(name: "UtataneHisuiNative", targets: ["UtataneHisuiNative"]),
        .library(name: "UtataneYuhnaNative", targets: ["UtataneYuhnaNative"]),
        .library(name: "UtatanePlatformMacOS", targets: ["UtatanePlatformMacOS"]),
        .executable(name: "utatane-mcp", targets: ["UtataneMCP"])
    ],
    targets: [
        .target(
            name: "UtataneCore",
            path: "core/Sources"
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
        .executableTarget(
            name: "UtataneMCP",
            path: "mcp-server/Sources"
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
            cxxSettings: [.define("GL_SILENCE_DEPRECATION")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("OpenGL")
            ]
        ),
        .target(
            name: "UtatanePlatformMacOS",
            dependencies: [
                "CNicxliveRenderer",
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
            path: "windows-shiori/Sources"
        ),
        .target(
            name: "UtatanePOSIXShiori",
            dependencies: [
                "UtataneCore",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "posix-shiori/Sources"
        ),
        .target(
            name: "UtatanePlugin",
            dependencies: ["UtataneCore", "UtataneShiori"],
            path: "plugin/Sources"
        ),
        .target(
            name: "CKawariNative",
            path: "kawari-native/Sources/CKawariNative",
            sources: [
                "KawariBridge.cpp",
                "Vendor/KAWARI/build/src/shiori/kawari_shiori.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_engine.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_ns.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_dict.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_code.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_codeset.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_codeexpr.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_codekis.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_vm.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_lexer.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_compiler.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_log.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_rc.cpp",
                "Vendor/KAWARI/build/src/misc/misc.cpp",
                "Vendor/KAWARI/build/src/misc/mt19937ar.cpp",
                "Vendor/KAWARI/build/src/misc/l10n.cpp",
                "Vendor/KAWARI/build/src/misc/phttp.cpp",
                "Vendor/KAWARI/build/src/saori/saori.cpp",
                "Vendor/KAWARI/build/src/saori/saori_module.cpp",
                "Vendor/KAWARI/build/src/saori/saori_unique.cpp",
                "Vendor/KAWARI/build/src/kis/kis_echo.cpp",
                "Vendor/KAWARI/build/src/kis/kis_dict.cpp",
                "Vendor/KAWARI/build/src/kis/kis_date.cpp",
                "Vendor/KAWARI/build/src/kis/kis_counter.cpp",
                "Vendor/KAWARI/build/src/kis/kis_file.cpp",
                "Vendor/KAWARI/build/src/kis/kis_escape.cpp",
                "Vendor/KAWARI/build/src/kis/kis_urllist.cpp",
                "Vendor/KAWARI/build/src/kis/kis_substitute.cpp",
                "Vendor/KAWARI/build/src/kis/kis_split.cpp",
                "Vendor/KAWARI/build/src/kis/kis_communicate.cpp",
                "Vendor/KAWARI/build/src/kis/kis_xargs.cpp",
                "Vendor/KAWARI/build/src/kis/kis_string.cpp",
                "Vendor/KAWARI/build/src/kis/kis_help.cpp",
                "Vendor/KAWARI/build/src/kis/kis_saori.cpp",
                "Vendor/KAWARI/build/src/kis/kis_system.cpp",
                "Vendor/KAWARI/build/src/libkawari/kawari_crypt.cpp",
                "Vendor/KAWARI/build/src/misc/base64.cpp"
            ],
            publicHeadersPath: "Include",
            cxxSettings: [
                .headerSearchPath("Vendor/KAWARI/build/src"),
                .unsafeFlags(["-Wno-writable-strings", "-Wno-reserved-user-defined-literal"])
            ]
        ),
        .target(
            name: "UtataneKawariNative",
            dependencies: [
                "CKawariNative",
                "UtataneCore",
                "UtataneNativeSaori",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "kawari-native/Sources/UtataneKawariNative"
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
                "UtataneNativeSaori",
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
                "NativeSwiftSaori.cpp",
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
                "UtataneNativeSaori",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "satori-native/Sources/UtataneSatoriNative"
        ),
        .target(
            name: "UtataneFirstNative",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript"],
            path: "first-native/Sources"
        ),
        .target(
            name: "UtataneNativeSaori",
            path: "native-saori/Sources",
            linkerSettings: [.linkedFramework("AVFoundation")]
        ),
        .target(
            name: "UtataneMisakaNative",
            dependencies: [
                "UtataneCore",
                "UtataneNativeSaori",
                "UtataneRuntime",
                "UtataneSakuraScript",
                "UtataneShiori"
            ],
            path: "misaka-native/Sources"
        ),
        .target(
            name: "UtataneAkariNative",
            dependencies: ["UtataneCore", "UtataneNativeSaori", "UtataneRuntime", "UtataneSakuraScript", "UtataneShiori"],
            path: "akari-native/Sources"
        ),
        .target(
            name: "UtataneEseShioriNative",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript", "UtataneShiori"],
            path: "ese-shiori-native/Sources"
        ),
        .target(
            name: "UtataneNiseShioriNative",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript", "UtataneShiori"],
            path: "nise-shiori-native/Sources"
        ),
        .target(
            name: "UtataneShinoNative",
            dependencies: ["UtataneCore", "UtataneNativeSaori", "UtataneRuntime", "UtataneSakuraScript", "UtataneShiori"],
            path: "shino-native/Sources"
        ),
        .target(
            name: "UtataneHisuiNative",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript", "UtataneShiori"],
            path: "hisui-native/Sources"
        ),
        .target(
            name: "UtataneYuhnaNative",
            dependencies: ["UtataneCore", "UtataneRuntime", "UtataneSakuraScript", "UtataneShiori"],
            path: "yuhna-native/Sources"
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
            name: "UtataneMCPTests",
            dependencies: ["UtataneMCP"],
            path: "mcp-server/Tests"
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
            path: "windows-shiori/Tests"
        ),
        .testTarget(
            name: "UtatanePOSIXShioriTests",
            dependencies: ["UtatanePOSIXShiori"],
            path: "posix-shiori/Tests"
        ),
        .testTarget(
            name: "UtatanePluginTests",
            dependencies: ["UtatanePlugin"],
            path: "plugin/Tests"
        ),
        .testTarget(
            name: "UtataneKawariNativeTests",
            dependencies: ["UtataneCore", "UtataneKawariNative", "UtataneShiori"],
            path: "kawari-native/Tests"
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
        ),
        .testTarget(
            name: "UtataneFirstNativeTests",
            dependencies: ["UtataneFirstNative"],
            path: "first-native/Tests"
        ),
        .testTarget(
            name: "UtataneNativeSaoriTests",
            dependencies: ["UtataneNativeSaori"],
            path: "native-saori/Tests"
        ),
        .testTarget(
            name: "UtataneMisakaNativeTests",
            dependencies: ["UtataneCore", "UtataneMisakaNative", "UtataneNativeSaori", "UtataneShiori"],
            path: "misaka-native/Tests"
        ),
        .testTarget(
            name: "UtataneAkariNativeTests",
            dependencies: ["UtataneAkariNative", "UtataneCore", "UtataneNativeSaori"],
            path: "akari-native/Tests"
        ),
        .testTarget(
            name: "UtataneEseShioriNativeTests",
            dependencies: ["UtataneCore", "UtataneEseShioriNative", "UtataneShiori"],
            path: "ese-shiori-native/Tests"
        ),
        .testTarget(
            name: "UtataneNiseShioriNativeTests",
            dependencies: ["UtataneCore", "UtataneNiseShioriNative"],
            path: "nise-shiori-native/Tests"
        ),
        .testTarget(
            name: "UtataneShinoNativeTests",
            dependencies: ["UtataneCore", "UtataneGhostKit", "UtataneShinoNative"],
            path: "shino-native/Tests"
        ),
        .testTarget(
            name: "UtataneHisuiNativeTests",
            dependencies: ["UtataneCore", "UtataneHisuiNative"],
            path: "hisui-native/Tests"
        ),
        .testTarget(
            name: "UtataneYuhnaNativeTests",
            dependencies: ["UtataneCore", "UtataneYuhnaNative"],
            path: "yuhna-native/Tests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)

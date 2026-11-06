import Foundation
import Testing
@testable import UtataneModuleHost

struct DNProxyPreflightTests {
    private struct Fixture {
        let root: URL
        let module: URL
        let dotnet: URL
        var environment: [String: String] {
            ["UTATANE_DOTNET": dotnet.path]
        }

        init(source: Bool = true) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "DNProxy 診断 \(UUID())")
            module = root.appending(path: "module/lib/libdnproxy.dylib")
            dotnet = root.appending(path: "dotnet")
            try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appending(path: "module/bin"), withIntermediateDirectories: true)
            for name in ["DnProxyHost.dll", "DnProxyHost.runtimeconfig.json", "DnProxyHost.deps.json", "Ukagaka.NET.Interfaces.dll"] {
                try Data().write(to: root.appending(path: "module/bin/\(name)"))
            }
            try Data().write(to: module)
            try "#!/bin/sh\nexit 0\n".write(to: dotnet, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dotnet.path)
            try "<configuration><setting name=\"Protocol\"><value>SHIORI/3.0</value></setting></configuration>".write(
                to: root.appending(path: "dnproxy.dll.config"), atomically: true, encoding: .utf8
            )
            if source {
                try "Language: C#\nSourceFiles: Ghost.cs\n".write(to: root.appending(path: "dnproxy.ini"), atomically: true, encoding: .utf8)
            } else {
                try Data().write(to: root.appending(path: "user.dll"))
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func runner(_: URL, arguments: [String], _: [String: String]) throws -> String {
        switch arguments {
        case ["--info"]: "Host:\n  Architecture: arm64\n"
        case ["--list-runtimes"]: "Microsoft.NETCore.App 10.0.1 [/dotnet/shared]\n"
        case ["--list-sdks"]: "10.0.100 [/dotnet/sdk]\n"
        case ["--version"]: "10.0.100\n"
        default: throw CocoaError(.fileReadUnknown)
        }
    }

    @Test func `source mode reports the exact executable and SDK requirement without running ghost code`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment, runner: Self.runner)
        let report = probe.inspect(directoryURL: f.root, moduleURL: f.module)
        #expect(report.status == .ready)
        #expect(report.dotnetURL == f.dotnet)
        #expect(report.architecture == "arm64")
        #expect(report.sdkVersion == "10.0.100")
        #expect(report.requiresSDK)
        #expect(!FileManager.default.fileExists(atPath: f.root.appending(path: "profile").path))
    }

    @Test func `precompiled mode never needs or queries an SDK`() throws {
        let f = try Fixture(source: false)
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { executable, args, environment in
            #expect(args != ["--list-sdks"] && args != ["--version"])
            return try Self.runner(executable, arguments: args, environment)
        }
        let report = probe.inspect(directoryURL: f.root, moduleURL: f.module)
        #expect(report.status == .ready)
        #expect(!report.requiresSDK)
    }

    @Test func `missing module and missing managed host are different failures`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment, runner: Self.runner)
        #expect(probe.inspect(directoryURL: f.root, moduleURL: nil).status == .missingModule)
        try FileManager.default.removeItem(at: f.root.appending(path: "module/bin/Ukagaka.NET.Interfaces.dll"))
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .missingHost)
    }

    @Test func `an invalid explicit dotnet is reported without falling back`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let invalid = f.root.appending(path: "missing-dotnet")
        let probe = DNProxyPreflight(environment: ["UTATANE_DOTNET": invalid.path, "PATH": f.root.path], runner: Self.runner)
        let report = probe.inspect(directoryURL: f.root, moduleURL: f.module)
        #expect(report.status == .missingDotnet)
        #expect(report.dotnetURL == invalid)
    }

    @Test(arguments: ["9.0.9", "11.0.1", "10.0.0-preview.1"])
    func `a different major or preview runtime does not satisfy net10`(_ version: String) throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { exe, args, env in
            args == ["--list-runtimes"] ? "Microsoft.NETCore.App \(version) [/runtime]\n" : try Self.runner(exe, arguments: args, env)
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .missingRuntime)
    }

    @Test func `runtime-only installation gives an actionable source SDK failure`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { exe, args, env in
            args == ["--list-sdks"] ? "" : try Self.runner(exe, arguments: args, env)
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .missingSDK)
    }

    @Test func `a launchable x64 dotnet reports its own runtime architecture`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { exe, args, env in
            args == ["--info"] ? "Host:\n Architecture: x64\n" : try Self.runner(exe, arguments: args, env)
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).architecture == "x64")
    }

    @Test(arguments: ["Language: VB\nSourceFiles: a.vb\n", "SourceFiles: A.cs\nCompilerOptions: /x\n", "SourceFiles: A.cs\nGenerateExecutable: 1\n"])
    func `unsupported settings are distinguished before probing dotnet`(_ ini: String) throws {
        let f = try Fixture()
        defer { f.remove() }
        try ini.write(to: f.root.appending(path: "dnproxy.ini"), atomically: true, encoding: .utf8)
        let probe = DNProxyPreflight(environment: f.environment) { _, _, _ in
            Issue.record("unsupported configuration must not execute dotnet")
            return ""
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .unsupportedConfiguration)
    }

    @Test func `malformed XML and missing source lists are configuration failures`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment, runner: Self.runner)
        try "Language: C#\n".write(to: f.root.appending(path: "dnproxy.ini"), atomically: true, encoding: .utf8)
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .invalidConfiguration)
        try "<configuration>".write(to: f.root.appending(path: "dnproxy.dll.config"), atomically: true, encoding: .utf8)
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .invalidConfiguration)
    }

    @Test func `failed dotnet invocation is not mistaken for a missing runtime`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { _, _, _ in throw CocoaError(.executableRuntimeMismatch) }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .dotnetFailed)
    }

    @Test func `a newer stable SDK can target net10`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { exe, args, env in
            if args == ["--list-sdks"] {
                return "11.0.100 [/sdk]"
            }
            if args == ["--version"] {
                return "11.0.100"
            }
            return try Self.runner(exe, arguments: args, env)
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .ready)
    }

    @Test func `UTF8 BOM and continued source lists match the managed reader`() throws {
        let f = try Fixture()
        defer { f.remove() }
        try "\u{feff}Language: C#\nSourceFiles: a.cs,\n b.cs // comment\n".write(to: f.root.appending(path: "dnproxy.ini"), atomically: true, encoding: .utf8)
        #expect(DNProxyPreflight(environment: f.environment, runner: Self.runner).inspect(directoryURL: f.root, moduleURL: f.module).status == .ready)
    }

    @Test func `rediagnosis observes an SDK installed after the first check`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let flag = f.root.appending(path: "sdk-installed")
        let probe = DNProxyPreflight(environment: f.environment) { exe, args, env in
            if args == ["--list-sdks"], !FileManager.default.fileExists(atPath: flag.path) {
                return ""
            }
            return try Self.runner(exe, arguments: args, env)
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .missingSDK)
        try Data().write(to: flag)
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .ready)
    }

    @Test func `an installed SDK is insufficient when global selection chooses an older one`() throws {
        let f = try Fixture()
        defer { f.remove() }
        let probe = DNProxyPreflight(environment: f.environment) { exe, args, env in
            args == ["--version"] ? "9.0.100" : try Self.runner(exe, arguments: args, env)
        }
        #expect(probe.inspect(directoryURL: f.root, moduleURL: f.module).status == .sdkSelectionFailed)
    }

    @Test func `real command runner handles large output without pipe deadlock`() throws {
        let f = try Fixture()
        defer { f.remove() }
        try "#!/bin/sh\nwhile :; do printf '0123456789012345678901234567890123456789'; done\n".write(to: f.dotnet, atomically: false, encoding: .utf8)
        #expect(throws: (any Error).self) { try DNProxyPreflight.run(f.dotnet, [], [:]) }
    }

    @Test func `real command runner bounds a silent executable`() throws {
        let f = try Fixture()
        defer { f.remove() }
        try "#!/bin/sh\nexec /bin/sleep 60\n".write(to: f.dotnet, atomically: false, encoding: .utf8)
        #expect(throws: NativeShioriProcessError.self) { try DNProxyPreflight.run(f.dotnet, [], [:]) }
    }
}

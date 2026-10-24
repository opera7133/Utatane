import Foundation
import Testing
import UtataneModuleHost
import UtataneNativeSaori
@testable import UtatanePlugin

/// Synthetic plugin dictionary, real YAYA and conventional SAORI/PLUGIN ABIs.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_HTTPC_LIBRARY"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_HTTPC_URL"] != nil))
struct HttpcPluginIntegrationTests {
    @Test(arguments: ["yaya", "yaya-6"], ["arm64", "x86_64"])
    func `httpc completion returns through its owning plugin runtime`(_ kind: String, _ architecture: String) async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = FileManager.default.temporaryDirectory.appending(path: "plugin-httpc-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try URL(filePath: #require(environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"])).appending(path: "lib\(kind).dylib")
        let httpc = try URL(filePath: #require(environment["UTATANE_HTTPC_LIBRARY"]))
        let url = try #require(environment["UTATANE_HTTPC_URL"])
        try FileManager.default.copyItem(at: httpc, to: root.appending(path: "libhttpc.dylib"))
        try "charset, UTF-8\ndic, plugin.dic\n".write(to: root.appending(path: "yaya.txt"), atomically: true, encoding: .utf8)
        let dictionary = #"""
        request
        {
            _value = "accepted"
            if STRSTR(_argv[0], "ID: OnHttpcNotify", 0) >= 0 {
                if STRSTR(_argv[0], "Reference0: plugin-owner", 0) >= 0 && STRSTR(_argv[0], "Reference2: bg-日本語next", 0) >= 0 {
                    _value = "delivered"
                }
            }
            else {
                _loaded = LOADLIB("httpc.dll")
                _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: bg%(CHR(13))%(CHR(10))Argument1: plugin-owner%(CHR(13))%(CHR(10))Argument2: URL_PLACEHOLDER%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                _result = REQUESTLIB("httpc.dll", _wire)
            }
            "PLUGIN/2.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Script: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
        }
        """#
        try dictionary.replacingOccurrences(of: "URL_PLACEHOLDER", with: url).write(to: root.appending(path: "plugin.dic"), atomically: true, encoding: .utf8)
        let repository = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardizedFileURL
        let helper = root.appending(path: "host")
        let compiler = Process()
        compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", architecture, repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", helper.path]
        try compiler.run(); compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0)
        let plugin = InstalledPlugin(id: "httpc-probe", name: "httpc probe", directory: root, moduleURL: library, charset: "UTF-8",
                                     author: nil, authorURL: nil, homeURL: nil, readmeURL: nil, readmeCharset: nil,
                                     secondChangeInterval: 0, observesOtherGhostTalk: false, runtime: .dynamicLibrary(library))
        let events = PluginHttpcEvents(), runtime = PluginRuntime()
        let failures = await runtime.reload([plugin]) { plugin in
            try DynamicLibraryPluginTransport(plugin: plugin, onInternalSaoriEvent: events.receive, hostURL: helper)
        }
        #expect(failures.isEmpty)
        #expect(try await runtime.request(pluginIDOrName: plugin.id, event: "OnProbe")?.script == "accepted")
        let completion = try #require(await events.wait())
        #expect(completion.isCurrent)
        #expect(try await runtime.request(pluginIDOrName: plugin.id, event: completion.id, references: completion.references)?.script == "delivered")
        await runtime.unloadAll()
        #expect(!completion.isCurrent)
    }
}

private final class PluginHttpcEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var event: InternalSaoriEvent?
    private var waiter: CheckedContinuation<InternalSaoriEvent?, Never>?
    func receive(_ event: InternalSaoriEvent) {
        lock.withLock { self.event = event; waiter?.resume(returning: event); waiter = nil }
    }

    func wait() async -> InternalSaoriEvent? {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if let event {
                    continuation.resume(returning: event)
                } else {
                    waiter = continuation
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [self] in
                lock.withLock { waiter?.resume(returning: nil); waiter = nil }
            }
        }
    }
}

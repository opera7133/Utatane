import Foundation
import Testing
import UtataneCore
import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

/// Opt in with a freshly built universal httpc and a deterministic loopback URL.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_HTTPC_LIBRARY"] != nil && ProcessInfo.processInfo.environment["UTATANE_HTTPC_URL"] != nil))
struct HttpcBackgroundIntegrationTests {
    @Test(arguments: ["arm64", "x86_64"])
    func `conventional httpc returns immediately and notifies its owning host`(_ architecture: String) async throws {
        let environment = ProcessInfo.processInfo.environment
        let library = try URL(filePath: #require(environment["UTATANE_HTTPC_LIBRARY"]))
        let url = try #require(environment["UTATANE_HTTPC_URL"])
        let root = FileManager.default.temporaryDirectory.appending(path: "httpc-日本語-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appending(path: "host")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardizedFileURL
        let compiler = Process()
        compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", architecture, repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", helper.path]
        try compiler.run(); compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0)
        let events = HttpcEventBox()
        let session = try NativeShioriProcessSession(directoryURL: root, moduleURL: library, hostURL: helper, onInternalSaoriEvent: events.receive)
        defer { try? session.close() }
        func send(_ id: String, _ arguments: [String]) throws -> String {
            let all = ["bg", id, url] + arguments
            let wire = (["EXECUTE SAORI/1.0", "Charset: UTF-8"] + all.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
            return try session.request(wire)
        }
        #expect(try send("text", []).hasPrefix("SAORI/1.0 204"))
        #expect(try send("saved", ["保存.bin"]).hasPrefix("SAORI/1.0 204"))
        let results = await events.wait(count: 2)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.id == "OnHttpcNotify" && $0.references[1] == "-" && $0.isCurrent })
        #expect(results.first { $0.references[0] == "text" }?.references[2] == "bg-日本語next")
        #expect(results.first { $0.references[0] == "saved" }?.references[2] == "1")
        #expect(try Data(contentsOf: root.appending(path: "保存.bin")) == Data("bg-日本語\r\nnext".utf8))
        try session.close()
        #expect(results.allSatisfy { !$0.isCurrent })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"] != nil),
          arguments: ["yaya", "yaya-6", "satori", "kawari"], ["arm64", "x86_64"])
    func `real SHIORI loaders use conventional httpc and consume its completion`(_ kind: String, _ architecture: String) async throws {
        let environment = ProcessInfo.processInfo.environment
        let libraries = try URL(filePath: #require(environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"]))
        let httpc = try URL(filePath: #require(environment["UTATANE_HTTPC_LIBRARY"]))
        let url = try #require(environment["UTATANE_HTTPC_URL"])
        let root = FileManager.default.temporaryDirectory.appending(path: "httpc-dictionary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: httpc, to: root.appending(path: "libhttpc.dylib"))
        if kind.hasPrefix("yaya") {
            try "charset, UTF-8\ndic, probe.dic\n".write(to: root.appending(path: "yaya.txt"), atomically: true, encoding: .utf8)
            let dictionary = #"""
            request
            {
                _value = "accepted"
                if STRSTR(_argv[0], "ID: OnHttpcNotify", 0) >= 0 {
                    _value = "delivered"
                }
                else {
                    _loaded = LOADLIB("httpc.dll")
                    _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: bg%(CHR(13))%(CHR(10))Argument1: dictionary%(CHR(13))%(CHR(10))Argument2: URL_PLACEHOLDER%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                    _result = REQUESTLIB("httpc.dll", _wire)
                }
                "SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Value: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
            }
            """#
            try dictionary.replacingOccurrences(of: "URL_PLACEHOLDER", with: url).write(to: root.appending(path: "probe.dic"), atomically: true, encoding: .utf8)
        } else if kind == "satori" {
            try "＠SAORI\r\n通信,httpc.dll,bg,dictionary\r\n".write(to: root.appending(path: "satori_conf.txt"), atomically: true, encoding: .utf8)
            try "＊OnProbe\r\n：（通信、\(url)）。\r\n＊OnHttpcNotify\r\n：delivered。\r\n".write(to: root.appending(path: "dic00.txt"), atomically: true, encoding: .utf8)
        } else {
            try "System.Callback.OnGET : $(entry ${System.Request.ID};)\nOnProbe : probe$(saoriregist httpc.dll httpc)$(callsaori httpc bg dictionary \"\(url)\")\nOnHttpcNotify : delivered\n".write(to: root.appending(path: "kawarirc.kis"), atomically: true, encoding: .utf8)
        }
        let repository = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardizedFileURL
        let helper = root.appending(path: "host")
        let compiler = Process()
        compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", architecture, repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", helper.path]
        try compiler.run(); compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0)
        let events = HttpcEventBox()
        let traceStore = AppLogStore(), trace = SaoriDiagnostics(store: traceStore)
        trace.isEnabled = true
        let session = try NativeShioriSession(directoryURL: root, moduleURL: libraries.appending(path: "lib\(kind).dylib"), saoriDiagnostics: trace, onInternalSaoriEvent: events.receive, hostURL: helper)
        defer { try? session.close() }
        let initial = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnProbe\r\nSecurityLevel: Local\r\n\r\n")
        let completion = try #require(await events.wait(count: 1).first, "Initial response: \(initial)")
        #expect(completion.references == [0: "dictionary", 1: "-", 2: "bg-日本語next"])
        #expect(completion.isCurrent)
        #expect(traceStore.snapshot().contains { $0.message.contains("phase=load") && $0.message.contains("libhttpc.dylib") })
        #expect(traceStore.snapshot().contains { $0.message.contains("phase=call backend=dylib status=204") })
        #expect(traceStore.snapshot().allSatisfy { !$0.message.contains("Argument1:") && !$0.message.contains("bg-日本語") })
        let response = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnHttpcNotify\r\nReference0: dictionary\r\nReference1: -\r\nReference2: bg-日本語next\r\n\r\n")
        #expect(try ShioriMessageParser.parseResponse(response).value?.contains("delivered") == true)
        try session.close()
        #expect(!completion.isCurrent)
    }
}

private final class HttpcEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [InternalSaoriEvent] = []
    private var waiter: (Int, CheckedContinuation<[InternalSaoriEvent], Never>)?
    func receive(_ value: InternalSaoriEvent) {
        lock.withLock {
            values.append(value)
            if let (count, continuation) = waiter, values.count >= count {
                waiter = nil; continuation.resume(returning: values)
            }
        }
    }

    func wait(count: Int) async -> [InternalSaoriEvent] {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if values.count >= count {
                    continuation.resume(returning: values)
                } else {
                    waiter = (count, continuation)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [self] in
                lock.withLock {
                    if let (_, continuation) = waiter {
                        waiter = nil; continuation.resume(returning: values)
                    }
                }
            }
        }
    }
}

import Foundation
import Testing
import UtataneCore
import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

final class InternalSaoriCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var event: InternalSaoriEvent?
    private var waiter: CheckedContinuation<InternalSaoriEvent?, Never>?

    func receive(_ value: InternalSaoriEvent) {
        lock.withLock {
            event = value
            let continuation = waiter
            waiter = nil
            continuation?.resume(returning: value)
        }
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
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [self] in
                lock.withLock {
                    let continuation = waiter
                    waiter = nil
                    continuation?.resume(returning: nil)
                }
            }
        }
    }
}

private struct IntegrationMediaReader: InternalSaoriMediaReading {
    func read(_ url: URL) throws -> InternalSaoriMediaInfo {
        .init(kind: "audio", values: ["title": "metadata"])
    }
}

/// Opt in with local, rebuilt modules. Never installs them into a user's catalog.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"] != nil))
struct InternalSaoriIntegrationTests {
    @Test(arguments: ["yaya", "yaya-6", "satori", "kawari"], ["arm64", "x86_64"])
    func `real SHIORI dictionaries call the owning baseware without a SAORI DLL`(_ kind: String, _ architecture: String) async throws {
        let modules = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"]))
        let root = FileManager.default.temporaryDirectory.appending(path: "internal-saori-\(kind)-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let helper = root.appending(path: "host")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardizedFileURL
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", architecture, repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", helper.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)

        if kind.hasPrefix("yaya") {
            try "charset, UTF-8\ndic, probe.dic\n".write(to: master.appending(path: "yaya.txt"), atomically: true, encoding: .utf8)
            try #"""
            request
            {
                _loaded = LOADLIB("internal_text.dll")
                _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: Normalize%(CHR(13))%(CHR(10))Argument1: NFKC%(CHR(13))%(CHR(10))Argument2: ｶﾞｲﾄﾞ%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                if STRSTR(_argv[0], "ID: OnAsync", 0) >= 0 {
                    _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: Normalize%(CHR(13))%(CHR(10))Argument1: NFKC%(CHR(13))%(CHR(10))Argument2: ｶﾞｲﾄﾞ%(CHR(13))%(CHR(10))Argument3: --async=OnNormalized%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                }
                _response = REQUESTLIB("internal_text.dll", _wire)
                _value = "failed"
                if STRSTR(_response, "Result: ガイド", 0) >= 0 { _value = "ガイド" }
                if STRSTR(_argv[0], "ID: OnData", 0) >= 0 {
                    _loaded = LOADLIB("internal_data.dll")
                    _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: Decompress%(CHR(13))%(CHR(10))Argument1: gzip%(CHR(13))%(CHR(10))Argument2: H4sIAAAAAAAACvNIzcnJBwCCidH3BQAAAA==%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                    _response = REQUESTLIB("internal_data.dll", _wire)
                    if STRSTR(_response, "Result: Hello", 0) >= 0 { _value = "Hello" }
                    _unloaded = UNLOADLIB("internal_data.dll")
                }
                if STRSTR(_argv[0], "ID: OnMedia", 0) >= 0 {
                    _loaded = LOADLIB("internal_file.dll")
                    _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: MediaInfo%(CHR(13))%(CHR(10))Argument1: probe.bin%(CHR(13))%(CHR(10))Argument2: title%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                    _response = REQUESTLIB("internal_file.dll", _wire)
                    if STRSTR(_response, "Value0: metadata", 0) >= 0 { _value = "audio" }
                    _unloaded = UNLOADLIB("internal_file.dll")
                }
                if STRSTR(_argv[0], "ID: OnHash", 0) >= 0 {
                    _loaded = LOADLIB("internal_crypto.dll")
                    _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: Digest%(CHR(13))%(CHR(10))Argument1: sha256%(CHR(13))%(CHR(10))Argument2: probe.bin%(CHR(13))%(CHR(10))Argument3: --data-in=file%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                    _response = REQUESTLIB("internal_crypto.dll", _wire)
                    if STRSTR(_response, "Result: 6e340b9c", 0) >= 0 { _value = "6e340b9c" }
                    _unloaded = UNLOADLIB("internal_crypto.dll")
                }
                _unloaded = UNLOADLIB("internal_text.dll")
                "SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Value: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
            }
            """#.write(to: master.appending(path: "probe.dic"), atomically: true, encoding: .utf8)
        } else if kind == "satori" {
            try "＠SAORI\r\n正規化,internal_text.dll,Normalize,NFKC\r\n".write(to: master.appending(path: "satori_conf.txt"), atomically: true, encoding: .utf8)
            try "＊OnHash\r\n：（internal_crypto、Digest、sha256、probe.bin、--data-in=file）。\r\n＊OnData\r\n：（internal_data、Decompress、gzip、H4sIAAAAAAAACvNIzcnJBwCCidH3BQAAAA==）。\r\n＊OnMedia\r\n：（internal_file、MediaInfo、probe.bin、title）。\r\n＊OnBoot\r\n：（正規化、ｶﾞｲﾄﾞ）。\r\n＊OnAuto\r\n：（internal_text、Normalize、NFKC、ｶﾞｲﾄﾞ）。\r\n＊OnAsync\r\n：（internal_text、Normalize、NFKC、ｶﾞｲﾄﾞ、--async=OnNormalized）。\r\n".write(to: master.appending(path: "dic00.txt"), atomically: true, encoding: .utf8)
        } else {
            let dictionary = "OnHash : $(callsaori internal_crypto Digest sha256 probe.bin --data-in=file)\nOnData : $(callsaori internal_data Decompress gzip H4sIAAAAAAAACvNIzcnJBwCCidH3BQAAAA==)\nOnMedia : $(callsaori internal_file MediaInfo probe.bin title)\nSystem.Callback.OnGET : $(entry ${System.Request.ID};)\nOnBoot : $(callsaori internal_text Normalize NFKC ｶﾞｲﾄﾞ)\nOnAsync : $(callsaori internal_text Normalize NFKC ｶﾞｲﾄﾞ --async=OnNormalized)\n"
            try #require(LegacyTextDecoder.encode(dictionary, charset: "Shift_JIS")).write(to: master.appending(path: "kawarirc.kis"))
        }
        try Data([0]).write(to: master.appending(path: "probe.bin"))
        let library = modules.appending(path: "lib\(kind).dylib")
        let box = InternalSaoriCompletionBox()
        let session = try NativeShioriSession(directoryURL: master, moduleURL: library, onInternalSaoriEvent: box.receive, internalSaoriMediaReader: IntegrationMediaReader(), hostURL: helper)
        if kind == "kawari" {
            _ = try session.request("NOTIFY SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: Local\r\nID: hwnd\r\nReference0: 1\r\n\r\n")
        }
        let wire = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: Local\r\nID: OnBoot\r\n\r\n")
        let response = try ShioriMessageParser.parseResponse(wire)
        #expect(response.value?.contains("ガイド") == true, "\(wire)")
        if kind == "satori" {
            let response = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: Local\r\nID: OnAuto\r\n\r\n")
            #expect(try ShioriMessageParser.parseResponse(response).value?.contains("ガイド") == true)
        }
        for (eventID, expected) in [("OnData", "Hello"), ("OnMedia", "audio"), ("OnHash", "6e340b9c")] {
            let result = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: Local\r\nID: \(eventID)\r\n\r\n")
            #expect(try ShioriMessageParser.parseResponse(result).value?.contains(expected) == true, "\(kind) \(architecture): \(result)")
        }
        _ = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: Local\r\nID: OnAsync\r\n\r\n")
        let completion = try #require(await box.wait())
        #expect(completion.id == "OnNormalized")
        #expect(completion.references[1] == "ガイド")
        #expect(completion.isCurrent)
        try session.close()
        #expect(!completion.isCurrent)
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "internal_text.dll").path))
    }
}

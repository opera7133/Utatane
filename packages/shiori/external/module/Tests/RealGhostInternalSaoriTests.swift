import Foundation
import Testing
import UtataneCore
import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

/// Reads locally installed ghosts only; all probes and saves live in disposable copies.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_REAL_SAORI_GHOST_ROOT"] != nil && ProcessInfo.processInfo.environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"] != nil))
struct RealGhostInternalSaoriTests {
    @Test(arguments: ["yaya", "yaya-6", "satori", "kawari"], ["arm64", "x86_64"])
    func `installed ghost frameworks use internal time and consume asynchronous results`(_ kind: String, _ architecture: String) async throws {
        let environment = ProcessInfo.processInfo.environment
        let ghosts = try URL(fileURLWithPath: #require(environment["UTATANE_REAL_SAORI_GHOST_ROOT"]))
        let libraries = try URL(fileURLWithPath: #require(environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"]))
        let names = ["yaya": "ria", "yaya-6": "ria", "satori": "momochi", "kawari": "CLDSP2+"]
        let source = try ghosts.appending(path: #require(names[kind]) + "/ghost/master")
        let originalConfig = source.appending(path: kind.hasPrefix("yaya") ? "yaya.txt" : kind == "satori" ? "satori_conf.txt" : "kawarirc.kis")
        let original = try Data(contentsOf: originalConfig)
        let root = FileManager.default.temporaryDirectory.appending(path: "real-saori-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)
        if kind.hasPrefix("yaya") {
            let probe = #"""
            OnUtatanePlainProbe { "utatane-probe" }
            OnUtataneInternalProbe
            {
                FUNCTIONEX('internal_time', 'Format', '0', '', '--tz=UTC')
            }
            OnUtataneAsyncProbe
            {
                FUNCTIONEX('internal_time', 'Add', '2024-01-31T12:00Z', '1', 'month', '--tz=UTC', '--async=OnUtataneProbeDone')
            }
            OnUtataneProbeDone
            {
                reference[1]
            }
            """#
            try probe.write(to: master.appending(path: "utatane-probe.dic"), atomically: true, encoding: .utf8)
            let handle = try FileHandle(forWritingTo: master.appending(path: "yaya.txt"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\ndic, utatane-probe.dic, UTF-8\n".utf8))
            try handle.close()
        } else if kind == "satori" {
            let probe = "＊OnUtataneInternalProbe\r\n：（internal_time、Format、0、、--tz=UTC）。\r\n＊OnUtataneAsyncProbe\r\n：（internal_time、Add、2024-01-31T12:00Z、1、month、--tz=UTC、--async=OnUtataneProbeDone）。\r\n＊OnUtataneProbeDone\r\n：（Ｒ１）。\r\n"
            try #require(LegacyTextDecoder.encode(probe, charset: "Shift_JIS")).write(to: master.appending(path: "dic_utatane_probe.txt"))
        } else {
            let probe = "\nOnUtataneInternalProbe : $(callsaori internal_time Format 0 \"\" --tz=UTC)\nOnUtataneAsyncProbe : $(callsaori internal_time Add 2024-01-31T12:00Z 1 month --tz=UTC --async=OnUtataneProbeDone)\nOnUtataneProbeDone : ${System.Request.Reference1}\n"
            let handle = try FileHandle(forWritingTo: master.appending(path: "kawarirc.kis"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(probe.utf8))
            try handle.close()
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardizedFileURL
        let host = root.appending(path: "host")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", architecture, repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", host.path]
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        let box = InternalSaoriCompletionBox()
        let session = try NativeShioriSession(directoryURL: master, moduleURL: libraries.appending(path: "lib\(kind).dylib"), onInternalSaoriEvent: box.receive, hostURL: host)
        defer { try? session.close() }
        func request(_ id: String, reference: String? = nil) throws -> String {
            let header = reference.map { "Reference0: OnUtataneProbeDone\r\nReference1: \($0)\r\n" } ?? ""
            let wire = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: Local\r\nID: \(id)\r\n\(header)\r\n")
            return try ShioriMessageParser.parseResponse(wire).value ?? ""
        }
        _ = try session.request("NOTIFY SHIORI/3.0\r\nCharset: UTF-8\r\nID: hwnd\r\nReference0: 1\r\n\r\n")
        if kind.hasPrefix("yaya") {
            let plain = try request("OnUtatanePlainProbe")
            #expect(plain.contains("utatane-probe"), "plain response: \(plain)")
        }
        let synchronous = try request("OnUtataneInternalProbe")
        #expect(synchronous.contains("1970-01-01T00:00:00Z"), "probe response: \(synchronous)")
        _ = try request("OnUtataneAsyncProbe")
        let completion = try #require(await box.wait())
        #expect(completion.id == "OnUtataneProbeDone")
        #expect(completion.references[1] == "1709208000")
        #expect(try request(completion.id, reference: completion.references[1]).contains("1709208000"))
        try session.close()
        #expect(!completion.isCurrent)
        #expect(try Data(contentsOf: originalConfig) == original)
    }
}

import Foundation
import Testing
import UtataneShiori
@testable import UtataneYayaNative

/// Opt-in probe of the author's AYA 5.8 template. Never changes the supplied master.
struct Aya5CompatibilityTests {
    @Test(arguments: ["standard", "legacy", "error", "yaya"])
    func `talk fallback is limited to empty AYA responses`(mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-aya-talk-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "dic, probe.dic\n".write(to: directory.appending(path: "aya5.txt"), atomically: true, encoding: .utf8)
        if mode == "yaya" {
            try "dic, probe.dic\n".write(to: directory.appending(path: "yaya.txt"), atomically: true, encoding: .utf8)
        }
        let status = mode == "error" ? 500 : (mode == "standard" ? 200 : 204)
        let value = mode == "standard" ? "standard" : ""
        let dictionary = """
        request
        {
            if STRSTR(_argv[0], "ID: OnAITalk", 0) >= 0 {
                "SHIORI/3.0 \(status) Result%(CHR(13))%(CHR(10))Value: \(value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
            } else {
                "SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Value: legacy%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
            }
        }
        """
        try dictionary.write(to: directory.appending(path: "probe.dic"), atomically: true, encoding: .utf8)
        let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: directory)
        if mode == "error" {
            await #expect(throws: NativeYayaPersonalityError.self) { try await engine.handle(event: .randomTalk) }
        } else {
            let expected: String? = mode == "yaya" ? nil : (mode == "standard" ? "standard" : "legacy")
            #expect(try await engine.handle(event: .randomTalk)?.rawValue == expected)
        }
    }

    @Test(arguments: ["aya5", "aya", "yaya"])
    func `module name preserves variable file across reload`(module: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-aya-state-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "dic, probe.dic\n".write(to: directory.appending(path: "\(module).txt"), atomically: true, encoding: .utf8)
        let dictionary = #"""
        request
        {
            probe_count++
            "SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Value: %(probe_count)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
        }
        """#
        try dictionary.write(to: directory.appending(path: "probe.dic"), atomically: true, encoding: .utf8)
        #expect(NativeYayaPersonalityEngine.supports(masterDirectoryURL: directory))
        func query() throws -> String? {
            let session = try NativeYayaSession(masterDirectoryURL: directory)
            return try ShioriMessageParser.parseResponse(session.request("GET SHIORI/3.0\r\nID: OnTest\r\n\r\n")).value
        }
        #expect(try query() == "1")
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "\(module)_variable.cfg").path))
        #expect(try query() == "2")
        if module != "yaya" {
            #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "yaya_variable.cfg").path))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_AYA5_MASTER"] != nil))
    func `AYA5 template dictionaries execute directly in YAYA`() async throws {
        let source = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_AYA5_MASTER"]))
        let copy = FileManager.default.temporaryDirectory.appending(path: "utatane-aya5-probe-\(UUID())")
        try FileManager.default.copyItem(at: source, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        #expect(NativeYayaPersonalityEngine.supports(masterDirectoryURL: copy))
        let session = try NativeYayaSession(masterDirectoryURL: copy)
        for event in ["OnFirstBoot", "OnBoot", "OnAiTalk", "OnMouseDoubleClick", "OnClose"] {
            let raw = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Utatane\r\nSecurityLevel: local\r\nID: \(event)\r\nReference0: 0\r\nReference1: 0\r\nReference2: 0\r\nReference3: 0\r\nReference4: Head\r\n\r\n")
            let response = try ShioriMessageParser.parseResponse(raw)
            #expect(response.statusCode == 200, "\(event): \(response.statusCode)")
            #expect(response.value?.isEmpty == false, "\(event) has no script")
        }
        let unmapped = try ShioriMessageParser.parseResponse(session.request(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnAITalk\r\n\r\n"
        ))
        #expect(unmapped.statusCode == 204)
        let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: copy)
        #expect(try await engine.handle(event: .randomTalk)?.rawValue.isEmpty == false)
        #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "yaya.txt").path))
    }
}

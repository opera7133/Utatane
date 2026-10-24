import Foundation
import Testing
import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_SHARED_SAORI_TEST_ROOT"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"] != nil))
struct SharedSaoriIntegrationTests {
    @Test(arguments: ["yaya", "yaya-6", "satori", "kawari"], ["arm64", "x86_64"])
    func `shared SAORI catalog IDs and original ip DLL alias resolve through actual SHIORIs`(_ kind: String, _ architecture: String) throws {
        let environment = ProcessInfo.processInfo.environment
        let libraries = try URL(filePath: #require(environment["UTATANE_INTERNAL_SAORI_TEST_ROOT"]))
        let catalog = try #require(environment["UTATANE_SHARED_SAORI_TEST_ROOT"])
        let root = FileManager.default.temporaryDirectory.appending(path: "shared-saori-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if kind.hasPrefix("yaya") {
            try "charset, UTF-8\ndic, probe.dic\n".write(to: root.appending(path: "yaya.txt"), atomically: true, encoding: .utf8)
            try #"""
            request
            {
                _loaded = LOADLIB("ip.dll")
                _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: GetLocalHostname%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
                _result = REQUESTLIB("ip.dll", _wire)
                _value = "failed"
                if STRSTR(_result, "SAORI/1.0 200", 0) >= 0 { _value = "resolved" }
                "SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Value: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
            }
            """#.write(to: root.appending(path: "probe.dic"), atomically: true, encoding: .utf8)
        } else if kind == "satori" {
            try "＠SAORI\r\nIP,ip.dll\r\n".write(to: root.appending(path: "satori_conf.txt"), atomically: true, encoding: .utf8)
            try "＊OnProbe\r\n：（IP、GetLocalHostname）。\r\n".write(to: root.appending(path: "dic00.txt"), atomically: true, encoding: .utf8)
        } else {
            try "System.Callback.OnGET : $(entry ${System.Request.ID};)\nOnProbe : $(saoriregist ip.dll ip)$(callsaori ip GetLocalHostname)\n".write(to: root.appending(path: "kawarirc.kis"), atomically: true, encoding: .utf8)
        }
        let repository = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardizedFileURL
        let helper = root.appending(path: "host"), compiler = Process()
        compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", architecture, repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", helper.path]
        try compiler.run(); compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0)
        let session = try NativeShioriProcessSession(directoryURL: root, moduleURL: libraries.appending(path: "lib\(kind).dylib"), hostURL: helper, additionalEnvironment: ["UTATANE_SAORI_ROOT": catalog])
        defer { try? session.close() }
        let response = try ShioriMessageParser.parseResponse(session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnProbe\r\nSecurityLevel: Local\r\n\r\n"))
        let value = try #require(response.value)
        if kind.hasPrefix("yaya") {
            #expect(value == "resolved")
        } else {
            #expect(value.localizedCaseInsensitiveContains(ProcessInfo.processInfo.hostName))
        }
    }
}

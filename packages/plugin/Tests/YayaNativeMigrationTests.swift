import Foundation
import Testing
import UtataneModuleHost

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_YAYA5_MODULE"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_YAYA6_MODULE"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
struct YayaNativeMigrationTests {
    @Test func `YAYA five save loads in six while preserving the original backup`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "YAYA migration \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "charset, UTF-8\ndic, probe.dic\n".write(to: root.appending(path: "yaya.txt"), atomically: true, encoding: .utf8)
        try #"""
        request
        {
            probe_count++
            "SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Value: count=%(probe_count)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
        }
        """#.write(to: root.appending(path: "probe.dic"), atomically: true, encoding: .utf8)
        let environment = ProcessInfo.processInfo.environment
        let five = try URL(fileURLWithPath: #require(environment["UTATANE_YAYA5_MODULE"]))
        let six = try URL(fileURLWithPath: #require(environment["UTATANE_YAYA6_MODULE"]))
        let host = try URL(fileURLWithPath: #require(environment["UTATANE_NATIVE_SHIORI_HOST"]))
        let request = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        let original = try NativeShioriSession(directoryURL: root, moduleURL: five, hostURL: host)
        #expect(try original.request(request).contains("count=1"))
        try original.close()
        let saved = try Data(contentsOf: root.appending(path: "yaya_variable.cfg"))
        for count in [2, 3] {
            let upgraded = try NativeShioriSession(directoryURL: root, moduleURL: six, hostURL: host)
            #expect(try upgraded.request(request).contains("count=\(count)"))
            try upgraded.close()
            #expect(try Data(contentsOf: root.appending(path: "Utatane-YAYA-backup/yaya_variable.cfg")) == saved)
        }
    }
}

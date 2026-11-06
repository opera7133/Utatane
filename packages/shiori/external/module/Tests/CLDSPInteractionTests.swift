import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_GHOST"] != nil))
func `local CLDSP EQ switches respond to native mouse events`() throws {
    let environment = ProcessInfo.processInfo.environment
    let source = try URL(fileURLWithPath: #require(environment["UTATANE_CLDSP_GHOST"]))
    let library = try URL(fileURLWithPath: #require(environment["UTATANE_CLDSP_MODULE"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "CLDSP-interaction-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: source, to: root)
    let master = root.appending(path: "ghost/master")
    let config = master.appending(path: "kawarirc.kis")
    let original = try Data(contentsOf: config)
    let handle = try FileHandle(forWritingTo: config)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\nOnUtataneEQState : ${eq_enabled}|${mode_eq}|${eq_bank}\nOnUtataneSpectrumPrepare : $(set playing 1;set fullmode_sw 1;set spectrum_mode 1;set mode_eq 0;set surface.1 9;)\n".utf8))
    try handle.close()
    let session = try NativeShioriSession(directoryURL: master, moduleURL: library, moduleResolver: .init(allowsFallback: false))
    defer { try? session.close() }
    func request(_ id: String, _ references: [Int: String] = [:]) throws -> String {
        let fields = references.sorted { $0.key < $1.key }.map { "Reference\($0.key): \($0.value)\r\n" }.joined()
        return try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: \(id)\r\n\(fields)\r\n")
    }
    _ = try request("OnBoot")
    let before = try request("OnUtataneEQState")
    let click = try request("OnMouseDown", [0: "95", 1: "176", 2: "0", 3: "1", 4: "mode_eq_on", 5: "0"])
    let after = try request("OnUtataneEQState")
    #expect(try ShioriMessageParser.parseResponse(click).statusCode == 200)
    #expect(before != after)
    _ = try request("OnMouseDown", [0: "113", 1: "180", 2: "0", 3: "1", 4: "mode_eq_bank0", 5: "0"])
    #expect(try request("OnUtataneEQState").contains("|1|0"))
    _ = try request("OnUtataneSpectrumPrepare")
    let levels = Array(repeating: "80", count: 31).joined(separator: "\u{1}")
    var elapsed = 0.0
    for index in 0 ..< 10 {
        let began = Date()
        let result = try request("OnSoundSpectrum", [0: "cldsp2.mp3", 1: "31", 2: "80\u{1}80", 3: "80\u{1}80", 4: levels, 5: levels, 6: String(index * 100)])
        elapsed += Date().timeIntervalSince(began)
        if index == 0 {
            let script = try ShioriMessageParser.parseResponse(result).value ?? ""
            try script.write(to: URL(fileURLWithPath: "/private/tmp/utatane-cldsp-spectrum-script.txt"), atomically: true, encoding: .utf8)
            print("CLDSP spectrum script bytes", script.utf8.count)
        }
    }
    print("CLDSP spectrum average SHIORI seconds", elapsed / 10)
    #expect(try Data(contentsOf: source.appending(path: "ghost/master/kawarirc.kis")) == original)
}

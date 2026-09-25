import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_HISUI_MODULE"] != nil))
struct HisuiNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `hisui loads from catalog and saves state outside the ghost`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hisui \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "hisui/lib/libhisui.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_HISUI_MODULE"])),
            to: module
        )
        let master = root.appending(path: "ghost/master")
        let dictionary = master.appending(path: "hisui_base")
        try FileManager.default.createDirectory(at: dictionary, withIntermediateDirectories: true)
        try "sakura.name,翡翠\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        try "{\ntoken:OnBoot\nscript:\\0boot\\e\n}\n".write(
            to: dictionary.appending(path: "boot.tlk"), atomically: true, encoding: .utf8
        )
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.moduleURL(for: .hisui, masterDirectoryURL: master) == module)
        let state = root.appending(path: "state/hisui-state.json")
        let session = try NativeShioriSession(directoryURL: master, moduleURL: module,
                                              moduleResolver: resolver, hisuiStateStoreURL: state)
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(response.value == "\\0boot\\e")
        try await session.closeAsync()
        #expect(FileManager.default.fileExists(atPath: state.path))
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "hisui-state.json").path))
    }
}

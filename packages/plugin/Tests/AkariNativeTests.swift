import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_AKARI_MODULE"] != nil))
struct AkariNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `akari loads from catalog and saves variables outside the ghost`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "akari \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "akari/lib/libakari.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_AKARI_MODULE"])),
            to: module
        )
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try "shiori,akari.dll\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        try "＊OnBoot\n・（０）こんにちは。\n".write(
            to: master.appending(path: "akari.txt"), atomically: true, encoding: .utf8
        )
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.moduleURL(for: .akari, masterDirectoryURL: master) == module)
        let state = root.appending(path: "state/akari-vars.json")
        let session = try NativeShioriSession(directoryURL: master, moduleURL: module,
                                              moduleResolver: resolver, akariVariableStoreURL: state)
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(response.value?.contains("こんにちは") == true)
        try await session.closeAsync()
        #expect(FileManager.default.fileExists(atPath: state.path))
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "akari-vars.json").path))
    }
}

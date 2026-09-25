import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_KAWARI_MODULE"] != nil))
struct KawariNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `kawari loads from catalog and answers legacy ghost`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kawari \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "kawari/lib/libkawari.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_KAWARI_MODULE"])),
            to: module
        )
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try #require("dict : events.txt\r\n".data(using: .shiftJIS))
            .write(to: master.appending(path: "kawari.ini"))
        try #require("event.OnBoot : \\0起動\\e\r\n".data(using: .shiftJIS))
            .write(to: master.appending(path: "events.txt"))
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.moduleURL(for: .kawari, masterDirectoryURL: master) == module)
        let session = try NativeShioriSession(directoryURL: master, moduleURL: module, moduleResolver: resolver)
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(response.value?.contains("起動") == true)
        try await session.closeAsync()
    }
}

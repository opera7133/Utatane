import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_ESE_SHIORI_MODULE"] != nil))
struct EseShioriNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `ese shiori loads from catalog, keeps state outside the ghost, and recovers a broken bundled copy`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ese-shiori 複数 \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "ese-shiori/lib/libese-shiori.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_ESE_SHIORI_MODULE"])),
            to: module
        )
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try "[ESEAI]\nDIC_CHAR_SET=UTF-8\n".write(to: master.appending(path: "eseai.ini"),
                                                  atomically: true, encoding: .utf8)
        try "##EVNT=(\"OnBoot\")\n\\1\\s1起動\\e\n".write(to: master.appending(path: "eseai_boot.txt"),
                                                        atomically: true, encoding: .utf8)
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.moduleURL(for: .eseShiori, masterDirectoryURL: master) == module)
        let state = root.appending(path: "state/ese-shiori-state.json")
        let session = try NativeShioriSession(directoryURL: master, moduleURL: module,
                                              moduleResolver: resolver, eseStateStoreURL: state)
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(response.value == "\\1\\s[11]起動\\e")
        try await session.closeAsync()
        #expect(FileManager.default.fileExists(atPath: state.path))
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "ese-shiori-state.json").path))
        let broken = master.appending(path: "libese-shiori.dylib")
        try Data("broken".utf8).write(to: broken)
        #expect(try resolver.moduleURL(for: .eseShiori, masterDirectoryURL: master) == broken)
        let recovered = try NativeShioriSession(directoryURL: master, moduleURL: broken,
                                                moduleResolver: resolver, eseStateStoreURL: state)
        let recoveredResponse = try await ShioriMessageParser.parseResponse(recovered.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(recoveredResponse.value == "\\1\\s[11]起動\\e")
        try await recovered.closeAsync()
    }
}

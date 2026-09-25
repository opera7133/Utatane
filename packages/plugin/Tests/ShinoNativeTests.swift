import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_SHINO_MODULE"] != nil))
struct ShinoNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `shino loads from catalog and saves state outside the ghost`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shino \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "shino/lib/libshino.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_SHINO_MODULE"])),
            to: module
        )
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try "sakura.name,忍\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        try "\\ev[OnBoot],\\0boot\\e\n".write(
            to: master.appending(path: "ai_test.txt"), atomically: true, encoding: .utf8
        )
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.moduleURL(for: .shino, masterDirectoryURL: master) == module)
        let state = root.appending(path: "state/shino-state.json")
        let session = try NativeShioriSession(directoryURL: master, moduleURL: module,
                                              stateDirectoryURL: state.deletingLastPathComponent(), moduleResolver: resolver)
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(response.value == "\\0boot\\e")
        try await session.closeAsync()
        #expect(FileManager.default.fileExists(atPath: state.path))
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "shino-state.json").path))
    }
}

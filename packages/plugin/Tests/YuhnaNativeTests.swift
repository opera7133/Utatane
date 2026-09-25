import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_YUHNA_MODULE"] != nil))
struct YuhnaNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `yuhna loads from catalog and saves state outside the ghost`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "yuhna \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "yuhna/lib/libyuhna.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_YUHNA_MODULE"])),
            to: module
        )
        let master = root.appending(path: "ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        var data = Data("YDF/1.07 fixture".utf8)
        data.append(contentsOf: [0, 0, 0, 2])
        for (name, script) in [("OnYuhnaRandomTalk", "\\0talk\\e"), ("OnBoot", "\\0boot\\e")] {
            let nameBytes = Array(name.utf8)
            let scriptBytes = Array(script.utf8)
            data.append(contentsOf: [UInt8(nameBytes.count >> 8), UInt8(nameBytes.count & 0xFF)])
            data.append(contentsOf: nameBytes)
            data.append(contentsOf: [0, 0, 0, 0, 1])
            data.append(contentsOf: [UInt8(scriptBytes.count >> 8), UInt8(scriptBytes.count & 0xFF), 0])
            data.append(contentsOf: scriptBytes)
        }
        try data.write(to: master.appending(path: "dic.ydf"))
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.moduleURL(for: .yuhna, masterDirectoryURL: master) == module)
        let state = root.appending(path: "state/yuhna-state.json")
        let session = try NativeShioriSession(directoryURL: master, moduleURL: module,
                                              moduleResolver: resolver, yuhnaStateStoreURL: state)
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        ))
        #expect(response.value == "\\0boot\\e")
        try await session.closeAsync()
        #expect(FileManager.default.fileExists(atPath: state.path))
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "yuhna-state.json").path))
    }
}

import Foundation
import Testing
import UtataneModuleHost
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_NISE_SHIORI_MODULE"] != nil))
struct NiseShioriNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `managed niseshiori keeps ghost state separate and recovers a broken bundled copy`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "niseshiori 複数 \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "nise-shiori/lib/libniseshiori.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_NISE_SHIORI_MODULE"])),
            to: module
        )
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        var directories: [URL] = []
        for name in ["A", "B"] {
            let directory = root.appending(path: name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "#Charset: UTF-8\n\\ev,OnBoot,\\0起動\\set[count=1]\\e\n\\ev,OnMouseDoubleClick & %get[count]=1,\\0クリック\\e\n"
                .write(to: directory.appending(path: "ai.txt"), atomically: true, encoding: .utf8)
            directories.append(directory)
            #expect(try resolver.moduleURL(for: .niseshiori, masterDirectoryURL: directory) == module)
        }
        let request = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        let click = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnMouseDoubleClick\r\n\r\n"
        let stateA = root.appending(path: "state/A/nise-shiori-state.json")
        let stateB = root.appending(path: "state/B/nise-shiori-state.json")
        try FileManager.default.createDirectory(at: stateA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"username":"","variables":{"count":"1"},"learnedWords":{},"talkInterval":180,"newsIndex":0}"#
            .write(to: stateA, atomically: true, encoding: .utf8)
        let a = try NativeShioriSession(directoryURL: directories[0], moduleURL: module,
                                        moduleResolver: resolver, niseStateStoreURL: stateA)
        let b = try NativeShioriSession(directoryURL: directories[1], moduleURL: module,
                                        moduleResolver: resolver, niseStateStoreURL: stateB)
        #expect(try await ShioriMessageParser.parseResponse(a.requestAsync(click)).value == "\\0クリック\\e")
        #expect(try await ShioriMessageParser.parseResponse(a.requestAsync(request)).value == "\\0起動\\e")
        #expect(try await ShioriMessageParser.parseResponse(b.requestAsync(click)).statusCode == 204)
        try await a.closeAsync()
        try await b.closeAsync()
        #expect(FileManager.default.fileExists(atPath: stateA.path))
        #expect(FileManager.default.fileExists(atPath: stateB.path))
        #expect(!FileManager.default.fileExists(atPath: directories[0].appending(path: "nise-shiori-state.json").path))
        let bundled = directories[0].appending(path: "libniseshiori.dylib")
        try Data("broken".utf8).write(to: bundled)
        let recovered = try NativeShioriSession(directoryURL: directories[0], moduleURL: bundled,
                                                moduleResolver: resolver, niseStateStoreURL: stateA)
        #expect(try await ShioriMessageParser.parseResponse(recovered.requestAsync(click)).value == "\\0クリック\\e")
        try await recovered.closeAsync()
    }
}

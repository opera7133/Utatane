import Foundation
import Testing
import UtataneModuleHost
import UtatanePlugin
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_MINATO_MODULE"] != nil))
struct MinatoNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `shared minato runs two ghosts and recovers a broken bundled copy`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "湊 複数 \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "minato/lib/libminato.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_MINATO_MODULE"])), to: module)
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        var directories: [URL] = []
        for name in ["A", "B"] {
            let directory = root.appending(path: name)
            try FileManager.default.createDirectory(at: directory.appending(path: "talks"), withIntermediateDirectories: true)
            try "[characters]\n\"湊\" = \"\\\\0\"\n".write(to: directory.appending(path: "config.toml"), atomically: true, encoding: .utf8)
            try #"""
            OnBoot => {
                global save.count += 1
                湊: count=${save.count}
            }
            """#.write(to: directory.appending(path: "talks/main.mnt"), atomically: true, encoding: .utf8)
            directories.append(directory)
            #expect(try resolver.moduleURL(for: .minato, masterDirectoryURL: directory) == module)
        }
        let request = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        let bundledB = directories[1].appending(path: "libminato.dylib")
        try FileManager.default.copyItem(at: module, to: bundledB)
        #expect(try resolver.moduleURL(for: .minato, masterDirectoryURL: directories[1]) == bundledB)
        let a = try NativeShioriSession(directoryURL: directories[0], moduleURL: module, moduleResolver: resolver)
        let b = try NativeShioriSession(directoryURL: directories[1], moduleURL: bundledB, moduleResolver: resolver)
        #expect(try await ShioriMessageParser.parseResponse(a.requestAsync(request)).value?.contains("count=1") == true)
        #expect(try await ShioriMessageParser.parseResponse(a.requestAsync(request)).value?.contains("count=2") == true)
        #expect(try await ShioriMessageParser.parseResponse(b.requestAsync(request)).value?.contains("count=1") == true)
        try await a.closeAsync()
        try await b.closeAsync()
        let bundled = directories[0].appending(path: "libminato.dylib")
        try Data("broken".utf8).write(to: bundled)
        #expect(try resolver.moduleURL(for: .minato, masterDirectoryURL: directories[0]) == bundled)
        let strict = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:], allowsFallback: false)
        #expect(throws: NativeShioriProcessError.self) {
            try NativeShioriSession(directoryURL: directories[0], moduleURL: bundled, moduleResolver: strict)
        }
        let recovered = try NativeShioriSession(directoryURL: directories[0], moduleURL: bundled, moduleResolver: resolver)
        #expect(try await ShioriMessageParser.parseResponse(recovered.requestAsync(request)).value?.contains("count=3") == true)
        try await recovered.closeAsync()
    }

    @Test func `bundled minato uses the conventional loader without overwriting a live session`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "湊 テスト \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "talks"), withIntermediateDirectories: true)
        try #"""
        [characters]
        "湊" = "\\0"
        """#.write(to: root.appending(path: "config.toml"), atomically: true, encoding: .utf8)
        try "OnBoot => {\n    湊: こんにちは😀\n}\n".write(
            to: root.appending(path: "talks/main.mnt"), atomically: true, encoding: .utf8
        )
        let module = root.appending(path: "libminato.dylib")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_MINATO_MODULE"])), to: module
        )
        let request = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        let session = try DynamicLibraryModuleSession.open(directoryURL: root, moduleURL: module)
        #expect(throws: DynamicLibraryModuleError.self) {
            try DynamicLibraryModuleSession.open(directoryURL: root, moduleURL: module)
        }
        let response = try ShioriMessageParser.parseResponse(session.request(request))
        #expect(response.statusCode == 200)
        #expect(response.headers["Charset"] == "UTF-8")
        #expect(response.value?.contains("こんにちは😀") == true)
        try session.close()
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "save.json").path))
        let reloaded = try DynamicLibraryModuleSession.open(directoryURL: root, moduleURL: module)
        #expect(try ShioriMessageParser.parseResponse(reloaded.request(request)).value?.contains("こんにちは😀") == true)
        try reloaded.close()
    }
}

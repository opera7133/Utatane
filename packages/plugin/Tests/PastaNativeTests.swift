import Foundation
import Testing
import UtataneModuleHost
import UtatanePlugin
import UtataneShiori

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_PASTA_MODULE"] != nil))
struct PastaNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
    func `shared pasta runs two ghosts and recovers a broken bundled copy`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pasta 複数 \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let module = support.appending(path: "pasta/lib/libpasta.dylib")
        try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_PASTA_MODULE"])), to: module)
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
        var directories: [URL] = []
        for name in ["A", "B"] {
            let directory = root.appending(path: name)
            try FileManager.default.createDirectory(at: directory.appending(path: "scripts/pasta/shiori"), withIntermediateDirectories: true)
            try "[actor.\"テスト\"]\nspot = 0\n[persistence]\nobfuscate = false\n".write(
                to: directory.appending(path: "pasta.toml"), atomically: true, encoding: .utf8
            )
            try #"""
            local save = require "pasta.save"
            SHIORI = {}
            function SHIORI.load() return true end
            function SHIORI.request(req)
                save.count = (save.count or 0) + 1
                return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: count=" .. save.count .. "\r\n\r\n"
            end
            function SHIORI.unload() end
            return SHIORI
            """#.write(to: directory.appending(path: "scripts/pasta/shiori/entry.lua"), atomically: true, encoding: .utf8)
            directories.append(directory)
            #expect(try resolver.moduleURL(for: .pasta, masterDirectoryURL: directory) == module)
        }
        let request = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        let bundledB = directories[1].appending(path: "libpasta.dylib")
        try FileManager.default.copyItem(at: module, to: bundledB)
        #expect(try resolver.moduleURL(for: .pasta, masterDirectoryURL: directories[1]) == bundledB)
        let a = try NativeShioriSession(directoryURL: directories[0], moduleURL: module, moduleResolver: resolver)
        let b = try NativeShioriSession(directoryURL: directories[1], moduleURL: bundledB, moduleResolver: resolver)
        #expect(try await ShioriMessageParser.parseResponse(a.requestAsync(request)).value?.contains("count=1") == true)
        #expect(try await ShioriMessageParser.parseResponse(a.requestAsync(request)).value?.contains("count=2") == true)
        #expect(try await ShioriMessageParser.parseResponse(b.requestAsync(request)).value?.contains("count=1") == true)
        try await a.closeAsync()
        try await b.closeAsync()
        let bundled = directories[0].appending(path: "libpasta.dylib")
        try Data("broken".utf8).write(to: bundled)
        #expect(try resolver.moduleURL(for: .pasta, masterDirectoryURL: directories[0]) == bundled)
        let strict = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:], allowsFallback: false)
        #expect(throws: NativeShioriProcessError.self) {
            try NativeShioriSession(directoryURL: directories[0], moduleURL: bundled, moduleResolver: strict)
        }
        let recovered = try NativeShioriSession(directoryURL: directories[0], moduleURL: bundled, moduleResolver: resolver)
        #expect(try await ShioriMessageParser.parseResponse(recovered.requestAsync(request)).value?.contains("count=3") == true)
        try await recovered.closeAsync()
    }
}

import Foundation
import Testing
import UtataneCore
@testable import UtatanePOSIXShiori
import UtataneShiori

struct KagariResolverTests {
    @Test func `bundled kagari is found without configuration and local overrides keep priority`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appending(path: "ghost/master")
        let support = root.appending(path: "support/NativeShiori")
        let resources = root.appending(path: "Utatane.app/Contents/Resources")
        let resolver = POSIXShioriModuleResolver(applicationSupportURL: support, bundledResourcesURL: resources)
        #expect(resolver.moduleURL(for: .kagari, masterDirectoryURL: master, environment: [:]) == nil)
        for directory in [resources.appending(path: "NativeShiori/kagari"), support.appending(path: "kagari"), master] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let module = directory.appending(path: "libkagari.dylib")
            try Data().write(to: module)
            #expect(resolver.moduleURL(for: .kagari, masterDirectoryURL: master, environment: [:]) == module)
        }
    }

    @Test func `packaged ghost module takes precedence over common installation`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appending(path: "ghost/master")
        let support = root.appending(path: "support")
        let resolver = POSIXShioriModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil)
        let installed = support.appending(path: "kagari/lib/libkagari.dylib")
        let bundled = master.appending(path: "kagari/lib/libkagari.dylib")
        let flat = master.appending(path: "libkagari.dylib")
        for module in [installed, bundled, flat] {
            try FileManager.default.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("invalid-library".utf8).write(to: module)
            #expect(resolver.moduleURL(for: .kagari, masterDirectoryURL: master, environment: [:]) == module)
        }
        // A selected broken local module must fail rather than trying the installed one.
        #expect(throws: POSIXShioriError.self) {
            try POSIXShioriSession(masterDirectoryURL: master, moduleURL: #require(resolver.moduleURL(
                for: .kagari, masterDirectoryURL: master, environment: [:]
            )), kind: .kagari)
        }
    }

    @Test func `kagari detection does not claim every Lua ghost`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "return {}".write(to: root.appending(path: "index.lua"), atomically: true, encoding: .utf8)
        let resolver = POSIXShioriModuleResolver()
        #expect(resolver.kind(for: root) == nil)
        try "shiori,tkytk.dll\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        #expect(resolver.kind(for: root) == nil)
        try "shiori,kagari.dll\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        #expect(resolver.kind(for: root) == .kagari)
        let library = root.appending(path: "override.dylib")
        try Data().write(to: library)
        #expect(resolver.moduleURL(for: .kagari, masterDirectoryURL: root, environment: ["UTATANE_KAGARI_MODULE": library.path]) == library)
        #expect(resolver.moduleURL(for: .kagari, masterDirectoryURL: root, environment: ["UTATANE_AOSORA_MODULE": library.path]) != library)
    }
}

@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["UTATANE_KAGARI_MODULE"] != nil)
)
struct KagariNativeTests {
    private var module: URL {
        URL(filePath: ProcessInfo.processInfo.environment["UTATANE_KAGARI_MODULE"]!)
    }

    private func fixture(_ script: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "utatane kagari 日本語 \(UUID())")
        try FileManager.default.createDirectory(at: root.appending(path: "lib"), withIntermediateDirectories: true)
        try script.write(to: root.appending(path: "index.lua"), atomically: true, encoding: .utf8)
        try "return 'こんにちは'".write(to: root.appending(path: "lib/helper.lua"), atomically: true, encoding: .utf8)
        try "shiori,kagari.dll\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        return root
    }

    private let script = #"""
    local helper = require('helper')
    local root
    local count = 0
    return {
      load = function(path) root = path; return true end,
      request = function(req)
        count = count + 1
        return 'SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: ' .. helper .. count .. '\r\nReference0: kept\r\n\r\n'
      end,
      unload = function()
        local f = assert(io.open(root .. 'unloaded', 'w'))
        f:write('ok'); f:close(); return true
      end
    }
    """#

    @Test func `broken bundled kagari uses common installation only when enabled`() throws {
        let root = try fixture(script)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "../support-\(UUID())").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: support) }
        let installed = support.appending(path: "kagari/lib/libkagari.dylib")
        try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        for library in try FileManager.default.contentsOfDirectory(at: module.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            where library.pathExtension == "dylib"
        {
            try FileManager.default.copyItem(at: library, to: installed.deletingLastPathComponent().appending(path: library.lastPathComponent))
        }
        let bundled = root.appending(path: "libkagari.dylib")
        try Data("broken".utf8).write(to: bundled)
        let strict = POSIXShioriModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, allowsFallback: false)
        #expect(throws: POSIXShioriError.self) {
            try strict.loadSession(for: .kagari, masterDirectoryURL: root, environment: [:])
        }
        let resolver = POSIXShioriModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil)
        let recovered = try resolver.loadSession(for: .kagari, masterDirectoryURL: root, environment: [:])
        #expect(try ShioriMessageParser.parseResponse(recovered.request("GET SHIORI/3.0\r\nID: OnBoot\r\n\r\n")).value == "こんにちは1")
        recovered.close()
        #expect(throws: POSIXShioriError.self) {
            try resolver.loadSession(for: .kagari, masterDirectoryURL: root,
                                     environment: ["UTATANE_KAGARI_MODULE": bundled.path])
        }
    }

    @Test func `real kagari loads isolates instances and unloads`() async throws {
        let root = try fixture(script)
        defer { try? FileManager.default.removeItem(at: root) }
        for library in try FileManager.default.contentsOfDirectory(at: module.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            where library.pathExtension == "dylib"
        {
            try FileManager.default.copyItem(at: library, to: root.appending(path: library.lastPathComponent))
        }
        let resolver = POSIXShioriModuleResolver(applicationSupportURL: root.appending(path: "no-shared-modules"), bundledResourcesURL: nil)
        let first = try resolver.loadSession(for: .kagari, masterDirectoryURL: root, environment: [:])
        let second = try resolver.loadSession(for: .kagari, masterDirectoryURL: root, environment: [:])
        let request = "GET SHIORI/3.0\r\nID: OnBoot\r\n\r\n"
        for count in 1 ... 20 {
            let response = try ShioriMessageParser.parseResponse(first.request(request))
            #expect(response.value == "こんにちは\(count)")
            #expect(response.referenceValues[0] == "kept")
        }
        #expect(try ShioriMessageParser.parseResponse(second.request(request)).value == "こんにちは1")
        first.close()
        first.close()
        #expect(throws: POSIXShioriError.self) { try first.request(request) }
        second.close()
        #expect(try String(contentsOf: root.appending(path: "unloaded"), encoding: .utf8) == "ok")
        let engine = try POSIXShioriPersonalityEngine(masterDirectoryURL: root)
        #expect(try await engine.handle(event: .boot)?.rawValue == "こんにちは1")
        await engine.shutdown()
    }

    @Test(arguments: ["error('bad')", "return nil", "return {}", "return 5", "return {load=function() return false end, request=function() end, unload=function() end}", "return {load=function() error('bad') end, request=function() end, unload=function() end}", "return {load=function() return 'yes' end, request=function() end, unload=function() end}"])
    func `failed load is rejected`(body: String) throws {
        let root = try fixture(body)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: POSIXShioriError.self) {
            try POSIXShioriSession(masterDirectoryURL: root, moduleURL: module, kind: .kagari)
        }
    }

    @Test(arguments: ["error('bad')", "return nil", "return {}", "return 123"])
    func `bad request returns 500 and failing unload releases instance`(body: String) throws {
        let root = try fixture("return { load=function() return true end, request=function() \(body) end, unload=function() error('bad unload') end }")
        defer { try? FileManager.default.removeItem(at: root) }
        for _ in 0 ..< 3 {
            let session = try POSIXShioriSession(masterDirectoryURL: root, moduleURL: module, kind: .kagari)
            #expect(try ShioriMessageParser.parseResponse(session.request("GET SHIORI/3.0\r\n\r\n")).statusCode == 500)
            session.close()
        }
    }
}

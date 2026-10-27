import Foundation
import Testing
@testable import UtatanePlugin

struct KagariPluginCatalogTests {
    @Test(arguments: ["kagari.dll", "libkagari.dylib"])
    func `KAGARI plugin uses the instance ABI including explicit macOS override`(filename: String) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = root.appending(path: "plugin")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data().write(to: plugin.appending(path: filename))
        let override = filename.hasSuffix("dylib") ? "filename.macos,\(filename)\n" : ""
        try "name,Lua Plugin\nid,lua-plugin\nfilename,kagari.dll\n\(override)".write(to: plugin.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        let installed = try #require(PluginCatalog().load(from: [root]).first)
        #expect(installed.runtime == .nativeSHIORI(.kagari))
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_KAGARI_MODULE"] != nil))
struct KagariPluginNativeTests {
    @Test func `real KAGARI plugin preserves PLUGIN wire isolated state and reload`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "utatane-kagari-plugin-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = #"""
        local root
        local count = 0
        return {
          load = function(path)
            root = path
            local file = io.open(root .. 'count.txt', 'r')
            if file then count = tonumber(file:read('*a')); file:close() end
            return true
          end,
          request = function(req)
            assert(req:find('GET PLUGIN/2.0\r\n', 1, true))
            assert(req:find('Language: Japanese\r\n', 1, true))
            if req:find('ID: version\r\n', 1, true) then
              return 'PLUGIN/2.0 200 OK\r\nCharset: UTF-8\r\nValue: fixture/1\r\n\r\n'
            end
            count = count + 1
            return 'PLUGIN/2.0 200 OK\r\nCharset: UTF-8\r\nScript: こんにちは' .. count .. '\r\nTarget: Two\r\n\r\n'
          end,
          unload = function()
            local file = assert(io.open(root .. 'count.txt', 'w'))
            file:write(tostring(count)); file:close(); return true
          end
        }
        """#
        for name in ["first", "second"] {
            let directory = root.appending(path: name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try script.write(to: directory.appending(path: "index.lua"), atomically: true, encoding: .utf8)
            try Data().write(to: directory.appending(path: "kagari.dll"))
            try "name,\(name)\nid,\(name)\nfilename,kagari.dll\n".write(to: directory.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        }
        let plugins = try PluginCatalog().load(from: [root])
        let module = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_KAGARI_MODULE"]))
        let firstPlugin = try #require(plugins.first { $0.id == "first" })
        let secondPlugin = try #require(plugins.first { $0.id == "second" })
        let first = try KagariPluginTransport(plugin: firstPlugin, moduleURLOverride: module)
        let second = try KagariPluginTransport(plugin: secondPlugin, moduleURLOverride: module)
        let request = PluginRequest(method: "GET", id: "OnMenuExec", language: "Japanese")
        #expect(try await first.request(request).script == "こんにちは1")
        #expect(try await first.request(request).script == "こんにちは2")
        #expect(try await second.request(request).script == "こんにちは1")
        await first.shutdown()
        #expect(try String(contentsOf: firstPlugin.directory.appending(path: "count.txt"), encoding: .utf8) == "2")
        let reloaded = try KagariPluginTransport(plugin: firstPlugin, moduleURLOverride: module)
        let response = try await reloaded.request(request)
        #expect(response.script == "こんにちは3")
        #expect(response.target == "Two")
        await second.shutdown()
        await reloaded.shutdown()
    }
}

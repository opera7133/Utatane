import Foundation
import Testing
import UtataneMisakaNative
import UtataneModuleHost
import UtatanePlugin

private struct MisakaPluginFixture {
    let root: URL
    let plugin: InstalledPlugin
    let stateDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "美坂プラグイン \(UUID())")
        let plugins = root.appending(path: "plugins")
        let directory = plugins.appending(path: "echo")
        stateDirectory = root.appending(path: "state")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "type,plugin\nid,echo\nname,Echo\nfilename,misaka.dll\ncharset,Shift_JIS\n".write(
            to: directory.appending(path: "descript.txt"), atomically: true, encoding: .utf8
        )
        try Data().write(to: directory.appending(path: "misaka.dll"))
        try "dictionaries\n{\nmisaka.txt\n}\n".write(to: directory.appending(path: "misaka.ini"), atomically: true, encoding: .shiftJIS)
        try """
        $_Variable
        {$count=0}

        $OnMenuExec
        {$count++}{$appendheader("Event: OnResult")}{$appendheader("Reference0: {$count}")}{$appendheader("Script: 完了")}

        $OnEcho
        {$appendheader("Reference0: {$reference(0)}")}
        """.write(to: directory.appending(path: "misaka.txt"), atomically: true, encoding: .shiftJIS)
        plugin = try #require(PluginCatalog().load(from: [plugins]).first)
        #expect(plugin.runtime == .nativeSHIORI(.misaka))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func exercisePluginReload(moduleURL: URL?) async throws {
    let fixture = try MisakaPluginFixture()
    defer { fixture.remove() }
    let plugin = fixture.plugin
    let state = fixture.stateDirectory
    let resolver = UtataneModuleResolver(
        applicationSupportURL: fixture.root.appending(path: "modules"), bundledResourcesURL: nil,
        environment: moduleURL.map { ["UTATANE_MISAKA_MODULE": $0.path] } ?? [:]
    )
    let legacy = plugin.directory.appending(path: "misaka_vars.json")
    let legacyData = try JSONEncoder().encode(["count": ["7"]])
    try legacyData.write(to: legacy)
    let factory: PluginRuntime.TransportFactory = { plugin in
        try MisakaPluginTransport(plugin: plugin, stateDirectoryURL: state, moduleResolver: resolver)
    }
    let runtime = PluginRuntime()
    #expect(await runtime.reload([plugin], transportFactory: factory).isEmpty)
    let first = try #require(await runtime.request(pluginIDOrName: "Echo", event: "OnMenuExec"))
    #expect(first.event == "OnResult")
    #expect(first.script == "完了")
    #expect(first.references[0] == "8")
    let echo = try await runtime.request(pluginIDOrName: "echo", event: "OnEcho", references: [0: "日本語"])
    #expect(echo?.references[0] == "日本語")
    // The new session must read the state written by shutdown, not the previous snapshot.
    #expect(await runtime.reload([plugin], transportFactory: factory).isEmpty)
    #expect(try await runtime.request(pluginIDOrName: "echo", event: "OnMenuExec")?.references[0] == "9")
    await runtime.unloadAll()
    #expect(await runtime.loadedPluginIDs.isEmpty)
    let stateURL = PluginStateStore(directoryURL: state).misakaVariableStoreURL(for: plugin)
    let saved = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: stateURL))
    #expect(saved["count"] == ["9"])
    #expect(try Data(contentsOf: legacy) == legacyData)
}

struct MisakaPluginBuiltinTests {
    @Test func `reload and state migration`() async throws {
        try await exercisePluginReload(moduleURL: nil)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"] != nil))
struct MisakaPluginModuleTests {
    @Test func reloadAndStateMigration() async throws {
        let library = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"]))
        try await exercisePluginReload(moduleURL: library)
    }
}

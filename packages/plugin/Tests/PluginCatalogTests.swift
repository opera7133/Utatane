import Foundation
import Testing
@testable import UtatanePlugin

@Test func `loads plugin descript and prefers native SHIORI over DLL`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let plugin = root.appending(path: "wallet", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
    try Data("".utf8).write(to: plugin.appending(path: "yaya.txt"))
    try Data("".utf8).write(to: plugin.appending(path: "plugin.dll"))
    try Data("charset,UTF-8\nname,Wallet\nid,plugin-wallet\nfilename,plugin.dll\nsecondchangeinterval,5\n".utf8)
        .write(to: plugin.appending(path: "descript.txt"))

    let loaded = try #require(PluginCatalog().load(from: [root]).first)
    #expect(loaded.id == "plugin-wallet")
    #expect(loaded.secondChangeInterval == 5)
    #expect(loaded.runtime == .nativeSHIORI(.yaya))
}

@Test func `rejects traversal and duplicate IDs`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a", "b"] {
        let plugin = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data("name,\(name)\nid,same-id\nfilename,../outside.dll\n".utf8)
            .write(to: plugin.appending(path: "descript.txt"))
    }
    #expect(try PluginCatalog().load(from: [root]).isEmpty)
}

@Test func `accepts omitted or plugin type and rejects another content type`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    for (name, type) in [("omitted", nil), ("plugin", "plugin"), ("ghost", "ghost")] {
        let directory = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appending(path: "module.dylib"))
        let typeLine = type.map { "type,\($0)\n" } ?? ""
        try Data("name,\(name)\nid,\(name)\n\(typeLine)filename,module.dylib\n".utf8)
            .write(to: directory.appending(path: "descript.txt"))
    }

    #expect(try PluginCatalog().load(from: [root]).map(\.id).sorted() == ["omitted", "plugin"])
}

@Test func `serializes and parses PLUGIN 2 messages`() throws {
    let request = PluginRequest(method: "GET", id: "OnMenuExec", sender: "Ria", references: [0: "1"])
    #expect(request.serialized().hasPrefix("GET PLUGIN/2.0\r\n"))
    let response = try PluginResponse.parse(
        "PLUGIN/2.0 200 OK\r\nEvent: OnPluginResult\r\nReference0: done\r\nScript: \\0ok\\e\r\n\r\n"
    )
    #expect(response.event == "OnPluginResult")
    #expect(response.references[0] == "done")
    #expect(response.script == #"\0ok\e"#)
}

@Test func `runtime loads native plugins and dispatches by ID or name`() async throws {
    let plugin = testPlugin(id: "clock", name: "Clock", interval: 2)
    let recorder = RecordingPluginTransport()
    let runtime = PluginRuntime()
    let failures = await runtime.reload([plugin]) { _ in recorder }

    #expect(failures.isEmpty)
    #expect(await runtime.loadedPluginIDs == ["clock"])
    _ = try await runtime.request(pluginIDOrName: "Clock", event: "OnMenuExec", sender: "Ria")
    #expect(await recorder.events == ["OnMenuExec"])
    #expect(await runtime.secondChangeResponses().isEmpty)
    #expect(await runtime.secondChangeResponses().map(\.0.id) == ["clock"])
    #expect(await recorder.events == ["OnMenuExec", "OnSecondChange"])
}

private actor RecordingPluginTransport: PluginTransport {
    private(set) var events: [String] = []

    func request(_ request: PluginRequest) async throws -> PluginResponse {
        events.append(request.headers["ID"] ?? "")
        return PluginResponse(statusCode: 204)
    }
}

private func testPlugin(id: String, name: String, interval: Int) -> InstalledPlugin {
    InstalledPlugin(
        id: id,
        name: name,
        directory: URL(fileURLWithPath: "/tmp/\(id)"),
        moduleURL: URL(fileURLWithPath: "/tmp/\(id)/plugin.dll"),
        charset: "UTF-8",
        author: nil,
        authorURL: nil,
        homeURL: nil,
        readmeURL: nil,
        readmeCharset: nil,
        secondChangeInterval: interval,
        observesOtherGhostTalk: false,
        runtime: .nativeSHIORI(.yaya)
    )
}

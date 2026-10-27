import Foundation
import Testing
@testable import UtatanePlugin
import UtataneShiori

@MainActor
struct PluginResponseRoutingTests {
    let first = PluginGhostTarget(id: URL(filePath: "/ghost/one"), names: ["One", "First"])
    let second = PluginGhostTarget(id: URL(filePath: "/ghost/two"), names: ["Two", "Second"])

    @Test func `explicit Target reaches another ghost and unknown Target returns to caller`() {
        let running = [first, second]
        #expect(PluginResponseRouter.targets(for: " second ", callerID: first.id, running: running) == [second.id])
        #expect(PluginResponseRouter.targets(for: "missing", callerID: second.id, running: running) == [second.id])
        #expect(PluginResponseRouter.targets(for: nil, callerID: second.id, running: running) == [second.id])
        #expect(PluginResponseRouter.targets(for: "__SYSTEM_ALL_GHOST__", callerID: first.id, running: running) == [first.id, second.id])
        #expect(PluginResponseRouter.targets(for: nil, callerID: second.id, running: [first]) == [first.id])
        #expect(PluginResponseRouter.targets(for: nil, callerID: nil, running: []) == [])
    }

    @Test func `targeted Event uses its ghost reply and clears fallback script options`() async throws {
        let response = try PluginResponse.parse("PLUGIN/2.0 200 OK\r\nTarget: Two\r\nEvent: OnTest\r\nReference2: kept\r\nScript: fallback\r\nScriptOption: nobreak,notranslate\r\n\r\n")
        var calls: [URL] = []
        let replies = await PluginResponseRouter.route(response, callerID: first.id, running: [first, second]) { id, event, references, notify in
            calls.append(id)
            #expect(event == "OnTest")
            #expect(references == [2: "kept"])
            #expect(!notify)
            return "reply from Two"
        }
        #expect(calls == [second.id])
        #expect(replies.map(\.ghostID) == [second.id])
        #expect(replies.map(\.script) == ["reply from Two"])
        #expect(replies.first?.flags == ["plugin-event"])
        #expect(replies.first?.isPluginScript == false)
    }

    @Test func `notify reaches all ghosts without interpreting their replies as scripts`() async throws {
        let response = try PluginResponse.parse("PLUGIN/2.0 200 OK\r\nTarget: __SYSTEM_ALL_GHOST__\r\nEvent: OnTest\r\nEventOption: notify\r\nScript: fallback\r\nScriptOption: NoBreak,notranslate\r\n\r\n")
        var calls: [URL] = []
        let replies = await PluginResponseRouter.route(response, callerID: first.id, running: [first, second]) { id, _, _, notify in
            calls.append(id)
            #expect(notify)
            return "must not play"
        }
        #expect(calls == [first.id, second.id])
        #expect(replies.map(\.script) == ["fallback", "fallback"])
        #expect(replies.allSatisfy { $0.flags == ["nobreak", "notranslate", "plugin-script"] })
        #expect(replies.map(\.isPluginScript) == [true, true])
    }

    @Test func `unhandled Event retains fallback and non-success responses have no side effects`() async throws {
        let response = try PluginResponse.parse("PLUGIN/2.0 200 OK\r\nEvent: OnUnhandled\r\nScript: fallback\r\n\r\n")
        let replies = await PluginResponseRouter.route(response, callerID: first.id, running: [first]) { _, _, _, _ in "" }
        #expect(replies.map(\.script) == ["fallback"])
        var calls = 0
        let ignored = await PluginResponseRouter.route(.init(statusCode: 204, headers: response.headers), callerID: first.id, running: [first]) { _, _, _, _ in calls += 1; return nil }
        #expect(ignored.isEmpty)
        #expect(calls == 0)
    }

    @Test(arguments: [("ja-JP", "Japanese"), ("en-US", "English"), ("zh-Hant", "Chinese"), ("ko-KR", "Korean")])
    func `Language header uses the English language name`(identifier: String, expected: String) {
        #expect(PluginLanguage.header(for: identifier) == expected)
        let request = PluginRequest(method: "GET", id: "OnTest", language: expected)
        #expect(request.headers["Language"] == expected)
        #expect(request.headers["Sender"] == nil)
    }
}

private actor VersionContractTransport: PluginTransport {
    private let charset: String
    private let status: Int
    private(set) var requests: [PluginRequest] = []

    init(charset: String = "Shift_JIS", status: Int = 200) {
        self.charset = charset
        self.status = status
    }

    func request(_ request: PluginRequest) -> PluginResponse {
        requests.append(request)
        return request.headers["ID"] == "version"
            ? .init(statusCode: status, headers: ShioriHeaders([ShioriHeader(name: "Charset", value: charset)]))
            : .init(statusCode: 204)
    }
}

struct PluginWireContractTests {
    private func plugin(id: String = "fixture", before: Bool = false) -> InstalledPlugin {
        InstalledPlugin(id: id, name: id, directory: URL(filePath: "/tmp/\(id)"), moduleURL: URL(filePath: "/tmp/\(id)/yaya.dll"),
                        charset: "UTF-8", author: nil, authorURL: nil, homeURL: nil, readmeURL: nil, readmeCharset: nil,
                        secondChangeInterval: 1, observesOtherGhostTalk: true, observesOtherGhostTalkBefore: before,
                        runtime: .nativeSHIORI(.yaya))
    }

    @Test(arguments: ["request", "broadcast"])
    func `version Charset applies to following requests and reload resets it`(mode: String) async throws {
        let runtime = PluginRuntime()
        let transport = VersionContractTransport()
        _ = await runtime.reload([plugin()]) { _ in transport }
        if mode == "request" {
            _ = try await runtime.request(pluginIDOrName: "fixture", event: "version")
        } else {
            _ = await runtime.broadcast(event: "version")
        }
        _ = try await runtime.request(pluginIDOrName: "fixture", event: "OnMenuExec", sender: "Caller")
        _ = await runtime.secondChangeResponses()
        let requests = await transport.requests
        #expect(requests.map { $0.headers["Charset"] } == ["UTF-8", "Shift_JIS", "Shift_JIS"])
        #expect(requests[1].headers["Sender"] == "Caller")
        #expect(requests[2].headers["Sender"] == nil)
        let fresh = VersionContractTransport()
        _ = await runtime.reload([plugin()]) { _ in fresh }
        _ = try await runtime.request(pluginIDOrName: "fixture", event: "OnMenuExec")
        #expect(await fresh.requests.first?.headers["Charset"] == "UTF-8")
        await runtime.unloadAll()
    }

    @Test(arguments: [("not-a-charset", 200), ("Shift_JIS", 500)])
    func `invalid or failed version negotiation cannot change request encoding`(charset: String, status: Int) async throws {
        let runtime = PluginRuntime()
        let transport = VersionContractTransport(charset: charset, status: status)
        _ = await runtime.reload([plugin()]) { _ in transport }
        _ = await runtime.broadcast(event: "version")
        _ = try await runtime.request(pluginIDOrName: "fixture", event: "OnMenuExec")
        #expect(await transport.requests.last?.headers["Charset"] == "UTF-8")
        await runtime.unloadAll()
    }

    @Test func `talk timing filters only subscribed plugins without a host Sender`() async {
        let runtime = PluginRuntime()
        let before = VersionContractTransport()
        let after = VersionContractTransport()
        _ = await runtime.reload([plugin(id: "before", before: true), plugin(id: "after")]) { plugin in
            plugin.id == "before" ? before : after
        }
        _ = await runtime.broadcast(event: "OnOtherGhostTalk", references: [4: "hello"],
                                    matching: { $0.observesOtherGhostTalk && $0.observesOtherGhostTalkBefore })
        #expect(await before.requests.count == 1)
        #expect(await before.requests.first?.headers["Sender"] == nil)
        #expect(await before.requests.first?.headers["Reference4"] == "hello")
        #expect(await after.requests.isEmpty)
        await runtime.unloadAll()
    }

    @Test func `catalog reads before after and optional surface notifications`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for timing in ["before", "after", "0"] {
            let directory = root.appending(path: timing)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appending(path: "yaya.dll"))
            try "name,\(timing)\nid,\(timing)\nfilename,yaya.dll\notherghosttalk,\(timing)\nothersurfacechange,1\n".write(to: directory.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        }
        let plugins = try PluginCatalog().load(from: [root])
        #expect(plugins.count == 3)
        #expect(plugins.first { $0.id == "before" }?.observesOtherGhostTalkBefore == true)
        #expect(plugins.first { $0.id == "after" }?.observesOtherGhostTalk == true)
        #expect(plugins.first { $0.id == "0" }?.observesOtherGhostTalk == false)
        #expect(plugins.map(\.observesOtherSurfaceChange) == [true, true, true])
    }
}

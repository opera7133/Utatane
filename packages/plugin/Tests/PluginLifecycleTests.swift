import Foundation
import Testing
@testable import UtatanePlugin

private func lifecyclePlugin(id: String = "example", interval: Int = 1, directory: URL = URL(fileURLWithPath: "/tmp/example")) -> InstalledPlugin {
    InstalledPlugin(id: id, name: id, directory: directory, moduleURL: directory.appending(path: "plugin.dll"), charset: "UTF-8",
                    author: nil, authorURL: nil, homeURL: nil, readmeURL: nil, readmeCharset: nil,
                    secondChangeInterval: interval, observesOtherGhostTalk: false, runtime: .nativeSHIORI(.misaka))
}

private actor LifecycleGate {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if signaled {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        signaled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor GatedPlugin: PluginTransport {
    let requestStarted = LifecycleGate()
    let requestCanFinish = LifecycleGate()
    let shutdownStarted = LifecycleGate()
    let shutdownCanFinish = LifecycleGate()
    private(set) var shutdownCount = 0
    let gateShutdown: Bool
    init(gateShutdown: Bool = false) {
        self.gateShutdown = gateShutdown
    }

    func request(_: PluginRequest) async throws -> PluginResponse {
        await requestStarted.signal()
        await requestCanFinish.wait()
        return PluginResponse(statusCode: 200)
    }

    func shutdown() async {
        shutdownCount += 1
        await shutdownStarted.signal()
        if gateShutdown {
            await shutdownCanFinish.wait()
        }
    }
}

private final class CreationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var values: [String] {
        lock.withLock { entries }
    }

    func append(_ value: String) {
        lock.withLock { entries.append(value) }
    }
}

struct PluginLifecycleTests {
    @Test(arguments: ["tick", "broadcast", "request"])
    func `late responses do not resurrect unloaded plugins`(kind: String) async throws {
        let runtime = PluginRuntime()
        let transport = GatedPlugin()
        await runtime.reload([lifecyclePlugin()]) { _ in transport }
        let pending = Task { () throws -> Int in
            switch kind {
            case "tick": return await runtime.secondChangeResponses().count
            case "broadcast": return await runtime.broadcast(event: "OnTest").count
            default: return try await runtime.request(pluginIDOrName: "example", event: "OnTest") == nil ? 0 : 1
            }
        }
        await transport.requestStarted.wait()
        await runtime.unloadAll()
        await transport.requestCanFinish.signal()
        #expect(try await pending.value == 0)
        #expect(await runtime.loadedPluginIDs.isEmpty)
        #expect(await transport.shutdownCount == 1)
    }

    @Test func `overlapping reloads wait for shutdown and only latest installs`() async {
        let runtime = PluginRuntime()
        let old = GatedPlugin(gateShutdown: true)
        let recorder = CreationRecorder()
        await runtime.reload([lifecyclePlugin()]) { _ in old }
        let first = Task {
            await runtime.reload([lifecyclePlugin(id: "first")]) { plugin in
                recorder.append(plugin.id)
                return GatedPlugin()
            }
        }
        await old.shutdownStarted.wait()
        // Begin a newer transition while the original session is still shutting down.
        let secondStarted = LifecycleGate()
        let second = Task {
            await secondStarted.signal()
            return await runtime.reload([lifecyclePlugin(id: "second")]) { plugin in
                recorder.append(plugin.id)
                return GatedPlugin()
            }
        }
        await secondStarted.wait()
        // Observe the runtime's transition counter, rather than waiting for an arbitrary delay.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await runtime.generation < 3, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(await runtime.generation == 3)
        #expect(recorder.values.isEmpty)
        await old.shutdownCanFinish.signal()
        _ = await first.value
        _ = await second.value
        #expect(recorder.values == ["second"])
        #expect(await runtime.loadedPluginIDs == ["second"])
        #expect(await old.shutdownCount == 1)
        await runtime.unloadAll()
    }
}

struct PluginStateStoreTests {
    @Test func `migration preserves original and existing state`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "plugin")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let legacy = source.appending(path: "misaka_vars.json")
        try Data("legacy".utf8).write(to: legacy)
        let plugin = lifecyclePlugin(directory: source)
        let store = PluginStateStore(directoryURL: root.appending(path: "state"))
        let state = try store.prepareMisakaState(for: plugin)
        #expect(try Data(contentsOf: state) == Data("legacy".utf8))
        try Data("newer".utf8).write(to: state)
        #expect(try store.prepareMisakaState(for: plugin) == state)
        #expect(try Data(contentsOf: state) == Data("newer".utf8))
        #expect(try Data(contentsOf: legacy) == Data("legacy".utf8))
    }

    @Test func `plugin IDs stay within state directory`() {
        let root = URL(fileURLWithPath: "/tmp/plugin-state")
        let store = PluginStateStore(directoryURL: root)
        let first = store.misakaVariableStoreURL(for: lifecyclePlugin(id: "../Example/../../"))
        let second = store.misakaVariableStoreURL(for: lifecyclePlugin(id: "../EXAMPLE/../../"))
        #expect(first == second)
        #expect(first.standardizedFileURL.path.hasPrefix(root.path + "/"))
        #expect(first.deletingLastPathComponent().deletingLastPathComponent().path == root.path)
        #expect(first != store.misakaVariableStoreURL(for: lifecyclePlugin(id: "different")))
    }
}

import Foundation

public protocol PluginTransport: Sendable {
    func request(_ request: PluginRequest) async throws -> PluginResponse
    func shutdown() async
}

public extension PluginTransport {
    func shutdown() async {}
}

public struct PluginLoadFailure: Sendable, Equatable {
    public let plugin: InstalledPlugin
    public let message: String

    public init(plugin: InstalledPlugin, message: String) {
        self.plugin = plugin
        self.message = message
    }
}

public actor PluginRuntime {
    public typealias TransportFactory = @Sendable (InstalledPlugin) throws -> any PluginTransport

    private struct LoadedPlugin: Sendable {
        let plugin: InstalledPlugin
        let transport: any PluginTransport
        var secondsUntilTick: Int
    }

    private var loaded: [String: LoadedPlugin] = [:]
    private(set) var generation: UInt64 = 0
    private var pendingShutdown: Task<Void, Never>?

    public init() {}

    @discardableResult
    public func reload(
        _ plugins: [InstalledPlugin],
        transportFactory: TransportFactory
    ) async -> [PluginLoadFailure] {
        let transition = beginUnload()
        await transition.task.value
        guard generation == transition.generation else { return [] }
        pendingShutdown = nil
        var next: [String: LoadedPlugin] = [:]
        var failures: [PluginLoadFailure] = []
        for plugin in plugins {
            let isLoadable = switch plugin.runtime {
            case .nativeSHIORI, .dynamicLibrary, .windowsDLL: true
            case .unavailable: false
            }
            guard isLoadable else { continue }
            do {
                next[plugin.id.lowercased()] = try LoadedPlugin(
                    plugin: plugin,
                    transport: transportFactory(plugin),
                    secondsUntilTick: max(plugin.secondChangeInterval, 1)
                )
            } catch {
                failures.append(PluginLoadFailure(plugin: plugin, message: error.localizedDescription))
            }
        }
        loaded = next
        return failures
    }

    public func unloadAll() async {
        let transition = beginUnload()
        await transition.task.value
        if generation == transition.generation {
            pendingShutdown = nil
        }
    }

    private func beginUnload() -> (generation: UInt64, task: Task<Void, Never>) {
        generation &+= 1
        let previous = pendingShutdown
        let old = Array(loaded.values)
        loaded.removeAll()
        let task = Task {
            await previous?.value
            for entry in old {
                await entry.transport.shutdown()
            }
        }
        pendingShutdown = task
        return (generation, task)
    }

    public var loadedPluginIDs: [String] {
        loaded.values.map(\.plugin.id).sorted()
    }

    public func request(
        pluginIDOrName: String,
        method: String = "GET",
        event: String,
        sender: String? = nil,
        references: [Int: String] = [:]
    ) async throws -> PluginResponse? {
        guard let entry = entry(matching: pluginIDOrName) else { return nil }
        let requestGeneration = generation
        let response = try await entry.transport.request(PluginRequest(
            method: method,
            id: event,
            charset: entry.plugin.charset,
            sender: sender,
            references: references
        ))
        return generation == requestGeneration ? response : nil
    }

    public func secondChangeResponses() async -> [(InstalledPlugin, PluginResponse)] {
        let requestGeneration = generation
        var responses: [(InstalledPlugin, PluginResponse)] = []
        for key in loaded.keys.sorted() {
            guard var entry = loaded[key] else { continue }
            guard entry.plugin.secondChangeInterval > 0 else { continue }
            entry.secondsUntilTick -= 1
            let shouldTick = entry.secondsUntilTick <= 0
            if shouldTick {
                entry.secondsUntilTick = entry.plugin.secondChangeInterval
            }
            loaded[key] = entry
            if shouldTick {
                if let response = try? await entry.transport.request(PluginRequest(
                    method: "GET",
                    id: "OnSecondChange",
                    charset: entry.plugin.charset
                )) {
                    guard generation == requestGeneration else { return [] }
                    responses.append((entry.plugin, response))
                }
            }
            guard generation == requestGeneration else { return [] }
        }
        return responses
    }

    public func broadcast(
        method: String = "GET",
        event: String,
        sender: String? = nil,
        references: [Int: String] = [:]
    ) async -> [(InstalledPlugin, PluginResponse)] {
        let requestGeneration = generation
        var responses: [(InstalledPlugin, PluginResponse)] = []
        for key in loaded.keys.sorted() {
            guard let entry = loaded[key] else { continue }
            let response = try? await entry.transport.request(PluginRequest(
                method: method,
                id: event,
                charset: entry.plugin.charset,
                sender: sender,
                references: references
            ))
            guard generation == requestGeneration else { return [] }
            if let response {
                responses.append((entry.plugin, response))
            }
        }
        return responses
    }

    private func entry(matching idOrName: String) -> LoadedPlugin? {
        loaded[idOrName.lowercased()] ?? loaded.values.first {
            $0.plugin.name.caseInsensitiveCompare(idOrName) == .orderedSame
        }
    }
}

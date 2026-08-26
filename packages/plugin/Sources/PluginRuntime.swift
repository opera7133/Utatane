import Foundation

public protocol PluginTransport: Sendable {
    func request(_ request: PluginRequest) async throws -> PluginResponse
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

    public init() {}

    @discardableResult
    public func reload(
        _ plugins: [InstalledPlugin],
        transportFactory: TransportFactory
    ) -> [PluginLoadFailure] {
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

    public func unloadAll() {
        loaded.removeAll()
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
        return try await entry.transport.request(PluginRequest(
            method: method,
            id: event,
            charset: entry.plugin.charset,
            sender: sender,
            references: references
        ))
    }

    public func secondChangeResponses() async -> [(InstalledPlugin, PluginResponse)] {
        var responses: [(InstalledPlugin, PluginResponse)] = []
        for key in loaded.keys.sorted() {
            guard var entry = loaded[key] else { continue }
            guard entry.plugin.secondChangeInterval > 0 else { continue }
            entry.secondsUntilTick -= 1
            if entry.secondsUntilTick <= 0 {
                entry.secondsUntilTick = entry.plugin.secondChangeInterval
                if let response = try? await entry.transport.request(PluginRequest(
                    method: "GET",
                    id: "OnSecondChange",
                    charset: entry.plugin.charset
                )) {
                    responses.append((entry.plugin, response))
                }
            }
            loaded[key] = entry
        }
        return responses
    }

    public func broadcast(
        method: String = "GET",
        event: String,
        sender: String? = nil,
        references: [Int: String] = [:]
    ) async -> [(InstalledPlugin, PluginResponse)] {
        var responses: [(InstalledPlugin, PluginResponse)] = []
        for key in loaded.keys.sorted() {
            guard let entry = loaded[key],
                  let response = try? await entry.transport.request(PluginRequest(
                      method: method,
                      id: event,
                      charset: entry.plugin.charset,
                      sender: sender,
                      references: references
                  ))
            else { continue }
            responses.append((entry.plugin, response))
        }
        return responses
    }

    private func entry(matching idOrName: String) -> LoadedPlugin? {
        loaded[idOrName.lowercased()] ?? loaded.values.first {
            $0.plugin.name.caseInsensitiveCompare(idOrName) == .orderedSame
        }
    }
}

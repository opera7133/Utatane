#if canImport(Darwin)
    import Foundation
    import UtataneModuleHost

    public typealias DynamicLibraryModuleSession = UtataneModuleHost.DynamicLibraryModuleSession
    public typealias DynamicLibraryModuleError = UtataneModuleHost.DynamicLibraryModuleError

    public final class DynamicLibraryPluginTransport: PluginTransport, @unchecked Sendable {
        private let session: NativeShioriSession

        public init(plugin: InstalledPlugin, stateDirectoryURL: URL? = nil,
                    moduleResolver: UtataneModuleResolver = .init()) throws
        {
            guard case let .dynamicLibrary(moduleURL) = plugin.runtime else {
                throw DynamicLibraryModuleError.loadFailed(plugin.moduleURL, "dynamic libraryではありません")
            }
            let state = try stateDirectoryURL.map { try PluginStateStore(directoryURL: $0).prepareMisakaState(for: plugin) }
            session = try NativeShioriSession(directoryURL: plugin.directory, moduleURL: moduleURL,
                                              variableStoreURL: state, moduleResolver: moduleResolver)
        }

        public func request(_ request: PluginRequest) async throws -> PluginResponse {
            try await PluginResponse.parse(session.requestAsync(request.serialized()))
        }

        public func shutdown() async {
            do { try await session.closeAsync() }
            catch { NSLog("Plugin save failed: %@", error.localizedDescription) }
        }
    }
#endif

#if canImport(Darwin)
    import Foundation
    import UtataneModuleHost
    import UtataneNativeSaori

    public typealias DynamicLibraryModuleSession = UtataneModuleHost.DynamicLibraryModuleSession
    public typealias DynamicLibraryModuleError = UtataneModuleHost.DynamicLibraryModuleError

    public final class DynamicLibraryPluginTransport: PluginTransport, @unchecked Sendable {
        private let session: NativeShioriSession

        public init(plugin: InstalledPlugin, stateDirectoryURL: URL? = nil,
                    moduleURLOverride: URL? = nil,
                    saoriCaller: (any NativeSaoriCalling)? = nil,
                    saoriRootURL: URL? = nil,
                    moduleResolver: UtataneModuleResolver = .init()) throws
        {
            let moduleURL: URL
            if let moduleURLOverride {
                moduleURL = moduleURLOverride
            } else if case let .dynamicLibrary(url) = plugin.runtime {
                moduleURL = url
            } else {
                throw DynamicLibraryModuleError.loadFailed(plugin.moduleURL, "dynamic libraryではありません")
            }
            let state = stateDirectoryURL.map { PluginStateStore(directoryURL: $0).stateDirectoryURL(for: plugin) }
            session = try NativeShioriSession(directoryURL: plugin.directory, moduleURL: moduleURL,
                                              stateDirectoryURL: state, saoriCaller: saoriCaller,
                                              saoriRootURL: saoriRootURL,
                                              moduleResolver: moduleResolver)
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

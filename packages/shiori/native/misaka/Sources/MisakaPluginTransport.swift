import Foundation
import UtataneModuleHost
import UtataneNativeSaori
import UtatanePlugin

public actor MisakaPluginTransport: PluginTransport {
    private let session: MisakaEngineSession

    public init(plugin: InstalledPlugin, stateDirectoryURL: URL,
                moduleResolver: UtataneModuleResolver = .init(),
                saoriCaller: (any NativeSaoriCalling)? = nil) throws
    {
        let state = try PluginStateStore(directoryURL: stateDirectoryURL).prepareMisakaState(for: plugin)
        session = try MisakaEngineSession(
            masterDirectoryURL: plugin.directory, variableStoreURL: state,
            saoriCaller: saoriCaller, moduleResolver: moduleResolver
        )
    }

    public func request(_ request: PluginRequest) async throws -> PluginResponse {
        try PluginResponse(session.request(request.shioriRequest))
    }

    public func shutdown() async {
        do { try session.close() }
        catch { NSLog("MISAKA plugin save failed: %@", error.localizedDescription) }
    }
}

import Foundation
import UtatanePOSIXShiori

/// KAGARI exposes an instance-based ABI, not the conventional request/load exports.
public actor KagariPluginTransport: PluginTransport {
    private var session: POSIXShioriSession?

    public init(plugin: InstalledPlugin, moduleURLOverride: URL? = nil,
                resolver: POSIXShioriModuleResolver = .init()) throws
    {
        if let moduleURLOverride {
            session = try POSIXShioriSession(masterDirectoryURL: plugin.directory, moduleURL: moduleURLOverride, kind: .kagari)
        } else {
            session = try resolver.loadSession(for: .kagari, masterDirectoryURL: plugin.directory)
        }
    }

    public func request(_ request: PluginRequest) async throws -> PluginResponse {
        guard let session else { throw POSIXShioriError.requestFailed }
        return try PluginResponse.parse(session.request(request.serialized()))
    }

    public func shutdown() async {
        session?.close()
        session = nil
    }
}

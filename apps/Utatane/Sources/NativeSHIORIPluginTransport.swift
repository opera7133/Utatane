import Foundation
import UtatanePlugin
import UtataneWindowsShiori

enum NativeSHIORIPluginError: LocalizedError {
    case unsupportedRuntime

    var errorDescription: String? {
        "ネイティブSHIORIとして読み込めないプラグインです。"
    }
}

actor WindowsDLLPluginTransport: PluginTransport {
    private let session: WindowsDLLModuleProcessSession

    init(configuration: WindowsDLLModuleProcessConfiguration) throws {
        session = try WindowsDLLModuleProcessSession(configuration: configuration)
    }

    func request(_ request: PluginRequest) async throws -> PluginResponse {
        try PluginResponse.parse(session.request(request.serialized()))
    }
}

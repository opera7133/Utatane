import Foundation
import UtataneAkariNative
import UtataneCore
import UtataneKawariNative
import UtataneMisakaNative
import UtatanePlugin
import UtataneRuntime
import UtataneSatoriNative
import UtataneShiori
import UtataneWindowsShiori
import UtataneYayaNative

actor NativeSHIORIPluginTransport: PluginTransport {
    private enum Backend: Sendable {
        case akari(NativeAkariPersonalityEngine)
        case kawari(NativeKawariSession)
        case misaka(NativeMisakaSession)
        case satori(NativeSatoriSession)
        case yaya(NativeYayaSession)
    }

    private let backend: Backend

    init(plugin: InstalledPlugin) throws {
        guard case let .nativeSHIORI(kind) = plugin.runtime else {
            throw NativeSHIORIPluginError.unsupportedRuntime
        }
        backend = switch kind {
        case .akari: try .akari(NativeAkariPersonalityEngine(masterDirectoryURL: plugin.directory))
        case .kawari: try .kawari(NativeKawariSession(masterDirectoryURL: plugin.directory))
        case .misaka: try .misaka(NativeMisakaSession(masterDirectoryURL: plugin.directory))
        case .satori: try .satori(NativeSatoriSession(masterDirectoryURL: plugin.directory))
        case .yaya: try .yaya(NativeYayaSession(masterDirectoryURL: plugin.directory))
        }
    }

    func request(_ request: PluginRequest) async throws -> PluginResponse {
        switch backend {
        case let .akari(engine):
            try await PluginResponse(engine.pluginResponse(for: request.shioriRequest))
        case let .kawari(session):
            try PluginResponse.parse(session.request(request.serialized()))
        case let .misaka(session):
            try PluginResponse(session.request(request.shioriRequest))
        case let .satori(session):
            try PluginResponse.parse(session.request(request.serialized()))
        case let .yaya(session):
            try PluginResponse.parse(session.request(request.serialized()))
        }
    }
}

enum NativeSHIORIPluginError: LocalizedError {
    case unsupportedRuntime

    var errorDescription: String? {
        "ネイティブSHIORIとして読み込めないプラグインです。"
    }
}

actor WindowsDLLPluginTransport: PluginTransport {
    private let session: WindowsPluginDLLProcessSession

    init(configuration: WindowsPluginDLLProcessConfiguration) throws {
        session = try WindowsPluginDLLProcessSession(configuration: configuration)
    }

    func request(_ request: PluginRequest) async throws -> PluginResponse {
        try PluginResponse.parse(session.request(request.serialized()))
    }
}

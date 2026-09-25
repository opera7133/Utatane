import Foundation
import UtataneAkariNative
import UtataneCore
import UtataneKawariNative
import UtataneMisakaNative
import UtataneModuleHost
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
        case misaka(MisakaPluginTransport)
        case satori(NativeSatoriSession)
        case yaya(NativeYayaSession)
    }

    private let backend: Backend

    init(plugin: InstalledPlugin, stateDirectoryURL: URL, allowsShioriFallback: Bool = true) throws {
        guard case let .nativeSHIORI(kind) = plugin.runtime else {
            throw NativeSHIORIPluginError.unsupportedRuntime
        }
        backend = switch kind {
        case .akari: try .akari(NativeAkariPersonalityEngine(masterDirectoryURL: plugin.directory))
        case .kawari: try .kawari(NativeKawariSession(masterDirectoryURL: plugin.directory))
        case .misaka: try .misaka(MisakaPluginTransport(plugin: plugin, stateDirectoryURL: stateDirectoryURL,
                                                        moduleResolver: .init(allowsFallback: allowsShioriFallback)))
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
            try await session.request(request)
        case let .satori(session):
            try PluginResponse.parse(session.request(request.serialized()))
        case let .yaya(session):
            try PluginResponse.parse(session.request(request.serialized()))
        }
    }

    func shutdown() async {
        if case let .misaka(session) = backend {
            await session.shutdown()
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
    private let session: WindowsDLLModuleProcessSession

    init(configuration: WindowsDLLModuleProcessConfiguration) throws {
        session = try WindowsDLLModuleProcessSession(configuration: configuration)
    }

    func request(_ request: PluginRequest) async throws -> PluginResponse {
        try PluginResponse.parse(session.request(request.serialized()))
    }
}

import Foundation
import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

/// Shared session selection for ghosts and plugins.
public final class MisakaEngineSession: @unchecked Sendable {
    private enum Backend {
        case builtin(NativeMisakaSession)
        case module(UtataneModuleSession)
    }

    private let lock = NSLock()
    private var backend: Backend?

    public init(
        masterDirectoryURL: URL,
        variableStoreURL: URL? = nil,
        saoriCaller: (any NativeSaoriCalling)? = nil,
        moduleResolver: UtataneModuleResolver = .init()
    ) throws {
        let caller = saoriCaller ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        if let moduleURL = try moduleResolver.misakaModuleURL() {
            guard let variableStoreURL else {
                throw UtataneModuleError.invalidConfiguration("An external MISAKA module requires a state path")
            }
            backend = try .module(UtataneModuleSession(
                moduleURL: moduleURL, masterDirectoryURL: masterDirectoryURL,
                variableStoreURL: variableStoreURL, saoriCaller: caller
            ))
        } else {
            backend = try .builtin(NativeMisakaSession(
                masterDirectoryURL: masterDirectoryURL,
                variableStoreURL: variableStoreURL,
                saoriCaller: caller
            ))
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        guard lock.try() else { throw UtataneModuleError.busy }
        defer { lock.unlock() }
        guard let backend else { throw UtataneModuleError.closed }
        guard ["SHIORI/3.0", "PLUGIN/2.0"].contains(request.version) else {
            throw UtataneModuleError.invalidConfiguration("Unsupported request protocol")
        }
        switch backend {
        case let .module(session): return try session.request(request)
        case let .builtin(session):
            let result = try session.request(request)
            return ShioriResponse(version: request.version, statusCode: result.statusCode,
                                  reasonPhrase: result.reasonPhrase, headers: result.headers)
        }
    }

    public func close() throws {
        guard lock.try() else { throw UtataneModuleError.busy }
        defer { lock.unlock() }
        switch backend {
        case let .builtin(session): try session.save()
        case let .module(session): try session.close()
        case nil: return
        }
        backend = nil
    }
}

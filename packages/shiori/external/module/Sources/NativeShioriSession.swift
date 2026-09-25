import Foundation
import UtataneNativeSaori
import UtataneShiori

/// Native SHIORI loading used by ghosts and plugins. SAORI loading stays in its caller's process.
public final class NativeShioriSession: Sendable {
    private enum Backend: Sendable {
        case bridge(DynamicLibraryModuleSession)
        case process(NativeShioriProcessSession)
    }

    private let backend: Backend
    private let queue = DispatchQueue(label: "dev.utatane.native-shiori")

    public init(directoryURL: URL, moduleURL: URL,
                stateDirectoryURL: URL? = nil,
                saoriCaller: (any NativeSaoriCalling)? = nil,
                saoriRootURL: URL? = nil,
                moduleResolver: UtataneModuleResolver = .init(),
                hostURL: URL = NativeShioriProcessSession.defaultHostURL) throws
    {
        if let stateDirectoryURL, UtataneModuleImage.usesModuleBridge(moduleURL) {
            backend = try .bridge(DynamicLibraryModuleSession.open(
                directoryURL: directoryURL,
                moduleURL: moduleURL,
                variableStoreURL: stateDirectoryURL.appending(path: "module-state.json"),
                saoriCaller: saoriCaller,
                moduleResolver: moduleResolver
            ))
        } else {
            let kind = ConventionalShioriKind(libraryFilename: moduleURL.lastPathComponent)
            var environment: [String: String] = [:]
            if let stateDirectoryURL {
                environment["UTATANE_GHOST_STATE_DIR"] = stateDirectoryURL.path
            }
            if let saoriRootURL {
                environment["UTATANE_SAORI_ROOT"] = saoriRootURL.path
            }
            backend = try .process(ShioriModuleRecovery.load(
                preferred: moduleURL,
                fallback: kind.flatMap {
                    try moduleResolver.fallbackURL(for: $0, selected: moduleURL, masterDirectoryURL: directoryURL)
                },
                canRecover: { ($0 as? NativeShioriProcessError)?.canRecoverByLoadingAnotherModule == true }
            ) { url in
                try NativeShioriProcessSession(
                    directoryURL: directoryURL, moduleURL: url, hostURL: hostURL,
                    additionalEnvironment: environment
                )
            })
        }
    }

    public func request(_ message: String) throws -> String {
        switch backend {
        case let .bridge(session): try session.request(message)
        case let .process(session): try session.request(message)
        }
    }

    public func close() throws {
        switch backend {
        case let .bridge(session): try session.close()
        case let .process(session): try session.close()
        }
    }

    public func requestAsync(_ message: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.request(message) })
            }
        }
    }

    public func closeAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { try self.close() })
            }
        }
    }
}

import Foundation
import UtataneCore
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

    public convenience init(directoryURL: URL, selectedModule: GhostShioriSelection,
                            stateDirectoryURL: URL? = nil,
                            saoriCaller: (any NativeSaoriCalling)? = nil,
                            saoriRootURL: URL? = nil,
                            onInternalSaoriEvent: (@Sendable (InternalSaoriEvent) -> Void)? = nil,
                            internalSaoriMediaReader: (any InternalSaoriMediaReading)? = nil,
                            hostURL: URL = NativeShioriProcessSession.defaultHostURL) throws
    {
        try self.init(directoryURL: directoryURL, moduleURL: selectedModule.validatedModuleURL(),
                      selectedKind: selectedModule.kind, stateDirectoryURL: stateDirectoryURL,
                      saoriCaller: saoriCaller, saoriRootURL: saoriRootURL,
                      moduleResolver: .init(environment: [:], allowsFallback: false),
                      onInternalSaoriEvent: onInternalSaoriEvent, internalSaoriMediaReader: internalSaoriMediaReader,
                      hostURL: hostURL)
    }

    public convenience init(directoryURL: URL, moduleURL: URL,
                            stateDirectoryURL: URL? = nil,
                            saoriCaller: (any NativeSaoriCalling)? = nil,
                            saoriRootURL: URL? = nil,
                            moduleResolver: UtataneModuleResolver = .init(),
                            hostURL: URL = NativeShioriProcessSession.defaultHostURL) throws
    {
        try self.init(directoryURL: directoryURL, moduleURL: moduleURL, stateDirectoryURL: stateDirectoryURL,
                      saoriCaller: saoriCaller, saoriRootURL: saoriRootURL, moduleResolver: moduleResolver,
                      onInternalSaoriEvent: nil, hostURL: hostURL)
    }

    public convenience init(directoryURL: URL, moduleURL: URL,
                            stateDirectoryURL: URL? = nil,
                            saoriCaller: (any NativeSaoriCalling)? = nil,
                            saoriRootURL: URL? = nil,
                            moduleResolver: UtataneModuleResolver = .init(),
                            saoriDiagnostics: SaoriDiagnostics = .shared,
                            onInternalSaoriEvent: (@Sendable (InternalSaoriEvent) -> Void)?,
                            internalSaoriMediaReader: (any InternalSaoriMediaReading)? = nil,
                            hostURL: URL = NativeShioriProcessSession.defaultHostURL) throws
    {
        try self.init(directoryURL: directoryURL, moduleURL: moduleURL, selectedKind: nil,
                      stateDirectoryURL: stateDirectoryURL, saoriCaller: saoriCaller, saoriRootURL: saoriRootURL,
                      moduleResolver: moduleResolver, saoriDiagnostics: saoriDiagnostics,
                      onInternalSaoriEvent: onInternalSaoriEvent, internalSaoriMediaReader: internalSaoriMediaReader,
                      hostURL: hostURL)
    }

    public init(directoryURL: URL, moduleURL: URL, selectedKind: ConventionalShioriKind?,
                stateDirectoryURL: URL? = nil,
                saoriCaller: (any NativeSaoriCalling)? = nil,
                saoriRootURL: URL? = nil,
                moduleResolver: UtataneModuleResolver = .init(),
                saoriDiagnostics: SaoriDiagnostics = .shared,
                onInternalSaoriEvent: (@Sendable (InternalSaoriEvent) -> Void)? = nil,
                internalSaoriMediaReader: (any InternalSaoriMediaReading)? = nil,
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
            let kind = selectedKind ?? ConventionalShioriKind(libraryFilename: moduleURL.lastPathComponent)
                ?? ShioriCatalog.identify(masterDirectory: directoryURL, declaredModuleFilename: moduleURL.lastPathComponent)
                .flatMap { $0.id.rawValue == "dnproxy" ? .dnproxy : nil }
            if kind == .yaya6 {
                try YayaSaveBackup.prepare(in: directoryURL)
            }
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
                var selectedEnvironment = environment
                var startupTimeout: TimeInterval = 30
                if kind == .dnproxy {
                    let diagnostic = DNProxyPreflight().inspect(directoryURL: directoryURL, moduleURL: url)
                    guard diagnostic.status == .ready else { throw diagnostic }
                    selectedEnvironment["UTATANE_DOTNET"] = diagnostic.dotnetURL?.path
                    startupTimeout = diagnostic.requiresSDK ? 135 : 30
                }
                return try NativeShioriProcessSession(
                    directoryURL: directoryURL, moduleURL: url, diagnostics: saoriDiagnostics, hostURL: hostURL,
                    startupTimeout: startupTimeout,
                    internalSaoriMediaReader: internalSaoriMediaReader,
                    onInternalSaoriEvent: onInternalSaoriEvent,
                    additionalEnvironment: selectedEnvironment
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
        try await requestAsync(message, propertyReader: nil)
    }

    public func requestAsync(_ message: String, propertyReader: NativeShioriPropertyReader?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    switch self.backend {
                    case let .bridge(session): try session.request(message)
                    case let .process(session): try session.request(message, propertyReader: propertyReader)
                    }
                })
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

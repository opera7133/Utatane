import Foundation
import UtataneNetwork

public enum ModuleCatalogInstallError: Error, Equatable {
    case unavailable
    case unsupportedPlatform
    case unsupportedKind
}

/// Connects a signed HTTP catalog to Utatane's shared SHIORI and SAORI directories.
public struct ModuleCatalogManager: Sendable {
    public let client: SignedModuleCatalogClient
    public let applicationSupportURL: URL
    public let architecture: String
    public let macOSVersion: OperatingSystemVersion

    public init(
        client: SignedModuleCatalogClient,
        applicationSupportURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane"),
        architecture: String = {
            #if arch(arm64)
                "arm64"
            #else
                "x86_64"
            #endif
        }(),
        macOSVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) {
        self.client = client
        self.applicationSupportURL = applicationSupportURL
        self.architecture = architecture
        self.macOSVersion = macOSVersion
    }

    @discardableResult
    public func install(moduleID: String, session: URLSession = .shared) async throws -> URL {
        let catalog = try await client.fetch(session: session)
        guard let module = catalog.modules.first(where: { $0.id == moduleID && $0.availability == "candidate" }) else {
            throw ModuleCatalogInstallError.unavailable
        }
        let rootName: String
        if module.kinds.contains("shiori") {
            rootName = "NativeShiori"
        } else if module.kinds == ["saori"] {
            rootName = "NativeSaori"
        } else {
            throw ModuleCatalogInstallError.unsupportedKind
        }
        let candidates = module.artifacts.enumerated().filter { _, artifact in
            artifact.architectures.contains(architecture) && supported(artifact.minimumOS)
        }
        guard let selected = candidates.max(by: { lhs, rhs in
            versionKey(lhs.element).lexicographicallyPrecedes(versionKey(rhs.element))
        }) else { throw ModuleCatalogInstallError.unsupportedPlatform }

        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appending(path: "utatane-module-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: temporary) }
        let archive = temporary.appending(path: "module.zip")
        try await client.downloadArtifact(
            moduleID: moduleID,
            artifactIndex: selected.offset,
            catalog: catalog,
            to: archive,
            session: session
        )
        let root = applicationSupportURL.appending(path: rootName)
        return try ModulePackageInstaller().install(
            archiveURL: archive,
            module: module,
            artifact: selected.element,
            managedRootURL: root
        )
    }

    private func supported(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".")
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return false }
        return (macOSVersion.majorVersion, macOSVersion.minorVersion) >= (major, minor)
    }

    private func versionKey(_ artifact: SignedModuleCatalog.Module.Artifact) -> [Int] {
        let parts = artifact.version.split(separator: ".").map { Int($0) ?? 0 }
        return parts + Array(repeating: 0, count: max(0, 3 - parts.count)) + [artifact.revision]
    }
}

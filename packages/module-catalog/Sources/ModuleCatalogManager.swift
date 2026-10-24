import Foundation
import UtataneNetwork

public enum ModuleCatalogInstallError: Error, Equatable {
    case unavailable
    case unsupportedPlatform
    case unsupportedKind
}

public struct ModuleBatchInstallFailure: Error {
    public let moduleID: String
    public let underlying: any Error
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

    /// Reuse one verified catalog for the whole batch. Completed modules stay
    /// installed after a failure, and retries skip their verified manifests.
    @discardableResult
    public func install(moduleIDs: [String], catalog: SignedModuleCatalog, session: URLSession = .shared) async throws -> [URL] {
        let inventory = ModuleCatalogInventory(applicationSupportURL: applicationSupportURL, architecture: architecture, macOSVersion: macOSVersion)
        let plan = ModuleInstallPlan(moduleIDs: moduleIDs, catalog: catalog, inventory: inventory)
        if let first = plan.unavailable.first {
            throw ModuleBatchInstallFailure(moduleID: first.id, underlying: first.reason == .unsupportedPlatform
                ? ModuleCatalogInstallError.unsupportedPlatform : ModuleCatalogInstallError.unavailable)
        }
        var installed: [URL] = []
        for id in plan.moduleIDs {
            try Task.checkCancellation()
            do { try await installed.append(install(moduleID: id, catalog: catalog, session: session)) }
            catch { throw ModuleBatchInstallFailure(moduleID: id, underlying: error) }
        }
        return installed
    }

    @discardableResult
    public func install(moduleID: String, session: URLSession = .shared) async throws -> URL {
        let catalog = try await client.fetch(session: session)
        return try await install(moduleID: moduleID, catalog: catalog, session: session)
    }

    @discardableResult
    public func install(moduleID: String, catalog: SignedModuleCatalog, session: URLSession = .shared) async throws -> URL {
        try Task.checkCancellation()
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
        let inventory = ModuleCatalogInventory(
            applicationSupportURL: applicationSupportURL, architecture: architecture, macOSVersion: macOSVersion
        )
        guard let selected = inventory.artifact(for: module) else { throw ModuleCatalogInstallError.unsupportedPlatform }

        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appending(path: "utatane-module-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: temporary) }
        let archive = temporary.appending(path: "module.zip")
        try await client.downloadArtifact(
            moduleID: moduleID,
            artifactIndex: selected.index,
            catalog: catalog,
            to: archive,
            session: session
        )
        try Task.checkCancellation()
        let root = applicationSupportURL.appending(path: rootName)
        return try ModulePackageInstaller().install(
            archiveURL: archive,
            module: module,
            artifact: selected.value,
            managedRootURL: root
        )
    }
}

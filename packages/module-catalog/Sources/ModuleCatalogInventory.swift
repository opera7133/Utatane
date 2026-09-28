import Foundation
import UtataneNetwork

public enum ModuleCatalogState: Equatable, Sendable {
    case unavailable
    case unsupportedPlatform
    case notInstalled
    case current
    case updateAvailable
}

private struct InstalledModuleManifest: Decodable {
    let schemaVersion: Int
    let id: String
    let version: String
    let revision: Int
    let abi: String
    let minimumOS: String
    let architectures: [String]
    let files: [String: String]
}

/// Uses the same platform selection for installation, setup, and catalog labels.
public struct ModuleCatalogInventory: Sendable {
    public let applicationSupportURL: URL
    public let architecture: String
    public let macOSVersion: OperatingSystemVersion

    public init(
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
        self.applicationSupportURL = applicationSupportURL
        self.architecture = architecture
        self.macOSVersion = macOSVersion
    }

    public func artifact(for module: SignedModuleCatalog.Module) -> (index: Int, value: SignedModuleCatalog.Module.Artifact)? {
        module.artifacts.enumerated()
            .filter { $0.element.architectures.contains(architecture) && supports($0.element.minimumOS) }
            .max { versionKey($0.element).lexicographicallyPrecedes(versionKey($1.element)) }
            .map { ($0.offset, $0.element) }
    }

    public func state(for module: SignedModuleCatalog.Module) -> ModuleCatalogState {
        guard module.availability == "candidate" else { return .unavailable }
        guard module.kinds.contains("shiori") || module.kinds == ["saori"] else { return .unavailable }
        let installed = installedManifest(moduleID: module.id, kind: module.kinds.contains("shiori") ? "shiori" : "saori")
        guard let selected = artifact(for: module)?.value else {
            return installed == nil ? .unsupportedPlatform : .current
        }
        guard let installed else { return .notInstalled }
        if installed.abi == selected.abi {
            let localVersion = versionKey(installed.version, revision: installed.revision)
            let catalogVersion = versionKey(selected.version, revision: selected.revision)
            if !localVersion.lexicographicallyPrecedes(catalogVersion) {
                return .current
            }
        }
        return .updateAvailable
    }

    public func isInstalled(moduleID: String, kind: String) -> Bool {
        installedManifest(moduleID: moduleID, kind: kind) != nil
    }

    public var hasRequiredInitialModules: Bool {
        isInstalled(moduleID: "yaya", kind: "shiori") && isInstalled(moduleID: "satori", kind: "shiori")
    }

    private func installedManifest(moduleID: String, kind: String) -> InstalledModuleManifest? {
        guard kind == "shiori" || kind == "saori" else { return nil }
        let root = applicationSupportURL
            .appending(path: kind == "shiori" ? "NativeShiori" : "NativeSaori")
            .appending(path: moduleID)
        guard let data = try? Data(contentsOf: root.appending(path: "module.json")),
              let manifest = try? JSONDecoder().decode(InstalledModuleManifest.self, from: data),
              manifest.schemaVersion == 1, manifest.id == moduleID,
              manifest.architectures.contains(architecture), supports(manifest.minimumOS),
              manifest.files.keys.contains(where: { path in
                  path.split(separator: "/").count == 2 && path.hasPrefix("lib/") && path.hasSuffix(".dylib")
                      && FileManager.default.fileExists(atPath: root.appending(path: path).path)
              })
        else { return nil }
        return manifest
    }

    private func supports(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".")
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return false }
        return (macOSVersion.majorVersion, macOSVersion.minorVersion) >= (major, minor)
    }

    private func versionKey(_ artifact: SignedModuleCatalog.Module.Artifact) -> [Int] {
        versionKey(artifact.version, revision: artifact.revision)
    }

    private func versionKey(_ version: String, revision: Int) -> [Int] {
        let parts: [Int]
        if version.hasPrefix("Tc") {
            let fields = version.dropFirst(2).split(separator: "-")
            if fields.count == 2, fields[0].count == 3,
               let code = Int(fields[0]), let patch = Int(fields[1])
            {
                parts = [code / 100, code % 100, patch]
            } else {
                parts = [0]
            }
        } else {
            parts = version.split(separator: ".").map { Int($0) ?? 0 }
        }
        return parts + Array(repeating: 0, count: max(0, 3 - parts.count)) + [revision]
    }
}

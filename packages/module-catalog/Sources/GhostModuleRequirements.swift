import Foundation
import UtataneCore
import UtataneNetwork

public struct GhostModuleRequirement: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let kind: String
    public let sourceDLLURL: URL?
}

/// Finds catalog modules needed by a newly installed ghost without changing its files.
public struct GhostModuleRequirements: Sendable {
    public init() {}

    /// Finds DLLs that still need a native module or an explicitly configured Windows host.
    /// This works without a network catalog, so a failed fetch cannot silently start a new ghost.
    public func unresolved(
        for ghost: InstalledGhost, applicationSupportURL: URL, catalog: SignedModuleCatalog? = nil
    ) -> [GhostModuleRequirement] {
        let master = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
        let declaredURL = safeDeclaredURL(ghost.effectiveShioriFilename, in: master)
        let descriptor = ShioriCatalog.identify(
            masterDirectory: master,
            declaredModuleFilename: ghost.shioriFilename,
            macOSModuleFilename: ghost.shioriMacOSFilename
        )
        var result: [GhostModuleRequirement] = []
        if !hasMacOSOverride(ghost, master: master), descriptor?.provisioning != .included,
           descriptor?.execution != .externalProcess,
           let declaredURL, declaredURL.pathExtension.lowercased() == "dll"
        {
            let yayaID: String? = if descriptor?.id.rawValue == "yaya" {
                "yaya-6"
            } else {
                nil
            }
            let catalogModule = catalog?.modules.first(where: { module in
                module.kinds.contains("shiori")
                    && (yayaID.map { module.id == $0 }
                        ?? (windowsFilenames(for: module).contains(declaredURL.lastPathComponent.lowercased())
                            || module.id == descriptor?.id.rawValue))
            })
            let id = yayaID ?? catalogModule?.id ?? (descriptor?.id.rawValue == "misaka" ? "misaka-native"
                : (descriptor?.id.rawValue ?? declaredURL.deletingPathExtension().lastPathComponent.lowercased()))
            if !localLibraryExists(beside: declaredURL, moduleID: id),
               !managedLibraryExists(moduleID: id, kind: "shiori", root: applicationSupportURL)
            {
                result.append(GhostModuleRequirement(
                    id: id, displayName: catalogModule?.displayName ?? descriptor?.displayName ?? declaredURL.lastPathComponent,
                    kind: "SHIORI", sourceDLLURL: FileManager.default.fileExists(atPath: declaredURL.path) ? declaredURL : nil
                ))
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: master, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }
        var seen = Set<String>()
        for case let dll as URL in enumerator where dll.pathExtension.lowercased() == "dll" {
            let stem = dll.deletingPathExtension().lastPathComponent.lowercased()
            let catalogModule = catalog?.modules.first(where: { module in
                module.kinds.contains("saori") && windowsFilenames(for: module).contains(dll.lastPathComponent.lowercased())
            })
            let moduleID = catalogModule?.id ?? (stem == "saori_cpuid" ? "saori-cpuid" : stem)
            let knownSAORI = ["saori_cpuid", "kenonoke", "textcopy2", "mciaudior", "wmove"].contains(stem)
            guard dll.standardizedFileURL != declaredURL?.standardizedFileURL,
                  (try? dll.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  knownSAORI || catalogModule != nil,
                  seen.insert(dll.lastPathComponent.lowercased()).inserted,
                  !localLibraryExists(beside: dll, moduleID: moduleID),
                  !managedLibraryExists(moduleID: moduleID, kind: "saori", root: applicationSupportURL)
            else { continue }
            result.append(GhostModuleRequirement(
                id: moduleID,
                displayName: dll.lastPathComponent, kind: "SAORI", sourceDLLURL: dll
            ))
        }
        return result
    }

    public func missing(
        for ghost: InstalledGhost,
        in catalog: SignedModuleCatalog,
        applicationSupportURL: URL
    ) -> [GhostModuleRequirement] {
        let inventory = ModuleCatalogInventory(applicationSupportURL: applicationSupportURL)
        var seen = Set<String>()
        return unresolved(for: ghost, applicationSupportURL: applicationSupportURL, catalog: catalog).compactMap { requirement in
            guard let module = catalog.modules.first(where: { module in
                module.availability == "candidate" && module.kinds.contains(requirement.kind.lowercased())
                    && (requirement.kind == "SHIORI" && ["yaya", "yaya-6"].contains(requirement.id)
                        ? module.id == requirement.id
                        : (module.id == requirement.id || requirement.sourceDLLURL.map { dll in
                            windowsFilenames(for: module).contains(dll.lastPathComponent.lowercased())
                        } == true))
            }), seen.insert(module.id).inserted,
            inventory.artifact(for: module) != nil,
            !inventory.isInstalled(moduleID: module.id, kind: requirement.kind.lowercased()),
            requirement.sourceDLLURL.map({ !localLibraryExists(beside: $0, moduleID: module.id) }) ?? true
            else { return nil }
            return GhostModuleRequirement(
                id: module.id, displayName: module.displayName, kind: requirement.kind,
                sourceDLLURL: requirement.sourceDLLURL
            )
        }
    }

    private func hasMacOSOverride(_ ghost: InstalledGhost, master: URL) -> Bool {
        guard let filename = ghost.shioriMacOSFilename,
              let candidate = safeDeclaredURL(filename, in: master),
              ["dylib", "so", "bundle"].contains(candidate.pathExtension.lowercased())
        else { return false }
        return FileManager.default.fileExists(atPath: candidate.path)
    }

    private func safeDeclaredURL(_ filename: String, in master: URL) -> URL? {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        let candidate = master.appending(path: normalized).standardizedFileURL
        return candidate.path.hasPrefix(master.standardizedFileURL.path + "/") ? candidate : nil
    }

    private func localLibraryExists(beside declared: URL, moduleID: String) -> Bool {
        let stem = declared.deletingPathExtension().lastPathComponent
        let directory = declared.deletingLastPathComponent()
        let names = moduleID == "yaya-6" ? ["libyaya-6.dylib"]
            : ["\(stem).dylib", "lib\(stem).dylib", "lib\(moduleID).dylib"]
        return names.contains { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }

    private func managedLibraryExists(moduleID: String, kind: String, root: URL) -> Bool {
        ModuleCatalogInventory(applicationSupportURL: root).isInstalled(moduleID: moduleID, kind: kind)
    }

    private func windowsFilenames(for module: SignedModuleCatalog.Module) -> Set<String> {
        if !module.windowsFilenames.isEmpty {
            return Set(module.windowsFilenames.map { $0.lowercased() })
        }
        switch module.id {
        case "yaya": return ["yaya.dll", "aya.dll", "aya5.dll"]
        case "misaka-native": return ["misaka.dll"]
        case "nise-shiori": return ["niseshiori.dll"]
        case "saori-cpuid": return ["saori_cpuid.dll"]
        default: return ["\(module.id).dll"]
        }
    }
}

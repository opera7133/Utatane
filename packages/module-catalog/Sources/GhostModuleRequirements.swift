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

    public func missing(
        for ghost: InstalledGhost,
        in catalog: SignedModuleCatalog,
        applicationSupportURL: URL
    ) -> [GhostModuleRequirement] {
        let master = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
        var result: [GhostModuleRequirement] = []
        let declaredURL = safeDeclaredURL(ghost.effectiveShioriFilename, in: master)
        if let module = shioriModule(for: ghost, master: master, catalog: catalog),
           !hasMacOSOverride(ghost, master: master),
           !(declaredURL.map { localLibraryExists(beside: $0, moduleID: module.id) } ?? false),
           !managedLibraryExists(moduleID: module.id, kind: "shiori", root: applicationSupportURL)
        {
            result.append(GhostModuleRequirement(
                id: module.id, displayName: module.displayName, kind: "SHIORI",
                sourceDLLURL: declaredURL.flatMap {
                    FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
                }
            ))
        }

        guard let enumerator = FileManager.default.enumerator(
            at: master, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }
        var seen = Set(result.map(\.id))
        for case let dll as URL in enumerator where dll.pathExtension.lowercased() == "dll" {
            guard (try? dll.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let module = catalog.modules.first(where: {
                      $0.availability == "candidate" && $0.kinds.contains("saori")
                          && windowsFilenames(for: $0).contains(dll.lastPathComponent.lowercased())
                  }), seen.insert(module.id).inserted,
                  !localLibraryExists(beside: dll, moduleID: module.id),
                  !managedLibraryExists(moduleID: module.id, kind: "saori", root: applicationSupportURL)
            else { continue }
            result.append(GhostModuleRequirement(
                id: module.id, displayName: module.displayName, kind: "SAORI", sourceDLLURL: dll
            ))
        }
        return result
    }

    private func shioriModule(
        for ghost: InstalledGhost, master: URL, catalog: SignedModuleCatalog
    ) -> SignedModuleCatalog.Module? {
        let declared = URL(filePath: ghost.effectiveShioriFilename).lastPathComponent.lowercased()
        let detected = ShioriCatalog.identify(
            masterDirectory: master,
            declaredModuleFilename: ghost.shioriFilename,
            macOSModuleFilename: ghost.shioriMacOSFilename
        )?.id.rawValue
        let detectedModuleID = detected == "misaka" ? "misaka-native" : detected
        return catalog.modules.first {
            $0.availability == "candidate" && $0.kinds.contains("shiori")
                && (windowsFilenames(for: $0).contains(declared) || $0.id == detectedModuleID)
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
        let names = ["\(stem).dylib", "lib\(stem).dylib", "lib\(moduleID).dylib"]
        return names.contains { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }

    private func managedLibraryExists(moduleID: String, kind: String, root: URL) -> Bool {
        let directory = root.appending(path: kind == "shiori" ? "NativeShiori" : "NativeSaori")
            .appending(path: moduleID)
        guard FileManager.default.fileExists(atPath: directory.appending(path: "module.json").path),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory.appending(path: "lib"), includingPropertiesForKeys: nil
              )
        else { return false }
        return files.contains { $0.pathExtension.lowercased() == "dylib" }
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

import Foundation

/// File layout shared by runtime selection and the missing-module check.
/// Finding a library does not assert a version or validate its executable code.
public enum NativeShioriLibraryLocator {
    public static func candidates(
        moduleID: String?, masterDirectory: URL? = nil, declaredFilename: String? = nil,
        nativeRoot: URL? = nil, bundledResources: URL? = nil
    ) -> [URL] {
        if let moduleID, !isModuleID(moduleID) {
            return []
        }
        let libraryStem = switch moduleID {
        case "misaka-native": "misaka"
        case "nise-shiori": "niseshiori"
        default: moduleID
        }
        let canonical = libraryStem.map { stem in ["lib\(stem)", stem] } ?? []
        let extensions = ["dylib", "so", "bundle"]
        func names(_ stems: [String]) -> [String] {
            stems.flatMap { stem in extensions.map { "\(stem).\($0)" } }
        }
        var urls: [URL] = []
        if let masterDirectory {
            var directories: [URL] = []
            var declaredStems: [String] = []
            if let declaredFilename, let declared = declaredURL(declaredFilename, in: masterDirectory) {
                directories.append(declared.deletingLastPathComponent())
                let stem = declared.deletingPathExtension().lastPathComponent
                // aya.dll and yaya.dll still select YAYA 6, never libyaya.dylib.
                if moduleID != "yaya-6" {
                    declaredStems = [stem, "lib\(stem)"]
                }
            }
            directories.append(masterDirectory)
            for directory in directories {
                urls += names(canonical + declaredStems + ["shiori"]).map { directory.appending(path: $0) }
            }
            if let moduleID {
                urls += names(canonical + ["shiori"]).map { masterDirectory.appending(path: "\(moduleID)/lib/\($0)") }
            }
        }
        if let moduleID {
            for root in [nativeRoot, bundledResources?.appending(path: "NativeShiori")].compactMap(\.self) {
                for folder in ["\(moduleID)/lib", moduleID] {
                    urls += names(canonical).map { root.appending(path: "\(folder)/\($0)") }
                }
            }
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    public static func firstExisting(in candidates: [URL]) -> URL? {
        candidates.first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
        }
    }

    public static func declaredURL(_ filename: String, in master: URL) -> URL? {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !normalized.contains("\0") else { return nil }
        let candidate = master.appending(path: normalized).standardizedFileURL
        return candidate.path.hasPrefix(master.standardizedFileURL.path + "/") ? candidate : nil
    }

    private static func isModuleID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

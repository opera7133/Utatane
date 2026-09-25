import Foundation

public struct UtataneModuleResolver: Sendable {
    private let applicationSupportURL: URL
    private let bundledResourcesURL: URL?
    private let environment: [String: String]
    private let allowsFallback: Bool

    public init(
        applicationSupportURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/NativeShiori"),
        bundledResourcesURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsFallback: Bool = true
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.bundledResourcesURL = bundledResourcesURL
        self.environment = environment
        self.allowsFallback = allowsFallback
    }

    public func misakaModuleURL(masterDirectoryURL: URL? = nil) throws -> URL? {
        if let override = environment["UTATANE_MISAKA_MODULE"] {
            guard override.hasPrefix("/"), !override.contains("\0") else {
                throw UtataneModuleError.invalidConfiguration("UTATANE_MISAKA_MODULE must be an absolute path")
            }
            // Preserve explicit configuration errors instead of silently using a different engine.
            return URL(fileURLWithPath: override)
        }
        if let masterDirectoryURL {
            for name in ["libmisaka.dylib", "misaka-native/lib/libmisaka.dylib"] {
                let file = masterDirectoryURL.appending(path: name)
                if FileManager.default.fileExists(atPath: file.path) {
                    return file
                }
            }
        }
        var roots = [applicationSupportURL]
        if let bundledResourcesURL {
            roots.append(bundledResourcesURL.appending(path: "NativeShiori"))
        }
        return roots.map { $0.appending(path: "misaka-native/lib/libmisaka.dylib") }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    public func misakaFallbackURL(for selected: URL, masterDirectoryURL: URL) throws -> URL? {
        guard allowsFallback, environment["UTATANE_MISAKA_MODULE"] == nil,
              selected.standardizedFileURL.path.hasPrefix(masterDirectoryURL.standardizedFileURL.path + "/")
        else { return nil }
        return try misakaModuleURL()
    }

    public func moduleURL(for kind: ConventionalShioriKind, masterDirectoryURL: URL? = nil) throws -> URL? {
        if kind == .misaka {
            return try misakaModuleURL(masterDirectoryURL: masterDirectoryURL)
        }
        let key = "UTATANE_\(kind.rawValue.uppercased().replacingOccurrences(of: "-", with: "_"))_MODULE"
        if let path = environment[key] {
            guard path.hasPrefix("/"), !path.contains("\0") else {
                throw UtataneModuleError.invalidConfiguration("\(key) must be an absolute path")
            }
            return URL(fileURLWithPath: path)
        }
        var directories: [URL] = []
        if let masterDirectoryURL {
            directories += [masterDirectoryURL, masterDirectoryURL.appending(path: "\(kind.rawValue)/lib")]
        }
        directories.append(applicationSupportURL.appending(path: "\(kind.rawValue)/lib"))
        if let bundledResourcesURL {
            directories.append(bundledResourcesURL.appending(path: "NativeShiori/\(kind.rawValue)/lib"))
        }
        return directories.map { $0.appending(path: kind.libraryFilename) }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    public func fallbackURL(for kind: ConventionalShioriKind, selected: URL, masterDirectoryURL: URL) throws -> URL? {
        if kind == .misaka {
            return try misakaFallbackURL(for: selected, masterDirectoryURL: masterDirectoryURL)
        }
        guard allowsFallback, environment["UTATANE_\(kind.rawValue.uppercased().replacingOccurrences(of: "-", with: "_"))_MODULE"] == nil,
              selected.standardizedFileURL.path.hasPrefix(masterDirectoryURL.standardizedFileURL.path + "/")
        else { return nil }
        return try moduleURL(for: kind)
    }
}

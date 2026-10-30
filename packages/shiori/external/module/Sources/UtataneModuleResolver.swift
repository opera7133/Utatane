import Foundation
import UtataneCore

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
        try moduleURL(for: .misaka, masterDirectoryURL: masterDirectoryURL)
    }

    public func misakaFallbackURL(for selected: URL, masterDirectoryURL: URL) throws -> URL? {
        guard allowsFallback, environment["UTATANE_MISAKA_MODULE"] == nil,
              selected.standardizedFileURL.path.hasPrefix(masterDirectoryURL.standardizedFileURL.path + "/")
        else { return nil }
        return try misakaModuleURL()
    }

    public func moduleURL(for kind: ConventionalShioriKind, masterDirectoryURL: URL? = nil) throws -> URL? {
        try moduleURL(for: kind, masterDirectoryURL: masterDirectoryURL, declaredModuleFilename: nil)
    }

    public func moduleURL(for kind: ConventionalShioriKind, masterDirectoryURL: URL?, declaredModuleFilename: String?) throws -> URL? {
        let key = "UTATANE_\(kind.rawValue.uppercased().replacingOccurrences(of: "-", with: "_"))_MODULE"
        if let path = environment[key] {
            guard path.hasPrefix("/"), !path.contains("\0") else {
                throw UtataneModuleError.invalidConfiguration("\(key) must be an absolute path")
            }
            return URL(fileURLWithPath: path)
        }
        return NativeShioriLibraryLocator.firstExisting(in: NativeShioriLibraryLocator.candidates(
            moduleID: kind == .misaka ? "misaka-native" : kind.rawValue, masterDirectory: masterDirectoryURL, declaredFilename: declaredModuleFilename,
            nativeRoot: applicationSupportURL, bundledResources: bundledResourcesURL
        ))
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

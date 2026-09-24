import Foundation

public struct UtataneModuleResolver: Sendable {
    private let applicationSupportURL: URL
    private let bundledResourcesURL: URL?
    private let environment: [String: String]

    public init(
        applicationSupportURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/NativeShiori"),
        bundledResourcesURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.bundledResourcesURL = bundledResourcesURL
        self.environment = environment
    }

    public func misakaModuleURL() throws -> URL? {
        if let override = environment["UTATANE_MISAKA_MODULE"] {
            guard override.hasPrefix("/"), !override.contains("\0") else {
                throw UtataneModuleError.invalidConfiguration("UTATANE_MISAKA_MODULE must be an absolute path")
            }
            // Preserve explicit configuration errors instead of silently using a different engine.
            return URL(fileURLWithPath: override)
        }
        var roots = [applicationSupportURL]
        if let bundledResourcesURL {
            roots.append(bundledResourcesURL.appending(path: "NativeShiori"))
        }
        return roots.map { $0.appending(path: "misaka-native/lib/libUtataneMisaka.dylib") }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}

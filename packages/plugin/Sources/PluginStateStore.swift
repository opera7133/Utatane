import Foundation

public struct PluginStateStore: Sendable {
    private let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func stateDirectoryURL(for plugin: InstalledPlugin) -> URL {
        // Catalog IDs are case-insensitive and can contain path separators.
        let key = plugin.id.lowercased().utf8.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appending(path: key, directoryHint: .isDirectory)
    }
}

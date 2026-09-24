import Foundation

public struct PluginStateStore: Sendable {
    private let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func misakaVariableStoreURL(for plugin: InstalledPlugin) -> URL {
        // Catalog IDs are case-insensitive and can contain path separators.
        let key = plugin.id.lowercased().utf8.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appending(path: key).appending(path: "misaka-vars.json")
    }

    /// Import the older in-plugin state once, preserving both the original and existing external state.
    public func prepareMisakaState(for plugin: InstalledPlugin) throws -> URL {
        let state = misakaVariableStoreURL(for: plugin)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: state.path) else { return state }
        let legacy = plugin.directory.appending(path: "misaka_vars.json").resolvingSymlinksInPath()
        guard manager.fileExists(atPath: legacy.path) else { return state }
        guard try legacy.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        try manager.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: legacy, to: state)
        return state
    }
}

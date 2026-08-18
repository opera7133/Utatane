import Foundation

/// A ghost package installed on disk. A running ghost is represented separately by the runtime.
public struct InstalledGhost: Identifiable, Sendable, Equatable {
    public let name: String
    public let rootDirectory: URL
    public let defaultShellDirectory: URL

    public var id: URL {
        rootDirectory
    }

    public init(name: String, rootDirectory: URL, defaultShellDirectory: URL) {
        self.name = name
        self.rootDirectory = rootDirectory
        self.defaultShellDirectory = defaultShellDirectory
    }
}

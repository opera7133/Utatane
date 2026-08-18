import Foundation
import UtataneCore
import UtataneRuntime

public struct FileSystemGhostRepository: GhostRepository {
    private let rootDirectory: URL
    private let packageLoader = GhostPackageLoader()

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func installedGhosts() async throws -> [InstalledGhost] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }

        return try FileManager.default
            .contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .map { try packageLoader.loadGhost(at: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

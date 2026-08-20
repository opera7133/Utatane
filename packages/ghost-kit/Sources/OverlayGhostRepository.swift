import UtataneCore
import UtataneRuntime

public struct OverlayGhostRepository: GhostRepository {
    private let repositories: [any GhostRepository]

    public init(repositories: [any GhostRepository]) {
        self.repositories = repositories
    }

    public func installedGhosts() async throws -> [InstalledGhost] {
        var seenDirectoryNames = Set<String>()
        var ghosts: [InstalledGhost] = []
        for repository in repositories {
            for ghost in try await repository.installedGhosts() {
                guard seenDirectoryNames.insert(ghost.rootDirectory.lastPathComponent).inserted else { continue }
                ghosts.append(ghost)
            }
        }
        return ghosts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

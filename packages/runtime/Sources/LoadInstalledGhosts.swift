import UtataneCore

public struct LoadInstalledGhosts: Sendable {
    private let repository: any GhostRepository

    public init(repository: any GhostRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> [InstalledGhost] {
        try await repository.installedGhosts()
    }
}

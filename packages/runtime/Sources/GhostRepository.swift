import UtataneCore

public protocol GhostRepository: Sendable {
    func installedGhosts() async throws -> [InstalledGhost]
}

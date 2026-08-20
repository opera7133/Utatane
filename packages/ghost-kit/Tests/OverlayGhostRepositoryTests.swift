import Foundation
import Testing
import UtataneCore
@testable import UtataneGhostKit
import UtataneRuntime

private struct StubOverlayRepository: GhostRepository {
    let ghosts: [InstalledGhost]

    func installedGhosts() async throws -> [InstalledGhost] {
        ghosts
    }
}

@Test func `overlay repository keeps the first ghost with each directory name`() async throws {
    let bundled = InstalledGhost(
        name: "Bundled Ria",
        rootDirectory: URL(filePath: "/Bundled/Ghosts/ria"),
        defaultShellDirectory: URL(filePath: "/Bundled/Ghosts/ria/shell/master")
    )
    let localDuplicate = InstalledGhost(
        name: "Local Ria",
        rootDirectory: URL(filePath: "/Local/Ghosts/ria"),
        defaultShellDirectory: URL(filePath: "/Local/Ghosts/ria/shell/master")
    )
    let localOnly = InstalledGhost(
        name: "Emily",
        rootDirectory: URL(filePath: "/Local/Ghosts/emily4"),
        defaultShellDirectory: URL(filePath: "/Local/Ghosts/emily4/shell/master")
    )
    let repository = OverlayGhostRepository(repositories: [
        StubOverlayRepository(ghosts: [bundled]),
        StubOverlayRepository(ghosts: [localDuplicate, localOnly])
    ])

    let ghosts = try await repository.installedGhosts()
    #expect(ghosts.map(\.name) == ["Bundled Ria", "Emily"])
}

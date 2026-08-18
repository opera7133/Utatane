import Foundation
import Testing
import UtataneCore
@testable import UtataneRuntime

private struct StubGhostRepository: GhostRepository {
    let result: [InstalledGhost]

    func installedGhosts() async throws -> [InstalledGhost] {
        result
    }
}

@Test
func `load installed ghosts returns repository result`() async throws {
    let rootDirectory = URL(filePath: "/ghost/sakura")
    let expected = [
        InstalledGhost(
            name: "Sakura",
            rootDirectory: rootDirectory,
            defaultShellDirectory: rootDirectory.appending(path: "shell/master", directoryHint: .isDirectory)
        )
    ]
    let useCase = LoadInstalledGhosts(repository: StubGhostRepository(result: expected))

    let actual = try await useCase()

    #expect(actual == expected)
}

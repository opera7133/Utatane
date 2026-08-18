import Foundation
import Testing
@testable import UtataneCore

@Test
func `installed ghost identity is its directory`() {
    let directory = URL(filePath: "/tmp/ghost/named-sakura")
    let shellDirectory = directory.appending(path: "shell/master", directoryHint: .isDirectory)
    let ghost = InstalledGhost(
        name: "named-sakura",
        rootDirectory: directory,
        defaultShellDirectory: shellDirectory
    )

    #expect(ghost.id == directory)
}

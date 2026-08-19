import Foundation
import Testing
import UtataneCore
@testable import UtataneGhostKit

@Test
func `loads and names every installed shell with master as default`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let master = root.appending(path: "shell/master", directoryHint: .isDirectory)
    let alternate = root.appending(path: "shell/alternate", directoryHint: .isDirectory)
    let ghostMaster = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    for directory in [master, alternate, ghostMaster] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("""
    name,Test Ghost
    sakura.name,Emily
    sakura.seriko.defaultsurface,1
    sakura.balloon.defaultsurface,2
    kero.name,Teddy
    kero.seriko.defaultsurface,11
    char2.name,Charlie
    char2.seriko.defaultsurface,200
    char2.balloon.defaultsurface,3
    """.utf8).write(
        to: ghostMaster.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("name,Default Shell\n".utf8).write(
        to: master.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("name,Alternate Shell\n".utf8).write(
        to: alternate.appending(path: "descript.txt", directoryHint: .notDirectory)
    )

    let ghost = try GhostPackageLoader().loadGhost(at: root)

    #expect(ghost.name == "Test Ghost")
    #expect(ghost.defaultShellDirectory.standardizedFileURL == master.standardizedFileURL)
    #expect(ghost.shells.map(\.name) == ["Default Shell", "Alternate Shell"])
    #expect(ghost.characters == [
        InstalledGhostCharacter(
            scope: 0,
            name: "Emily",
            defaultSurfaceID: 1,
            defaultBalloonSurfaceID: 2
        ),
        InstalledGhostCharacter(scope: 1, name: "Teddy", defaultSurfaceID: 11),
        InstalledGhostCharacter(
            scope: 2,
            name: "Charlie",
            defaultSurfaceID: 200,
            defaultBalloonSurfaceID: 3
        )
    ])
}

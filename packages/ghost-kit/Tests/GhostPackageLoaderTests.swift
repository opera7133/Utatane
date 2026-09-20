import Foundation
import Testing
import UtataneCore
@testable import UtataneGhostKit

@Test(arguments: ["libexample.dylib", "modules/example.so", "example.bundle", "shiolink.dll", ""])
func `selects an explicit macOS SHIORI without requiring the Windows DLL`(override: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let shell = root.appending(path: "shell/master")
    for directory in [master, shell] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("name,Shared Ghost\nshiori,example.dll\nshiori.macos,\(override)\n".utf8)
        .write(to: master.appending(path: "descript.txt"))
    try Data("shiori,legacy.dll\n".utf8).write(to: master.appending(path: "alias.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    let ghost = try GhostPackageLoader().loadGhost(at: root)
    #expect(ghost.shioriMacOSFilename == (override.isEmpty ? nil : override))
    #if os(macOS)
        #expect(ghost.shioriFilename == (override.isEmpty ? "example.dll" : override))
    #else
        #expect(ghost.shioriFilename == "example.dll")
    #endif
}

@Test
func `macOS SHIORI overrides an alias declaration and works without a common declaration`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let shell = root.appending(path: "shell/master")
    for directory in [master, shell] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("name,Mac Ghost\nshiori.macos,libexample.dylib\n".utf8)
        .write(to: master.appending(path: "descript.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    #if os(macOS)
        #expect(try GhostPackageLoader().loadGhost(at: root).shioriFilename == "libexample.dylib")
        try Data("shiori,legacy.dll\n".utf8).write(to: master.appending(path: "alias.txt"))
        #expect(try GhostPackageLoader().loadGhost(at: root).shioriFilename == "libexample.dylib")
    #endif
}

@Test
func `omitted SHIORI resolves to the traditional shiori dll default`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let shell = root.appending(path: "shell/master")
    for directory in [master, shell] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("name,Default SHIORI Ghost\n".utf8).write(to: master.appending(path: "descript.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))

    let ghost = try GhostPackageLoader().loadGhost(at: root)
    #expect(ghost.shioriFilename == nil)
    #expect(ghost.effectiveShioriFilename == "shiori.dll")
}

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
    charset,EUC-KR
    shiori,first.dll
    balloon,test-balloon
    sakura.name,Emily
    sakura.name2,Em
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
    try Data("""
    name,Default Shell
    sakura.name,Emily in Default
    sakura.name2,Em in Default
    kero.name,Teddy in Default
    """.utf8).write(
        to: master.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("name,Alternate Shell\n".utf8).write(
        to: alternate.appending(path: "descript.txt", directoryHint: .notDirectory)
    )

    let ghost = try GhostPackageLoader().loadGhost(at: root)

    #expect(ghost.name == "Test Ghost")
    #expect(ghost.defaultShellDirectory.standardizedFileURL == master.standardizedFileURL)
    #expect(ghost.shells.map(\.name) == ["Default Shell", "Alternate Shell"])
    #expect(ghost.characterName(for: 0, shell: ghost.shells[0]) == "Emily in Default")
    #expect(ghost.characterName(for: 1, shell: ghost.shells[0]) == "Teddy in Default")
    #expect(ghost.secondaryCharacterName(shell: ghost.shells[0]) == "Em in Default")
    #expect(ghost.shioriFilename == "first.dll")
    #expect(ghost.charset == "EUC-KR")
    #expect(ghost.defaultBalloonDirectoryName == "test-balloon")
    #expect(ghost.characters == [
        InstalledGhostCharacter(
            scope: 0,
            name: "Emily",
            secondaryName: "Em",
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

@Test
func `loads a legacy SHIORI declaration from alias txt`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let shell = root.appending(path: "shell/master", directoryHint: .isDirectory)
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    for directory in [shell, master] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("name,Legacy Ghost\n".utf8).write(to: master.appending(path: "descript.txt"))
    try Data("""
    shiori,niseshiori.dll
    sakura.surface.alias
    {
    normal,[0]
    }
    """.utf8).write(to: master.appending(path: "alias.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))

    let ghost = try GhostPackageLoader().loadGhost(at: root)

    #expect(ghost.shioriFilename == "niseshiori.dll")
}

@Test func `loads the installed mixed encoding Korean ghost`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(
        path: "Content/Local/Ghosts/nisesakura_rebirth2_008",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: root.path) else { return }

    let ghost = try GhostPackageLoader().loadGhost(at: root)

    #expect(ghost.name == "Nisesakura Rebirth2")
    #expect(ghost.charset == "EUC-KR")
    #expect(ghost.shioriFilename == "ese-shiori.dll")
    #expect(ghost.characters[0].name == "さくら")
    #expect(ghost.characters[1].name == "우뉴")
    #expect(ghost.shells.map(\.name).contains("사쿠라100%"))
}

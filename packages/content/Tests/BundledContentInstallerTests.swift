import Foundation
import Testing
@testable import UtataneContent

@Test func `installs bundled ghosts and balloons without overwriting existing content`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "utatane-bundled-content-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let bundled = root.appending(path: "Bundled", directoryHint: .isDirectory)
    let installedGhosts = root.appending(path: "Installed/Ghosts", directoryHint: .isDirectory)
    let installedBalloons = root.appending(path: "Installed/Balloons", directoryHint: .isDirectory)
    let bundledGhost = bundled.appending(path: "Ghosts/ria", directoryHint: .isDirectory)
    let bundledBalloon = bundled.appending(path: "Balloons/ria", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: bundledGhost, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: bundledBalloon, withIntermediateDirectories: true)
    try Data("bundled ghost".utf8).write(to: bundledGhost.appending(path: "content.txt"))
    try Data("bundled balloon".utf8).write(to: bundledBalloon.appending(path: "content.txt"))

    let installer = BundledContentInstaller()
    try installer.install(
        from: bundled,
        ghostsDirectory: installedGhosts,
        balloonsDirectory: installedBalloons
    )
    try Data("user edit".utf8).write(
        to: installedGhosts.appending(path: "ria/content.txt"),
        options: .atomic
    )
    try installer.install(
        from: bundled,
        ghostsDirectory: installedGhosts,
        balloonsDirectory: installedBalloons
    )

    #expect(try String(
        contentsOf: installedGhosts.appending(path: "ria/content.txt"),
        encoding: .utf8
    ) == "user edit")
    #expect(try String(
        contentsOf: installedBalloons.appending(path: "ria/content.txt"),
        encoding: .utf8
    ) == "bundled balloon")
}

@Test func `adds bundled homeurl without replacing existing content`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "utatane-bundled-homeurl-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let bundled = root.appending(path: "Bundled", directoryHint: .isDirectory)
    let installedGhosts = root.appending(path: "Installed/Ghosts", directoryHint: .isDirectory)
    let installedBalloons = root.appending(path: "Installed/Balloons", directoryHint: .isDirectory)
    let bundledGhostMaster = bundled.appending(path: "Ghosts/ria/ghost/master", directoryHint: .isDirectory)
    let bundledBalloon = bundled.appending(path: "Balloons/ria", directoryHint: .isDirectory)
    let installedGhostMaster = installedGhosts.appending(path: "ria/ghost/master", directoryHint: .isDirectory)
    let installedBalloon = installedBalloons.appending(path: "ria", directoryHint: .isDirectory)
    for directory in [bundledGhostMaster, bundledBalloon, installedGhostMaster, installedBalloon] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("name,りあ\nhomeurl,https://example.test/ria/\n".utf8).write(
        to: bundledGhostMaster.appending(path: "descript.txt")
    )
    try Data("name,Ria\nhomeurl,https://example.test/balloon-ria/\n".utf8).write(
        to: bundledBalloon.appending(path: "descript.txt")
    )
    try Data("name,利用者が変更したりあ\n".utf8).write(
        to: installedGhostMaster.appending(path: "descript.txt")
    )
    try Data("name,利用者が変更したバルーン\n".utf8).write(
        to: installedBalloon.appending(path: "descript.txt")
    )

    try BundledContentInstaller().install(
        from: bundled,
        ghostsDirectory: installedGhosts,
        balloonsDirectory: installedBalloons
    )

    let installedGhostDescriptor = try String(
        contentsOf: installedGhostMaster.appending(path: "descript.txt"),
        encoding: .utf8
    )
    let installedBalloonDescriptor = try String(
        contentsOf: installedBalloon.appending(path: "descript.txt"),
        encoding: .utf8
    )
    #expect(installedGhostDescriptor == "name,利用者が変更したりあ\nhomeurl,https://example.test/ria/\n")
    #expect(installedBalloonDescriptor == "name,利用者が変更したバルーン\nhomeurl,https://example.test/balloon-ria/\n")
}

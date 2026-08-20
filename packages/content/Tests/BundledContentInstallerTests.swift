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

import Foundation
import Testing
@testable import UtataneContent

@Test
func `rejects traversal absolute and backslash archive entries`() throws {
    let installer = NarInstaller()

    for entry in ["../outside", "/absolute", "folder\\file", "folder/./file"] {
        #expect(throws: NarInstallError.self) {
            try installer.validate(entries: [entry])
        }
    }
    try installer.validate(entries: ["ghost/master/descript.txt", "shell/master/"])
}

@Test
func `reads install metadata for creation event references`() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-install.txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("name,Test Ghost\ntype,ghost\nballoon.directory,test-balloon\n".utf8).write(to: url)

    let metadata = try NarInstaller().readInstallMetadata(from: url)

    #expect(metadata["name"] == "Test Ghost")
    #expect(metadata["type"] == "ghost")
    #expect(metadata["balloon.directory"] == "test-balloon")
}

@Test
func `installs a balloon NAR into the balloon root`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("type,balloon\nname,Test\ndirectory,test-balloon\n".utf8).write(
        to: package.appending(path: "install.txt", directoryHint: .notDirectory)
    )
    try Data("type,balloon\nname,Test\n".utf8).write(
        to: package.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    let destination = fixture.roots.balloonsDirectory.appending(
        path: "test-balloon",
        directoryHint: .isDirectory
    )
    #expect(result == NarInstallResult(
        primaryType: .balloon,
        items: [NarInstalledItem(type: .balloon, name: "Test", url: destination)]
    ))
    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "descript.txt").path))
}

@Test
func `installs a headline NAR into the headline root`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("type,headline\nname,Test News\ndirectory,test-news\n".utf8).write(
        to: package.appending(path: "install.txt")
    )
    try Data("type,rss\nname,Test News\nfeed,https://example.test/feed.xml\n".utf8).write(
        to: package.appending(path: "descript.txt")
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)
    let destination = fixture.roots.headlinesDirectory.appending(path: "test-news", directoryHint: .isDirectory)
    #expect(result.items == [NarInstalledItem(type: .headline, name: "Test News", url: destination)])
    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "descript.txt").path))
}

@Test
func `installs plugin and calendar NAR types into dedicated roots`() throws {
    for (rawType, expectedType, folder) in [
        ("plugin", NarContentType.plugin, "Plugins"),
        ("calendar skin", NarContentType.calendarSkin, "Calendar/Skins"),
        ("calendar plugin", NarContentType.calendarPlugin, "Calendar/Plugins"),
        ("calendar", NarContentType.calendarSkin, "Calendar/Skins")
    ] {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("type,\(rawType)\nname,Test\ndirectory,item\n".utf8).write(
            to: fixture.source.appending(path: "install.txt")
        )
        try Data("payload".utf8).write(to: fixture.source.appending(path: "data.txt"))
        let archive = try makeArchive(from: fixture.source, at: fixture.root)

        let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)
        let destination = fixture.roots.ghostsDirectory.deletingLastPathComponent()
            .appending(path: "\(folder)/item", directoryHint: .isDirectory)
        #expect(result.primaryType == expectedType)
        #expect(result.items == [NarInstalledItem(type: expectedType, name: "Test", url: destination)])
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "data.txt").path))
    }
}

@Test
func `honors install accept and reports a missing target`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("type,shell\nname,Target Shell\ndirectory,target-shell\naccept,Target Ghost\n".utf8).write(
        to: package.appending(path: "install.txt")
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    #expect(throws: NarInstallError.refused(
        accept: "Target Ghost",
        type: "shell",
        name: "Target Shell"
    )) {
        try NarInstaller().install(
            archiveURL: archive,
            roots: fixture.roots,
            selectedGhostDirectory: fixture.root.appending(path: "wrong-ghost")
        )
    }

    let target = fixture.root.appending(path: "target-ghost", directoryHint: .isDirectory)
    let result = try NarInstaller().install(
        archiveURL: archive,
        roots: fixture.roots,
        selectedGhostDirectory: fixture.root.appending(path: "wrong-ghost"),
        activeGhostDirectories: ["Target Ghost": target]
    )
    #expect(result.acceptedGhostName == "Target Ghost")
    #expect(result.items.first?.url == target.appending(path: "shell/target-shell", directoryHint: .isDirectory))
}

@Test
func `installs a ghost and its numbered bundled objects together`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    let ghostMaster = package.appending(path: "ghost/master", directoryHint: .isDirectory)
    let balloon = package.appending(path: "balloon", directoryHint: .isDirectory)
    let secondBalloon = package.appending(path: "balloon-extra", directoryHint: .isDirectory)
    let headline = package.appending(path: "headline", directoryHint: .isDirectory)
    let plugin = package.appending(path: "plugin", directoryHint: .isDirectory)
    let calendarSkin = package.appending(path: "calendar-skin", directoryHint: .isDirectory)
    let calendarPlugin = package.appending(path: "calendar-plugin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghostMaster, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: balloon, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondBalloon, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: headline, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: calendarSkin, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: calendarPlugin, withIntermediateDirectories: true)
    try Data((
        "type,ghost\ndirectory,test-ghost\nballoon.directory,test-balloon\nballoon.source.directory,balloon\n" +
            "balloon1.directory,test-balloon-extra\nballoon1.source.directory,balloon-extra\n" +
            "headline.directory,test-headline\nheadline.source.directory,headline\n" +
            "plugin.directory,test-plugin\nplugin.source.directory,plugin\n" +
            "calendar.skin.directory,test-calendar-skin\ncalendar.skin.source.directory,calendar-skin\n" +
            "calendar.plugin.directory,test-calendar-plugin\ncalendar.plugin.source.directory,calendar-plugin\n"
    ).utf8).write(to: package.appending(path: "install.txt", directoryHint: .notDirectory))
    try Data("type,ghost\nname,Test Ghost\n".utf8).write(
        to: ghostMaster.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("type,balloon\nname,Test Balloon\n".utf8).write(
        to: balloon.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("type,balloon\nname,Extra Balloon\n".utf8).write(
        to: secondBalloon.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("name,Test Headline\n".utf8).write(
        to: headline.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .ghost)
    #expect(result.installedURLs.count == 7)
    #expect(result.items.map(\.type) == [
        .ghost, .balloon, .balloon, .calendarPlugin, .calendarSkin, .headline, .plugin
    ])
    #expect(FileManager.default.fileExists(atPath: fixture.roots.ghostsDirectory
            .appending(path: "test-ghost/ghost/master/descript.txt").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.balloonsDirectory
            .appending(path: "test-balloon/descript.txt").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.balloonsDirectory
            .appending(path: "test-balloon-extra/descript.txt").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.headlinesDirectory
            .appending(path: "test-headline/descript.txt").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.pluginsDirectory
            .appending(path: "test-plugin").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.calendarSkinsDirectory
            .appending(path: "test-calendar-skin").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.calendarPluginsDirectory
            .appending(path: "test-calendar-plugin").path))
}

@Test
func `installs a package and exposes its boot ghost`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    let ghost = package.appending(path: "ghost-one", directoryHint: .isDirectory)
    let balloon = package.appending(path: "balloon-one", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghost.appending(path: "ghost/master"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: balloon, withIntermediateDirectories: true)
    try Data("type,package\nname,Test Package\nbootghost,test-ghost\n".utf8).write(
        to: package.appending(path: "install.txt")
    )
    try Data("type,ghost\nname,Test Ghost\ndirectory,test-ghost\n".utf8).write(
        to: ghost.appending(path: "install.txt")
    )
    try Data("name,Test Ghost\n".utf8).write(to: ghost.appending(path: "ghost/master/descript.txt"))
    try Data("type,balloon\nname,Test Balloon\ndirectory,test-balloon\n".utf8).write(
        to: balloon.appending(path: "install.txt")
    )
    try Data("name,Test Balloon\n".utf8).write(to: balloon.appending(path: "descript.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .package)
    #expect(result.bootGhostDirectory == "test-ghost")
    #expect(result.items.map(\.type) == [.balloon, .ghost])
    #expect(FileManager.default.fileExists(atPath: fixture.roots.ghostsDirectory
            .appending(path: "test-ghost/ghost/master/descript.txt").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.balloonsDirectory
            .appending(path: "test-balloon/descript.txt").path))
}

@Test
func `refresh replaces installed content while preserving undelete mask files`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let destination = fixture.roots.balloonsDirectory.appending(path: "test-balloon")
    try FileManager.default.createDirectory(at: destination.appending(path: "state"), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: destination.appending(path: "obsolete.txt"))
    try Data("saved".utf8).write(to: destination.appending(path: "state/savedata.txt"))

    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("type,balloon\nname,Test\ndirectory,test-balloon\nrefresh,1\nrefreshundeletemask,savedata.txt\n".utf8)
        .write(to: package.appending(path: "install.txt"))
    try Data("new".utf8).write(to: package.appending(path: "descript.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    _ = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "obsolete.txt").path))
    #expect(try String(contentsOf: destination.appending(path: "state/savedata.txt"), encoding: .utf8) == "saved")
    #expect(try String(contentsOf: destination.appending(path: "descript.txt"), encoding: .utf8) == "new")
}

@Test
func `rejects a NAR containing a symbolic link before extraction`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("type,balloon\ndirectory,test-balloon\n".utf8).write(
        to: package.appending(path: "install.txt", directoryHint: .notDirectory)
    )
    try FileManager.default.createSymbolicLink(
        at: package.appending(path: "unsafe-link", directoryHint: .notDirectory),
        withDestinationURL: URL(filePath: "/tmp", directoryHint: .isDirectory)
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root, storesSymbolicLinks: true)

    #expect(throws: NarInstallError.self) {
        try NarInstaller().install(archiveURL: archive, roots: fixture.roots)
    }
}

private struct Fixture {
    let root: URL
    let source: URL
    let roots: NarInstallationRoots
}

private func makeFixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let source = root.appending(path: "source", directoryHint: .isDirectory)
    let ghosts = root.appending(path: "installed/Ghosts", directoryHint: .isDirectory)
    let balloons = root.appending(path: "installed/Balloons", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    return Fixture(
        root: root,
        source: source,
        roots: NarInstallationRoots(ghostsDirectory: ghosts, balloonsDirectory: balloons)
    )
}

private func makeArchive(
    from source: URL,
    at root: URL,
    storesSymbolicLinks: Bool = false
) throws -> URL {
    let archive = root.appending(path: "fixture.nar", directoryHint: .notDirectory)
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/zip")
    process.arguments = ["-q", "-r"] + (storesSymbolicLinks ? ["-y"] : []) + [archive.path, "."]
    process.currentDirectoryURL = source
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    return archive
}

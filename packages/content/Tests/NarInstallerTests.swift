import Foundation
import Testing
@testable import UtataneContent
import UtataneCore

@Test
func `accepts Windows separators while rejecting unsafe archive entries`() throws {
    let installer = NarInstaller()

    for entry in ["../outside", "..\\outside", "/absolute", "C:\\absolute", "folder/./file"] {
        #expect(throws: NarInstallError.self) {
            try installer.validate(entries: [entry])
        }
    }
    try installer.validate(entries: ["ghost\\master\\descript.txt", "shell/master/"])
    #expect(throws: NarInstallError.self) {
        try installer.validate(entries: ["ghost/master/descript.txt", "ghost\\master\\descript.txt"])
    }
}

@Test
func `installs a NAR whose ZIP entries use Windows separators`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try Data("type,ghost\nname,Windows Paths\ndirectory,windows-paths\n".utf8).write(
        to: fixture.source.appending(path: "install.txt")
    )
    try Data("name,Windows Paths\n".utf8).write(
        to: fixture.source.appending(path: "ghost\\master\\descript.txt")
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.items.map(\.name) == ["Windows Paths"])
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.ghostsDirectory
            .appending(path: "windows-paths/ghost/master/descript.txt").path
    ))
}

@Test func `installs a ghost whose metadata declares EUC-KR`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "korean-ghost", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: package.appending(path: "ghost/master", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    let encoding = try #require(LegacyTextDecoder.encoding(named: "EUC-KR"))
    let metadata = try #require(
        "charset,EUC-KR\ntype,ghost\nname,니세사쿠라\ndirectory,korean-ghost\n".data(using: encoding)
    )
    try metadata.write(to: package.appending(path: "install.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.items.first?.name == "니세사쿠라")
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.ghostsDirectory.appending(path: "korean-ghost/ghost/master").path
    ))
}

@Test func `installs the archived Korean ghost and preserves its metadata`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = repositoryRoot.appending(
        path: "Content/Local/Ghosts/nisesakura_rebirth2_008",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: source.path) else { return }

    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let archive = fixture.root.appending(path: "nisesakura_rebirth2_008.zip")
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--norsrc", source.path, archive.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .ghost)
    #expect(result.items.first?.name == "니세사쿠라 \"Rebirth\"2")
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.ghostsDirectory
            .appending(path: "nisesakura_r2/ghost/master/ese-shiori.dll").path
    ))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_NAR_SMOKE_PATH"] != nil))
func `installs an externally supplied NAR for release smoke testing`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let archivePath = try #require(ProcessInfo.processInfo.environment["UTATANE_NAR_SMOKE_PATH"])

    let result = try NarInstaller().install(
        archiveURL: URL(filePath: archivePath),
        roots: fixture.roots
    )

    #expect(!result.items.isEmpty)
    for item in result.items {
        #expect(FileManager.default.fileExists(atPath: item.url.path))
    }
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

@Test
func `installs a ZIP ghost without install.txt at the archive root`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ghostMaster = fixture.source.appending(path: "ghost/master", directoryHint: .isDirectory)
    let shellMaster = fixture.source.appending(path: "shell/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghostMaster, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shellMaster, withIntermediateDirectories: true)
    try Data("name,Old Root Ghost\n".utf8).write(
        to: ghostMaster.appending(path: "descript.txt")
    )
    try Data("name,master\n".utf8).write(
        to: shellMaster.appending(path: "descript.txt")
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root, filename: "old_ghost.zip")

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .ghost)
    #expect(result.items.first?.name == "Old Root Ghost")
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.ghostsDirectory.appending(path: "Old Root Ghost/ghost/master/descript.txt").path
    ))
}

@Test
func `does not infer missing install metadata for a NAR`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ghostMaster = fixture.source.appending(path: "ghost/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghostMaster, withIntermediateDirectories: true)
    try Data("name,Not a valid NAR\n".utf8).write(to: ghostMaster.appending(path: "descript.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    #expect(throws: NarInstallError.missingInstallFile) {
        try NarInstaller().install(archiveURL: archive, roots: fixture.roots)
    }
}

@Test
func `installs a ZIP ghost without install.txt in a nested subfolder`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ghostDir = fixture.source.appending(path: "my_ghost", directoryHint: .isDirectory)
    let ghostMaster = ghostDir.appending(path: "ghost/master", directoryHint: .isDirectory)
    let shellMaster = ghostDir.appending(path: "shell/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghostMaster, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shellMaster, withIntermediateDirectories: true)
    try Data("name,Nested Ghost\n".utf8).write(
        to: ghostMaster.appending(path: "descript.txt")
    )
    try Data("name,master\n".utf8).write(
        to: shellMaster.appending(path: "descript.txt")
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root, filename: "nested_ghost.zip")

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .ghost)
    #expect(result.items.first?.name == "Nested Ghost")
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.ghostsDirectory.appending(path: "my_ghost/ghost/master/descript.txt").path
    ))
}

@Test
func `installs a standalone balloon ZIP without install.txt`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let balloonDir = fixture.source.appending(path: "custom_balloon", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: balloonDir, withIntermediateDirectories: true)
    try Data("type,balloon\nname,Custom Balloon\n".utf8).write(
        to: balloonDir.appending(path: "descript.txt")
    )
    try Data("origin".utf8).write(to: balloonDir.appending(path: "origin.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root, filename: "balloon.zip")

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .balloon)
    #expect(result.items.first?.name == "Custom Balloon")
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.balloonsDirectory.appending(path: "custom_balloon/origin.txt").path
    ))
}

@Test
func `installs a standalone shell ZIP without install.txt to selected ghost`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let shellDir = fixture.source.appending(path: "extra_shell", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: shellDir, withIntermediateDirectories: true)
    try Data("type,shell\nname,Extra Shell\n".utf8).write(
        to: shellDir.appending(path: "descript.txt")
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root, filename: "shell.zip")

    let targetGhost = fixture.roots.ghostsDirectory.appending(path: "target_ghost", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: targetGhost.appending(path: "ghost/master"), withIntermediateDirectories: true)

    let result = try NarInstaller().install(
        archiveURL: archive,
        roots: fixture.roots,
        selectedGhostDirectory: targetGhost
    )

    #expect(result.primaryType == .shell)
    #expect(result.items.first?.name == "Extra Shell")
    #expect(FileManager.default.fileExists(
        atPath: targetGhost.appending(path: "shell/extra_shell/descript.txt").path
    ))
}

@Test
func `installs an SSP folder structured ZIP containing multiple contents`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ghostDir = fixture.source.appending(path: "ghost/ssp_ghost/ghost/master", directoryHint: .isDirectory)
    let balloonDir = fixture.source.appending(path: "balloon/ssp_balloon", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghostDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: balloonDir, withIntermediateDirectories: true)
    try Data("name,SSP Ghost\n".utf8).write(to: ghostDir.appending(path: "descript.txt"))
    try Data("type,balloon\nname,SSP Balloon\n".utf8).write(to: balloonDir.appending(path: "descript.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root, filename: "ssp_bundle.zip")

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .package)
    #expect(result.items.count == 2)
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.ghostsDirectory.appending(path: "ssp_ghost/ghost/master/descript.txt").path
    ))
    #expect(FileManager.default.fileExists(
        atPath: fixture.roots.balloonsDirectory.appending(path: "ssp_balloon/descript.txt").path
    ))
}

@Test
func `rejects an arbitrary zip file without supported ghost or balloon content`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try Data("random contents".utf8).write(to: fixture.source.appending(path: "hello.txt"))
    let archive = try makeArchive(from: fixture.source, at: fixture.root, filename: "arbitrary.zip")

    #expect(throws: NarInstallError.missingInstallFile) {
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
    filename: String = "fixture.nar",
    storesSymbolicLinks: Bool = false
) throws -> URL {
    let archive = root.appending(path: filename, directoryHint: .notDirectory)
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

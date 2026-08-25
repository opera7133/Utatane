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
func `installs a ghost and its bundled balloon together`() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let package = fixture.source.appending(path: "package", directoryHint: .isDirectory)
    let ghostMaster = package.appending(path: "ghost/master", directoryHint: .isDirectory)
    let balloon = package.appending(path: "balloon", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ghostMaster, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: balloon, withIntermediateDirectories: true)
    try Data(
        "type,ghost\ndirectory,test-ghost\nballoon.directory,test-balloon\nballoon.source.directory,balloon\n".utf8
    ).write(to: package.appending(path: "install.txt", directoryHint: .notDirectory))
    try Data("type,ghost\nname,Test Ghost\n".utf8).write(
        to: ghostMaster.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    try Data("type,balloon\nname,Test Balloon\n".utf8).write(
        to: balloon.appending(path: "descript.txt", directoryHint: .notDirectory)
    )
    let archive = try makeArchive(from: fixture.source, at: fixture.root)

    let result = try NarInstaller().install(archiveURL: archive, roots: fixture.roots)

    #expect(result.primaryType == .ghost)
    #expect(result.installedURLs.count == 2)
    #expect(result.items.map(\.type) == [.ghost, .balloon])
    #expect(result.items.map(\.name) == ["test-ghost", "test-balloon"])
    #expect(FileManager.default.fileExists(atPath: fixture.roots.ghostsDirectory
            .appending(path: "test-ghost/ghost/master/descript.txt").path))
    #expect(FileManager.default.fileExists(atPath: fixture.roots.balloonsDirectory
            .appending(path: "test-balloon/descript.txt").path))
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

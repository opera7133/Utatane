import Foundation
import Testing
@testable import UtataneContent

@Test
func `compresses and extracts zip archives`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let source = temp.appending(path: "src", directoryHint: .isDirectory)
    let dest = temp.appending(path: "dst", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("Hello world".utf8).write(to: source.appending(path: "test.txt"))

    let archive = temp.appending(path: "out.zip")
    let runner = ArchiveOperationRunner()

    let compressResult = try runner.compress(destinationArchiveURL: archive, sourceDirectoryURL: source)
    #expect(compressResult.fileCount == 1)
    #expect(FileManager.default.fileExists(atPath: archive.path))

    let extractResult = try runner.extract(archiveURL: archive, destinationDirectoryURL: dest)
    #expect(extractResult.fileCount == 1)
    #expect(FileManager.default.fileExists(atPath: dest.appending(path: "test.txt").path))
}

@Test
func `rejects symbolic links in arbitrary zip extraction`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let source = temp.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: source.appending(path: "escape"),
        withDestinationURL: URL(fileURLWithPath: "/tmp")
    )
    let archive = temp.appending(path: "links.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-q", "-y", archive.path, "escape"]
    process.currentDirectoryURL = source
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    #expect(throws: ArchiveOperationError.self) {
        try ArchiveOperationRunner().extract(
            archiveURL: archive,
            destinationDirectoryURL: temp.appending(path: "destination")
        )
    }
}

@Test
func `NAR compression applies developer nonar and standard exclusions`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let source = temp.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source.appending(path: "profile"), withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: source.appending(path: "install.txt"))
    try Data("skip".utf8).write(to: source.appending(path: "private.txt"))
    try Data("skip".utf8).write(to: source.appending(path: "profile/state.txt"))
    try "private.txt,nonar\n".write(
        to: source.appending(path: "developer_options.txt"),
        atomically: true,
        encoding: .utf8
    )
    let archive = temp.appending(path: "out.nar")

    let result = try ArchiveOperationRunner().compress(
        destinationArchiveURL: archive,
        sourceDirectoryURL: source,
        appliesNarExclusions: true
    )
    let destination = temp.appending(path: "extracted", directoryHint: .isDirectory)
    _ = try ArchiveOperationRunner().extract(archiveURL: archive, destinationDirectoryURL: destination)

    #expect(result.fileCount == 2)
    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "install.txt").path))
    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "developer_options.txt").path))
    #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "private.txt").path))
    #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "profile/state.txt").path))
}

@Test
func `NAR compression applies nar ignore and include files`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let source = temp.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source.appending(path: "ghost/master"), withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: source.appending(path: "install.txt"))
    try Data("keep".utf8).write(to: source.appending(path: "ghost/master/keep.txt"))
    try Data("skip".utf8).write(to: source.appending(path: "ghost/master/skip.tmp"))
    try "*.tmp\n".write(to: source.appending(path: ".narignore"), atomically: true, encoding: .utf8)
    try "install.txt\nghost/**\n.narignore\n.narinclude\n".write(
        to: source.appending(path: ".narinclude"), atomically: true, encoding: .utf8
    )
    let archive = temp.appending(path: "out.nar")
    _ = try ArchiveOperationRunner().compress(
        destinationArchiveURL: archive,
        sourceDirectoryURL: source,
        appliesNarExclusions: true
    )
    let destination = temp.appending(path: "dst", directoryHint: .isDirectory)
    _ = try ArchiveOperationRunner().extract(archiveURL: archive, destinationDirectoryURL: destination)
    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "ghost/master/keep.txt").path))
    #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "ghost/master/skip.tmp").path))
}

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

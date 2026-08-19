import Foundation
import Testing
@testable import UtataneContent

@Test func `imports ghosts and balloons from an extracted SSP directory`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = temporary.appending(path: "SSP")
    let ghosts = temporary.appending(path: "Utatane/Ghosts")
    let balloons = temporary.appending(path: "Utatane/Balloons")
    defer { try? FileManager.default.removeItem(at: temporary) }

    try createFile(at: source.appending(path: "ghost/emily/ghost/master/yaya.txt"))
    try createFile(at: source.appending(path: "ghost/emily/ghost/master/descript.txt"))
    try createFile(at: source.appending(path: "balloon/origin/balloons0.png"))

    let result = try SSPContentImporter().importContents(
        from: source,
        ghostsDirectory: ghosts,
        balloonsDirectory: balloons
    )

    #expect(result.importedItemCount == 2)
    #expect(FileManager.default.fileExists(atPath: ghosts.appending(path: "emily/ghost/master/yaya.txt").path))
    #expect(FileManager.default.fileExists(atPath: balloons.appending(path: "origin/balloons0.png").path))
}

@Test func `ignores SSP helper directories that are not ghosts`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = temporary.appending(path: "SSP")
    let ghosts = temporary.appending(path: "Utatane/Ghosts")
    defer { try? FileManager.default.removeItem(at: temporary) }

    try createFile(at: source.appending(path: "ghost/emily/ghost/master/descript.txt"))
    try createFile(at: source.appending(path: "ghost/key_Librarian/descript.txt"))

    let result = try SSPContentImporter().importContents(
        from: source,
        ghostsDirectory: ghosts,
        balloonsDirectory: temporary.appending(path: "Balloons")
    )

    #expect(result.ghostDirectories.map(\.lastPathComponent) == ["emily"])
    #expect(!FileManager.default.fileExists(atPath: ghosts.appending(path: "key_Librarian").path))
}

@Test func `accepts a directory containing one SSP root directory`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let extracted = temporary.appending(path: "extracted")
    let source = extracted.appending(path: "ssp_2_6_54")
    defer { try? FileManager.default.removeItem(at: temporary) }

    try createFile(at: source.appending(path: "ghost/sakura/ghost/master/descript.txt"))
    let result = try SSPContentImporter().importContents(
        from: extracted,
        ghostsDirectory: temporary.appending(path: "Ghosts"),
        balloonsDirectory: temporary.appending(path: "Balloons")
    )
    #expect(result.ghostDirectories.map(\.lastPathComponent) == ["sakura"])
}

@Test func `does not overwrite installed content`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = temporary.appending(path: "SSP")
    let ghosts = temporary.appending(path: "Ghosts")
    defer { try? FileManager.default.removeItem(at: temporary) }

    try createFile(at: source.appending(path: "ghost/sakura/install.txt"))
    try createFile(at: ghosts.appending(path: "sakura/existing.txt"))

    #expect(throws: SSPContentImportError.self) {
        try SSPContentImporter().importContents(
            from: source,
            ghostsDirectory: ghosts,
            balloonsDirectory: temporary.appending(path: "Balloons")
        )
    }
}

@Test func `rejects symbolic links in imported content`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = temporary.appending(path: "SSP")
    let ghost = source.appending(path: "ghost/sakura")
    defer { try? FileManager.default.removeItem(at: temporary) }

    try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: ghost.appending(path: "outside"),
        withDestinationURL: temporary
    )

    #expect(throws: (any Error).self) {
        try SSPContentImporter().importContents(
            from: source,
            ghostsDirectory: temporary.appending(path: "Ghosts"),
            balloonsDirectory: temporary.appending(path: "Balloons")
        )
    }
}

private func createFile(at url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("test".utf8).write(to: url)
}

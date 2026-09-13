import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test func `safe content trash accepts only a direct child`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let container = temporary.appending(path: "Ghosts", directoryHint: .isDirectory)
    let item = container.appending(path: "ria", directoryHint: .isDirectory)
    let nested = item.appending(path: "ghost", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    #expect(SafeContentTrash.isDirectChild(item, of: container))
    #expect(!SafeContentTrash.isDirectChild(nested, of: container))
    #expect(!SafeContentTrash.isDirectChild(container, of: container))
}

@Test func `safe content trash validates before moving`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let container = temporary.appending(path: "Balloons", directoryHint: .isDirectory)
    let item = container.appending(path: "origin", directoryHint: .isDirectory)
    let nested = item.appending(path: "readme", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    var movedURL: URL?
    let trash = SafeContentTrash { movedURL = $0 }
    try trash.moveToTrash(item, directChildOf: container)
    #expect(movedURL == item.standardizedFileURL)

    #expect(throws: SafeContentTrashError.unsafeLocation) {
        try trash.moveToTrash(nested, directChildOf: container)
    }
    #expect(throws: SafeContentTrashError.missingItem) {
        try trash.moveToTrash(container.appending(path: "missing"), directChildOf: container)
    }
}

@Test func `safe content trash rejects a symlink escaping its container`() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let container = temporary.appending(path: "Plugins", directoryHint: .isDirectory)
    let outside = temporary.appending(path: "outside", directoryHint: .isDirectory)
    let link = container.appending(path: "linked-plugin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    defer { try? FileManager.default.removeItem(at: temporary) }

    #expect(!SafeContentTrash.isDirectChild(link, of: container))
    #expect(throws: SafeContentTrashError.unsafeLocation) {
        try SafeContentTrash(moveItem: { _ in }).moveToTrash(link, directChildOf: container)
    }
}

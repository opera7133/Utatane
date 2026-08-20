import Foundation
import Testing
@testable import UtataneShell

@Test
func `loads an SSP element path containing backslashes`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let parts = root.appending(path: "parts", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
    let image = parts.appending(path: "21000_CC_2.png", directoryHint: .notDirectory)
    try Data().write(to: image)

    let asset = try ShellLoader().loadElement(
        filename: "parts\\21000_CC_2.png",
        from: root
    )

    #expect(asset.imageURL == image)
}

@Test
func `rejects traversal in an SSP element path containing backslashes`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    #expect(throws: ShellError.self) {
        try ShellLoader().loadElement(filename: "..\\outside.png", from: root)
    }
}

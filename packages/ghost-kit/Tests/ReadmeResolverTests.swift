import Foundation
import Testing
@testable import UtataneGhostKit

@Test
func `resolves configured readme and charset safely`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try Data("readme,docs/guide.txt\nreadme.charset,UTF-8\n".utf8).write(to: master.appending(path: "descript.txt"))
    try FileManager.default.createDirectory(at: root.appending(path: "docs"), withIntermediateDirectories: true)
    try Data("guide".utf8).write(to: root.appending(path: "docs/guide.txt"))

    let document = ReadmeResolver().resolve(
        contentDirectory: root,
        descriptorURL: master.appending(path: "descript.txt")
    )

    #expect(document?.url == root.appending(path: "docs/guide.txt"))
    #expect(document?.charset == "UTF-8")
}

@Test
func `rejects readme outside content directory`() throws {
    let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "content", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("outside".utf8).write(to: parent.appending(path: "outside.txt"))
    let descriptor = root.appending(path: "descript.txt")
    try Data("readme,../outside.txt\n".utf8).write(to: descriptor)

    #expect(ReadmeResolver().resolve(contentDirectory: root, descriptorURL: descriptor) == nil)
}

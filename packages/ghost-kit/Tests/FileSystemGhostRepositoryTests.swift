import Foundation
import Testing
@testable import UtataneGhostKit

@Test func `invalid helper directories do not hide valid installed ghosts`() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let valid = root.appending(path: "valid", directoryHint: .isDirectory)
    try write("name,Valid Ghost\n", to: valid.appending(path: "ghost/master/descript.txt"))
    try write("name,Master\n", to: valid.appending(path: "shell/master/descript.txt"))
    try write("name,Helper\n", to: root.appending(path: "key_Librarian/descript.txt"))

    let ghosts = try await FileSystemGhostRepository(rootDirectory: root).installedGhosts()

    #expect(ghosts.map(\.name) == ["Valid Ghost"])
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

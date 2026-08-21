import CryptoKit
import Foundation
import Testing
@testable import UtataneNetwork

@Test func `parses both update manifest formats and rejects traversal`() throws {
    let delimiter = "\u{1}"
    let data = Data("ghost/master/a.txt\(delimiter)d41d8cd98f00b204e9800998ecf8427e\(delimiter)\nfile,shell/master/a.png\(delimiter)d41d8cd98f00b204e9800998ecf8427e\(delimiter)size=0\(delimiter)\n".utf8)
    let entries = try ContentNetworkUpdater.parseManifest(data)
    #expect(entries.map(\.path) == ["ghost/master/a.txt", "shell/master/a.png"])

    #expect(throws: ContentNetworkUpdateError.self) {
        try ContentNetworkUpdater.parseManifest(Data("../outside\(delimiter)d41d8cd98f00b204e9800998ecf8427e\n".utf8))
    }
}

@Test func `downloads verifies and applies changed files`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let content = Data("new content".utf8)
    let hash = Insecure.MD5.hash(data: content).map { String(format: "%02x", $0) }.joined()
    let delimiter = "\u{1}"
    let manifest = Data("descript.txt\(delimiter)\(hash)\(delimiter)\n".utf8)
    let updater = ContentNetworkUpdater { url in
        if url.lastPathComponent == "updates2.dau" {
            return manifest
        }
        if url.lastPathComponent == "descript.txt" {
            return content
        }
        throw NetworkFetchError.unsuccessfulStatus(404)
    }

    let result = try await updater.update(rootDirectory: root, homeURL: #require(URL(string: "https://example.test/ghost/")))
    #expect(result.changedFiles == ["descript.txt"])
    #expect(try Data(contentsOf: root.appending(path: "descript.txt")) == content)
}

@Test func `reads homeurl from ghost and balloon descriptors`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let ghost = root.appending(path: "ghost", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: ghost.appending(path: "ghost/master", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    try Data("name,Ghost\nhomeurl,https://example.test/ghost/\n".utf8).write(
        to: ghost.appending(path: "ghost/master/descript.txt")
    )

    let balloon = root.appending(path: "balloon", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: balloon, withIntermediateDirectories: true)
    try Data("type,balloon\nhomeurl,https://example.test/balloon/\n".utf8).write(
        to: balloon.appending(path: "descript.txt")
    )

    #expect(ContentNetworkUpdater.homeURL(in: ghost)?.absoluteString == "https://example.test/ghost/")
    #expect(ContentNetworkUpdater.homeURL(in: balloon)?.absoluteString == "https://example.test/balloon/")
}

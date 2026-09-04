import CryptoKit
import Foundation
import Testing
@testable import UtataneNetwork

private actor UpdateProgressRecorder {
    private var values: [ContentUpdateProgress] = []

    func append(_ value: ContentUpdateProgress) {
        values.append(value)
    }

    func recorded() -> [ContentUpdateProgress] {
        values
    }
}

private actor UpdateFetchRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func recorded() -> [String] {
        values
    }
}

@Test func `parses both update manifest formats and rejects traversal`() throws {
    let delimiter = "\u{1}"
    let data = Data("charset,Shift_JIS\ncomment,ignored\nghost/master/a.txt\(delimiter)d41d8cd98f00b204e9800998ecf8427e\(delimiter)\nfile,shell/master/a.png\(delimiter)d41d8cd98f00b204e9800998ecf8427e\(delimiter)size=0\(delimiter)date=2026-08-24T00:00:00Z\(delimiter)charset=UTF-8\(delimiter)\n".utf8)
    let entries = try ContentNetworkUpdater.parseManifest(data)
    #expect(entries.map(\.path) == ["ghost/master/a.txt", "shell/master/a.png"])
    #expect(entries[1].size == 0)
    #expect(entries[1].date == "2026-08-24T00:00:00Z")
    #expect(entries[1].charset == "UTF-8")

    #expect(throws: ContentNetworkUpdateError.self) {
        try ContentNetworkUpdater.parseManifest(Data("../outside\(delimiter)d41d8cd98f00b204e9800998ecf8427e\n".utf8))
    }
}

@Test func `formats legacy and extended aggregate update results`() {
    let success = ContentUpdateEventRecord(name: "Ghost", type: "ghost", succeeded: true, result: "2")
    #expect(success.legacyValue == "ghost\u{1}OK\u{1}2")
    #expect(success.extendedValue == "Ghost\u{1}ghost\u{1}OK\u{1}2")

    let failure = ContentUpdateEventRecord(
        name: "Ghost",
        type: "ghost",
        succeeded: false,
        result: "md5 miss",
        failurePath: "ghost/master/a.txt"
    )
    #expect(failure.legacyValue == "ghost\u{1}NG\u{1}md5 miss\u{1}ghost/master/a.txt")
    #expect(failure.extendedValue == "Ghost\u{1}ghost\u{1}NG\u{1}md5 miss\u{1}ghost/master/a.txt")
}

@Test func `parses and safely applies delete txt after update`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: root.appending(path: "ghost/master/old", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("obsolete".utf8).write(to: root.appending(path: "ghost/master/obsolete.txt"))
    try Data("old".utf8).write(to: root.appending(path: "ghost/master/old/data.txt"))
    let deleteList = Data("charset,UTF-8\nghost\\master\\obsolete.txt\nghost\\master\\old\\\n".utf8)
    let updater = ContentNetworkUpdater { url in
        switch url.lastPathComponent {
        case "updates2.dau": Data()
        case "delete.txt": deleteList
        default: throw NetworkFetchError.unsuccessfulStatus(404)
        }
    }

    _ = try await updater.update(rootDirectory: root, homeURL: #require(URL(string: "https://example.test/ghost/")))

    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "ghost/master/obsolete.txt").path))
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "ghost/master/old").path))
    #expect(throws: ContentNetworkUpdateError.self) {
        try ContentNetworkUpdater.parseDeleteList(Data("..\\outside".utf8))
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

    let recorder = UpdateProgressRecorder()
    let result = try await updater.update(
        rootDirectory: root,
        homeURL: #require(URL(string: "https://example.test/ghost/")),
        progress: { await recorder.append($0) }
    )
    #expect(result.changedFiles == ["descript.txt"])
    #expect(try Data(contentsOf: root.appending(path: "descript.txt")) == content)
    #expect(await recorder.recorded() == [
        .ready(files: ["descript.txt"]),
        .downloadBegin(path: "descript.txt", index: 0, total: 1),
        .checksumBegin(path: "descript.txt", expected: hash, actual: hash),
        .checksumComplete(path: "descript.txt", expected: hash, actual: hash)
    ])
}

@Test func `checks pending files without downloading or changing them`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("current".utf8).write(to: root.appending(path: "current.txt"))
    let currentHash = Insecure.MD5.hash(data: Data("current".utf8)).map { String(format: "%02x", $0) }.joined()
    let newHash = Insecure.MD5.hash(data: Data("new".utf8)).map { String(format: "%02x", $0) }.joined()
    let delimiter = "\u{1}"
    let manifest = Data("current.txt\(delimiter)\(currentHash)\(delimiter)\nnew.txt\(delimiter)\(newHash)\(delimiter)\n".utf8)
    let fetched = UpdateFetchRecorder()
    let updater = ContentNetworkUpdater { url in
        await fetched.append(url.lastPathComponent)
        if url.lastPathComponent == "updates2.dau" {
            return manifest
        }
        throw NetworkFetchError.unsuccessfulStatus(404)
    }

    let result = try await updater.check(
        rootDirectory: root,
        homeURL: #require(URL(string: "https://example.test/ghost/"))
    )

    #expect(result.changedFiles == ["new.txt"])
    #expect(await fetched.recorded() == ["updates2.dau"])
    #expect(try Data(contentsOf: root.appending(path: "current.txt")) == Data("current".utf8))
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "new.txt").path))
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

@Test func `throws downloadFailed when file fetch fails`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let hash = "d41d8cd98f00b204e9800998ecf8427e"
    let delimiter = "\u{1}"
    let manifest = Data("missing.txt\(delimiter)\(hash)\(delimiter)\n".utf8)
    let updater = ContentNetworkUpdater { url in
        if url.lastPathComponent == "updates2.dau" {
            return manifest
        }
        throw NetworkFetchError.unsuccessfulStatus(404)
    }

    do {
        _ = try await updater.update(rootDirectory: root, homeURL: #require(URL(string: "https://example.test/ghost/")))
        #expect(Bool(false), "Expected update to throw downloadFailed")
    } catch let ContentNetworkUpdateError.downloadFailed(path, errorDescription) {
        #expect(path == "missing.txt")
        #expect(errorDescription.contains("404"))
    } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
    }
}

@Test func `retains manifest transport failure when fallback is missing`() async throws {
    let updater = ContentNetworkUpdater { url in
        if url.lastPathComponent == "updates2.dau" {
            throw URLError(.appTransportSecurityRequiresSecureConnection)
        }
        throw NetworkFetchError.unsuccessfulStatus(404)
    }
    do {
        _ = try await updater.update(
            rootDirectory: FileManager.default.temporaryDirectory,
            homeURL: #require(URL(string: "http://example.test/ghost/"))
        )
        Issue.record("Expected manifest transport failure")
    } catch let ContentNetworkUpdateError.downloadFailed(path, detail) {
        #expect(path == "updates2.dau")
        #expect(!detail.isEmpty)
    }
}

import CryptoKit
import Foundation
import Testing
@testable import UtataneNetwork

private actor FetchFlag {
    private(set) var wasFetched = false

    func markFetched() {
        wasFetched = true
    }
}

@Test func `content update job checks and updates the same target`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let content = Data("updated".utf8)
    let hash = Insecure.MD5.hash(data: content).map { String(format: "%02x", $0) }.joined()
    let manifest = Data("data.txt\u{1}\(hash)\u{1}\n".utf8)
    let updater = ContentNetworkUpdater { url in
        switch url.lastPathComponent {
        case "updates2.dau": manifest
        case "data.txt": content
        default: throw NetworkFetchError.unsuccessfulStatus(404)
        }
    }
    let job = ContentUpdateJob(updater: updater)
    let target = try ContentUpdateTarget(
        kind: .plugin,
        name: "Test Plugin",
        rootDirectory: root,
        homeURL: #require(URL(string: "https://example.test/plugin/"))
    )

    let checked = try await job.run(target: target, operation: .check)
    #expect(checked.changedFiles == ["data.txt"])
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "data.txt").path))

    let updated = try await job.run(target: target, operation: .update)
    #expect(updated.changedFiles == ["data.txt"])
    #expect(try Data(contentsOf: root.appending(path: "data.txt")) == content)
    #expect(target.id == "plugin:\(root.standardizedFileURL.path)")
}

@Test func `content update job respects cancellation before network access`() async throws {
    let fetched = FetchFlag()
    let updater = ContentNetworkUpdater { _ in
        await fetched.markFetched()
        return Data()
    }
    let target = try ContentUpdateTarget(
        kind: .ghost,
        name: "Cancelled Ghost",
        rootDirectory: FileManager.default.temporaryDirectory,
        homeURL: #require(URL(string: "https://example.test/ghost/"))
    )
    let task = Task {
        try await ContentUpdateJob(updater: updater).run(target: target, operation: .check)
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
    let wasFetched = await fetched.wasFetched
    #expect(!wasFetched)
}

@Test func `content update job preserves cancellation from network fetch`() async throws {
    let updater = ContentNetworkUpdater { _ in throw CancellationError() }
    let target = try ContentUpdateTarget(
        kind: .balloon,
        name: "Cancelled Balloon",
        rootDirectory: FileManager.default.temporaryDirectory,
        homeURL: #require(URL(string: "https://example.test/balloon/"))
    )

    await #expect(throws: CancellationError.self) {
        try await ContentUpdateJob(updater: updater).run(target: target, operation: .update)
    }
}

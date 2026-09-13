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

private actor FetchAttempts {
    private var values: [String: Int] = [:]

    func next(for key: String) -> Int {
        values[key, default: 0] += 1
        return values[key, default: 0]
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

@Test func `content update batch retries transient failures and continues after permanent failures`() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let retryRoot = temporary.appending(path: "retry", directoryHint: .isDirectory)
    let invalidRoot = temporary.appending(path: "invalid", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: retryRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let attempts = FetchAttempts()
    let manifest = Data()
    let updater = ContentNetworkUpdater { url in
        if url.host == "retry.example.test" {
            let attempt = await attempts.next(for: url.host ?? "")
            if attempt <= 2 {
                throw NetworkFetchError.unsuccessfulStatus(503)
            }
            return manifest
        }
        throw NetworkFetchError.unsuccessfulStatus(404)
    }
    let retryTarget = try ContentUpdateTarget(
        kind: .ghost,
        name: "Retry Ghost",
        rootDirectory: retryRoot,
        homeURL: #require(URL(string: "https://retry.example.test/"))
    )
    let invalidTarget = try ContentUpdateTarget(
        kind: .balloon,
        name: "Invalid Balloon",
        rootDirectory: invalidRoot,
        homeURL: #require(URL(string: "file:///tmp/invalid"))
    )

    let result = try await ContentUpdateBatchJob(job: ContentUpdateJob(updater: updater)).run(
        targets: [invalidTarget, retryTarget],
        operation: .check
    )

    #expect(result.items.count == 2)
    #expect(result.failedCount == 1)
    #expect(result.succeededCount == 1)
    #expect(result.items[0].attempts == 1)
    #expect(result.items[1].attempts == 2)
}

@Test func `repair uses the transactional update path`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let content = Data("repaired".utf8)
    let hash = Insecure.MD5.hash(data: content).map { String(format: "%02x", $0) }.joined()
    let manifest = Data("data.txt\u{1}\(hash)\u{1}\n".utf8)
    let updater = ContentNetworkUpdater { url in
        switch url.lastPathComponent {
        case "updates2.dau": manifest
        case "data.txt": content
        default: throw NetworkFetchError.unsuccessfulStatus(404)
        }
    }
    let target = try ContentUpdateTarget(
        kind: .plugin,
        name: "Repair Plugin",
        rootDirectory: root,
        homeURL: #require(URL(string: "https://example.test/plugin/"))
    )

    let result = try await ContentUpdateJob(updater: updater).run(target: target, operation: .repair)

    #expect(result.changedFiles == ["data.txt"])
    #expect(try Data(contentsOf: root.appending(path: "data.txt")) == content)
}

import Foundation
import Testing
@testable import UtataneNativeSaori

private func asynchronousRequest(_ module: String, _ arguments: [String]) -> Data {
    Data((["EXECUTE SAORI/1.0", "Charset: UTF-8", "Module: \(module)"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n").appending("\r\n\r\n").utf8)
}

private final class InternalEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [InternalSaoriEvent] = []
    private var waiter: (Int, CheckedContinuation<[InternalSaoriEvent], Never>)?

    func record(_ event: InternalSaoriEvent) {
        lock.withLock {
            recorded.append(event)
            if let (count, continuation) = waiter, recorded.count >= count {
                waiter = nil
                continuation.resume(returning: recorded)
            }
        }
    }

    func events(count: Int) async -> [InternalSaoriEvent] {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if recorded.count >= count {
                    continuation.resume(returning: recorded)
                } else {
                    waiter = (count, continuation)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [self] in
                lock.withLock {
                    if let (_, continuation) = waiter {
                        waiter = nil
                        continuation.resume(returning: recorded)
                    }
                }
            }
        }
    }
}

@Test func `async SAORI returns 204 and delivers complete values to its own session`() async throws {
    let first = InternalEventRecorder()
    let second = InternalEventRecorder()
    let a = InternalSaoriSession(onEvent: first.record)
    let b = InternalSaoriSession(onEvent: second.record)
    defer { a.close(); b.close() }
    let response = a.response(to: asynchronousRequest("internal_system", ["ListModules", "--async=list"]))
    #expect(String(decoding: response, as: UTF8.self).hasPrefix("SAORI/1.0 204"))
    _ = b.response(to: asynchronousRequest("internal_text", ["Normalize", "NFKC", "ｶﾞｲﾄﾞ", "--async=OnNormalized"]))
    let event = try #require(await first.events(count: 1).first)
    #expect(event.id == "OnInternalSaoriComplete")
    #expect(event.references[0] == "list")
    #expect(event.references[2] == "internal_system")
    #expect(event.references[3] == "ListModules")
    #expect(event.references[4] == "internal_crypto")
    #expect(event.isCurrent)
    let other = try #require(await second.events(count: 1).first)
    #expect(other.id == "OnNormalized")
    #expect(other.references[1] == "ガイド")
    a.close()
    #expect(!event.isCurrent)
    #expect(other.isCurrent)
}

@Test func `async SAORI validates shape before accepting and reports content failures later`() async throws {
    let recorder = InternalEventRecorder()
    let session = InternalSaoriSession(onEvent: recorder.record)
    defer { session.close() }
    for arguments in [
        ["Convert", "abc", "--bad=1", "--async=OnInvalid"],
        ["Convert", "abc", "--async="]
    ] {
        #expect(String(decoding: session.response(to: asynchronousRequest("internal_data", arguments)), as: UTF8.self).hasPrefix("SAORI/1.0 400"))
    }
    let response = session.response(to: asynchronousRequest("internal_data", ["Convert", "zz", "--in=hex", "--async=OnInvalid"]))
    #expect(String(decoding: response, as: UTF8.self).hasPrefix("SAORI/1.0 204"))
    let event = try #require(await recorder.events(count: 1).first)
    #expect(event.id == "OnInvalidFailure")
    #expect(event.references == [0: "OnInvalid", 1: "invalid encoding", 2: "internal_data", 3: "Convert"])
    let noGhost = InternalSaoriSession()
    #expect(String(decoding: noGhost.response(to: asynchronousRequest("internal_random", ["UUID", "--async=id"])), as: UTF8.self).contains("ghost required"))
}

@Test func `async requests cannot hide malformed headers during rewriting`() {
    let session = InternalSaoriSession(onEvent: { _ in Issue.record("malformed request accepted") })
    defer { session.close() }
    let valid = String(decoding: asynchronousRequest("internal_random", ["UUID", "--async=id"]), as: UTF8.self)
    for header in ["Argumentfoo: hidden", "Argument00: hidden", "Argument-1: hidden", "Sender: bad\0value", "Sender: bad\nvalue"] {
        let malformed = valid.replacingOccurrences(of: "Charset: UTF-8", with: "Charset: UTF-8\r\n\(header)")
        #expect(String(decoding: session.response(to: Data(malformed.utf8)), as: UTF8.self).hasPrefix("SAORI/1.0 400"))
    }
}

@Test func `queued async work is bounded and discarded on SHIORI shutdown`() async {
    let queue = OperationQueue()
    queue.isSuspended = true
    let recorder = InternalEventRecorder()
    let session = InternalSaoriSession(onEvent: recorder.record, queue: queue)
    for index in 0 ..< 64 {
        let response = session.response(to: asynchronousRequest("internal_random", ["UUID", "--async=\(index)"]))
        #expect(String(decoding: response, as: UTF8.self).hasPrefix("SAORI/1.0 204"))
    }
    #expect(String(decoding: session.response(to: asynchronousRequest("internal_random", ["UUID", "--async=overflow"])), as: UTF8.self).contains("too many requests"))
    session.close()
    queue.isSuspended = false
    await withCheckedContinuation { continuation in
        queue.addBarrierBlock { continuation.resume() }
    }
    #expect(await recorder.events(count: 0).isEmpty)
}

@Test func `async option uses the last identifier without swallowing positional data`() async throws {
    let recorder = InternalEventRecorder()
    let session = InternalSaoriSession(onEvent: recorder.record)
    defer { session.close() }
    let result = session.response(to: asynchronousRequest("internal_data", ["Convert", "--async=literal", "--async=old", "--ASYNC=OnLast"]))
    #expect(String(decoding: result, as: UTF8.self).hasPrefix("SAORI/1.0 204"))
    let event = try #require(await recorder.events(count: 1).first)
    #expect(event.id == "OnLast")
    #expect(event.references[1] == "--async=literal")
}

@Test func `asynchronous file hashes use ghost paths and deliver read failures as events`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("abc".utf8).write(to: root.appending(path: "日本語.bin"))
    let recorder = InternalEventRecorder()
    let session = InternalSaoriSession(onEvent: recorder.record, service: .init(ghostDirectory: root))
    defer { session.close() }
    for (filename, identifier) in [("日本語.bin", "OnFileHash"), ("missing", "OnMissing")] {
        let result = session.response(to: asynchronousRequest("internal_crypto", ["Digest", "sha256", filename, "--data-in=file", "--async=\(identifier)"]))
        #expect(String(decoding: result, as: UTF8.self).hasPrefix("SAORI/1.0 204"))
    }
    let events = await recorder.events(count: 2)
    let success = try #require(events.first { $0.id == "OnFileHash" })
    #expect(success.references[1] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let failure = try #require(events.first { $0.id == "OnMissingFailure" })
    #expect(failure.references[1] == "file not found")
}

private func legacyHttpcHeaders(_ directory: URL, _ arguments: [String]) -> [String: String] {
    var result = ["module": "utatane_httpc", "charset": "UTF-8", "directory": directory.path]
    for (index, value) in arguments.enumerated() {
        result["argument\(index)"] = value
    }
    return result
}

@Test func `httpc bg notifications preserve owners identifiers all matches and unload lifetime`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = InternalEventRecorder()
    let body = Data("<a>日本語</a>\r\n<a>次</a>".utf8)
    let legacy = LegacyHttpcSession(onEvent: recorder.record, queue: OperationQueue(), fetch: { url, _ in url.path == "/missing" ? nil : (body, "UTF-8") })
    defer { legacy.close() }
    func send(_ arguments: [String]) -> String {
        String(decoding: legacy.response(headers: legacyHttpcHeaders(root, arguments), charset: "UTF-8"), as: UTF8.self)
    }
    #expect(send(["bg", "text", "https://example.invalid/ok"]).hasPrefix("SAORI/1.0 204"))
    #expect(send(["bg", "save", "https://example.invalid/ok", "保存.bin"]).hasPrefix("SAORI/1.0 204"))
    #expect(send(["bg", "failed", "https://example.invalid/missing", "保存.bin"]).hasPrefix("SAORI/1.0 204"))
    #expect(send(["bg", "extract", "https://example.invalid/ok", "<a>", "</a>"]).hasPrefix("SAORI/1.0 204"))
    let events = await recorder.events(count: 4)
    #expect(events.first { $0.references[0] == "extract" }?.references == [0: "extract", 1: "-", 2: "日本語", 3: "次"])
    #expect(events.allSatisfy { $0.id == "OnHttpcNotify" && $0.references[1] == "-" && $0.isCurrent })
    #expect(events.first { $0.references[0] == "text" }?.references[2] == "<a>日本語</a><a>次</a>")
    #expect(events.first { $0.references[0] == "save" }?.references[2] == "1")
    #expect(events.first { $0.references[0] == "failed" }?.references[2] == "0")
    #expect(try Data(contentsOf: root.appending(path: "保存.bin")) == body)
    _ = send(["cancel"])
    #expect(events.allSatisfy { !$0.isCurrent })
    _ = send(["bg", "new-lifetime", "https://example.invalid/ok"])
    let newEvents = await recorder.events(count: 5)
    #expect(newEvents.last?.isCurrent == true)
    legacy.close()
    #expect(newEvents.allSatisfy { !$0.isCurrent })
}

@Test func `private httpc bridge validates requests bounds queues and drops closed work`() async {
    let root = FileManager.default.temporaryDirectory
    let queue = OperationQueue()
    queue.isSuspended = true
    let legacy = LegacyHttpcSession(onEvent: { _ in Issue.record("closed httpc delivered a result") }, queue: queue,
                                    fetch: { _, _ in Issue.record("closed httpc performed IO"); return nil })
    for index in 0 ..< 64 {
        let result = legacy.response(headers: legacyHttpcHeaders(root, ["bg", "id\(index)", "https://example.invalid/ok"]), charset: "UTF-8")
        #expect(String(decoding: result, as: UTF8.self).hasPrefix("SAORI/1.0 204"))
    }
    let rejected = legacy.response(headers: legacyHttpcHeaders(root, ["bg", "overflow", "https://example.invalid/ok"]), charset: "UTF-8")
    #expect(String(decoding: rejected, as: UTF8.self).contains("too many requests"))
    legacy.close(); queue.isSuspended = false
    await withCheckedContinuation { continuation in queue.addBarrierBlock { continuation.resume() } }
    let noOwner = LegacyHttpcSession(onEvent: nil)
    #expect(String(decoding: noOwner.response(headers: legacyHttpcHeaders(root, ["bg", "id", "https://example.invalid/ok"]), charset: "UTF-8"), as: UTF8.self).contains("ghost required"))
    noOwner.close()
}

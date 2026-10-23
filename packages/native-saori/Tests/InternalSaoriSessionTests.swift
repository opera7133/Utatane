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
        ["Convert", "abc", "--async="],
        ["Convert", "abc", "--async=a", "--async=b"]
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

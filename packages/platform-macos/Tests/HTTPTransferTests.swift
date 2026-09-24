import Foundation
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS

@MainActor
struct HTTPTransferTests {
    @Test func `HTTP streaming preserves line order and the complete response`() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let received = Receiver()
        let url = try #require(URL(string: "https://utatane-test.invalid/stream"))
        let result = try await HTTPTransferClient.perform(
            URLRequest(url: url),
            progress: { data, _ in await received.progress(data.count) },
            streaming: { value, _ in await received.line(value) },
            session: session
        )
        #expect(result.data == FixtureProtocol.body)
        #expect((result.response as? HTTPURLResponse)?.statusCode == 200)
        #expect(received.lines == ["日本語", "", "last"])
        #expect(received.progressSizes == [FixtureProtocol.body.count])
    }

    @Test func `paused HTTP notification prevents further consumption and cancellation releases it`() async throws {
        let received = Receiver()
        received.clock.setSuspended(true)
        let bytes = CountingBytes()
        let url = try #require(URL(string: "https://utatane-test.invalid/stream"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        var cancelled = false
        let transfer = Task {
            do {
                _ = try await HTTPTransferClient.consume(
                    bytes, response: response, progress: nil,
                    streaming: { value, _ in await received.line(value) }
                )
            } catch is CancellationError { cancelled = true }
            catch { Issue.record(error) }
        }
        try await requireEventually { received.enteredLine }
        #expect(received.lines.isEmpty)
        #expect(bytes.consumed == 2) // One line only, regardless of input size.
        transfer.cancel()
        try await requireEventually { cancelled }
        #expect(received.lines.isEmpty)
        #expect(bytes.consumed <= 3)
    }
}

@MainActor
private final class Receiver {
    let clock = SuspensionClock()
    var enteredLine = false
    var lines: [String] = []
    var progressSizes: [Int] = []

    func line(_ value: String) async {
        enteredLine = true
        guard await clock.waitUntilActive() else { return }
        lines.append(value)
    }

    func progress(_ size: Int) {
        progressSizes.append(size)
    }
}

@MainActor
private final class CountingBytes: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = UInt8
    var consumed = 0
    nonisolated func makeAsyncIterator() -> CountingBytes {
        self
    }

    func next() async -> UInt8? {
        guard consumed < 10000 else { return nil }
        consumed += 1
        return consumed.isMultiple(of: 2) ? 10 : 65
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let body = Data("日本語\r\n\nlast".utf8)
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliberately split a multibyte UTF-8 character between packets.
        client?.urlProtocol(self, didLoad: Self.body.prefix(1))
        client?.urlProtocol(self, didLoad: Self.body.dropFirst())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

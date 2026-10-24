import Foundation
import Testing
@testable import UtatanePlatformMacOS

@MainActor
struct HTTPFileOutputTests {
    @Test func `file downloads expose flushed progress without retaining their body`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "download.bin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FileDownloadProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let observed = FileDownloadObservations()
        let result = try await HTTPTransferClient.perform(URLRequest(url: #require(URL(string: "https://fixture.invalid/ok"))),
                                                          progress: { data, _ in
                                                              #expect(data.isEmpty)
                                                              let size = try? Data(contentsOf: file).count
                                                              await observed.append(size ?? -1)
                                                          }, outputFileURL: file, session: session)
        #expect(result.fileURL == file)
        #expect(result.data.isEmpty)
        #expect(try Data(contentsOf: file) == FileDownloadProtocol.body)
        #expect(observed.sizes == [65536, 131_072, 196_608])
        let old = Data("old".utf8)
        try old.write(to: file)
        let failure = try await HTTPTransferClient.perform(URLRequest(url: #require(URL(string: "https://fixture.invalid/failure"))), outputFileURL: file, session: session)
        #expect(failure.fileURL == nil)
        #expect(try Data(contentsOf: file) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["download.bin"])
    }

    @Test func `failed partial downloads restore the old file and release the writer`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "download.bin")
        let old = Data("previous complete result".utf8)
        try old.write(to: file)
        let url = try #require(URL(string: "https://fixture.invalid/ok"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        do {
            let output = try HTTPFileOutput(file)
            _ = try await HTTPTransferClient.consume(FailingFileBytes(), response: response, progress: nil, streaming: nil, output: output)
            Issue.record("broken transfer completed")
        } catch let error as URLError { #expect(error.code == .networkConnectionLost) }
        #expect(try Data(contentsOf: file) == old)
        do {
            let output = try HTTPFileOutput(file)
            #expect(throws: (any Error).self) { try HTTPFileOutput(file) }
            try output.write(Data("new".utf8)); try output.commit()
        }
        #expect(try Data(contentsOf: file) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["download.bin"])
    }

    @Test func `cancellation removes a new partial file while streaming sees flushed bytes`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "new.bin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FileDownloadProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = try URLRequest(url: #require(URL(string: "https://fixture.invalid/ok")))
        await Task {
            do {
                _ = try await HTTPTransferClient.perform(request, progress: { _, _ in
                    #expect((try? Data(contentsOf: file).count) == 65536)
                    withUnsafeCurrentTask { $0?.cancel() }
                }, outputFileURL: file, session: session)
                Issue.record("cancelled transfer succeeded")
            } catch { #expect(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        }.value
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let responseURL = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil))
        let output = try HTTPFileOutput(file)
        let body = Data("first\r\nsecond\n".utf8)
        let observations = FileDownloadObservations()
        let data = try await HTTPTransferClient.consume(FileFixtureBytes(bytes: Array(body)), response: response, progress: nil, streaming: { _, _ in
            await observations.append((try? Data(contentsOf: file).count) ?? -1)
        }, output: output)
        #expect(data.isEmpty)
        #expect(observations.sizes == [7, 14])
        try output.commit()
        #expect(try Data(contentsOf: file) == body)
    }
}

@MainActor private final class FileDownloadObservations {
    var sizes: [Int] = []
    func append(_ size: Int) {
        sizes.append(size)
    }
}

private struct FailingFileBytes: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = UInt8
    var count = 0
    func makeAsyncIterator() -> Self {
        self
    }

    mutating func next() async throws -> UInt8? {
        if count == 100_000 {
            throw URLError(.networkConnectionLost)
        }
        count += 1; return 65
    }
}

private final class FileDownloadProtocol: URLProtocol, @unchecked Sendable {
    static let body = Data(repeating: 65, count: 3 * 65536)
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url!.path == "/ok" ? 200 : 404, httpVersion: nil, headerFields: ["Content-Length": String(Self.body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct FileFixtureBytes: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = UInt8
    var bytes: [UInt8]
    var index = 0
    func makeAsyncIterator() -> Self {
        self
    }

    mutating func next() async -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }
}

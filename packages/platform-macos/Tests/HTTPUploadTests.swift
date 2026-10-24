import Foundation
import Network
import Testing
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

@Test func `HTTP uploads stream file bytes and replay them through a 307 redirect`() async throws {
    let server = try UploadServer()
    let port = try await server.start()
    defer { server.stop() }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let body = Data((0 ..< 262_144).map { UInt8(truncatingIfNeeded: $0) })
    try body.write(to: root.appending(path: "送信.bin"))
    let command = SakuraScriptHTTPRequest(method: "POST", url: "http://127.0.0.1:\(port)/redirect", eventID: "OnPosted", waitsForCompletion: true,
                                          options: ["--param-input-file=送信.bin"], headers: ["Content-Type: application/octet-stream"], timeoutSeconds: 10)
    let prepared = try SakuraScriptHTTPRequestBuilder.prepare(command, masterDirectory: root)
    let response = try await HTTPTransferClient.perform(prepared.request, bodyFileURL: prepared.bodyFileURL)
    #expect((response.response as? HTTPURLResponse)?.statusCode == 200)
    #expect(response.data == body)
}

@Test func `HTTP multipart sends exact fields to a real loopback server`() async throws {
    let server = try UploadServer()
    let port = try await server.start()
    defer { server.stop() }
    let command = SakuraScriptHTTPRequest(method: "POST", url: "http://127.0.0.1:\(port)/echo", eventID: nil, waitsForCompletion: true,
                                          parameters: ["value=日本語", "empty="], headers: ["Content-Type: multipart/form-data"], timeoutSeconds: 10)
    let prepared = try SakuraScriptHTTPRequestBuilder.prepare(command, masterDirectory: .temporaryDirectory, boundary: "wire-fixture")
    let response = try await HTTPTransferClient.perform(prepared.request)
    #expect(response.data == prepared.request.httpBody)
}

private final class UploadServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "utatane.test.http-upload")
    private let lock = NSLock()
    private var waiter: CheckedContinuation<UInt16, any Error>?
    private var connections: [NWConnection] = []
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiter = continuation }
            listener.stateUpdateHandler = { [self] state in
                if case .ready = state, let port = listener.port {
                    finish(.success(port.rawValue))
                }
                if case let .failed(error) = state {
                    finish(.failure(error))
                }
            }
            listener.newConnectionHandler = { [self] connection in
                lock.withLock { connections.append(connection) }
                let handler = UploadConnection(connection)
                connection.start(queue: queue)
                handler.read()
            }
            queue.asyncAfter(deadline: .now() + 10) { [self] in finish(.failure(URLError(.timedOut))) }
            listener.start(queue: queue)
        }
    }

    private func finish(_ result: Result<UInt16, any Error>) {
        let continuation = lock.withLock { let value = waiter; waiter = nil; return value }
        continuation?.resume(with: result)
    }

    func stop() {
        listener.cancel()
        let connections = lock.withLock { self.connections }
        connections.forEach { $0.cancel() }
    }
}

/// All parser state is confined to the listener's serial queue.
private final class UploadConnection: @unchecked Sendable {
    let connection: NWConnection
    private var buffer = Data()
    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            if let data {
                buffer.append(data)
            }
            if let split = buffer.range(of: Data("\r\n\r\n".utf8)),
               let headers = String(data: buffer[..<split.lowerBound], encoding: .utf8)
            {
                let count = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
                guard count <= 4 * 1024 * 1024 else { connection.cancel(); return }
                if buffer.count - split.upperBound >= count {
                    if headers.hasPrefix("POST /redirect ") {
                        reply("307 Temporary Redirect", body: Data(), extra: "Location: /echo\r\n")
                    } else {
                        reply("200 OK", body: Data(buffer[split.upperBound ..< split.upperBound + count]))
                    }
                    return
                }
            }
            guard !complete, error == nil, buffer.count < 5 * 1024 * 1024 else { connection.cancel(); return }
            read()
        }
    }

    private func reply(_ status: String, body: Data, extra: String = "") {
        let data = Data("HTTP/1.1 \(status)\r\n\(extra)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        connection.send(content: data, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}

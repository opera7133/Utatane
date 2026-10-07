import Foundation
import Network
import UtataneNetwork

struct POP3Configuration: Sendable {
    let accountName: String
    let host: String
    let port: UInt16
    let user: String
    let password: String
    let usesTLS: Bool
}

struct POP3CheckResult: Sendable, Equatable {
    let messageCount: Int
    let totalBytes: Int
    let headerLines: [[String]]

    var topResult: String {
        headerLines.map { $0.map(Self.referenceText).joined(separator: "\u{1}") }.joined(separator: "\u{2}")
    }

    var senderAndSubject: String {
        guard let lines = headerLines.first else { return "" }
        let summary = MailHeaderParser.parse(lines: lines)
        return [summary.sender, summary.subject].map(Self.referenceText).joined(separator: "\u{1}")
    }

    private static func referenceText(_ value: String) -> String {
        String(value.prefix(4096)).filter { !$0.isNewline && !$0.unicodeScalars.contains(where: { $0.value < 32 }) }
    }
}

private final class POP3Connection: @unchecked Sendable {
    private final class StartState: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    private let connection: NWConnection
    private var buffer = Data()

    init(configuration: POP3Configuration) throws {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw URLError(.badURL)
        }
        let parameters: NWParameters = configuration.usesTLS ? .tls : .tcp
        connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: parameters)
    }

    func check(user: String, password: String) async throws -> POP3CheckResult {
        guard !user.contains(where: \.isNewline), !password.contains(where: \.isNewline) else { throw URLError(.badURL) }
        let timeout = Task { [connection] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            connection.cancel()
        }
        defer {
            timeout.cancel()
            connection.cancel()
        }
        try await start()
        try await expectOK(readLine())
        _ = try await command("USER \(user)")
        _ = try await command("PASS \(password)")
        let stat = try await command("STAT")
        let fields = stat.split(separator: " ")
        guard fields.count >= 3, let count = Int(fields[1]), let bytes = Int(fields[2]), count >= 0, bytes >= 0 else {
            throw URLError(.cannotParseResponse)
        }
        var headers: [[String]] = []
        if count > 0 {
            for index in stride(from: count, through: max(1, count - 19), by: -1) {
                // TOP is optional. An unsupported command leaves the session
                // synchronized, so preserve STAT counts without downloading bodies.
                try await send(Data("TOP \(index) 0\r\n".utf8))
                let status = try await readLine()
                if status.hasPrefix("-ERR") {
                    break
                }
                try expectOK(status)
                var lines: [String] = []
                var headerBytes = 0
                while true {
                    let line = try await readLine()
                    if line == "." {
                        break
                    }
                    headerBytes += line.utf8.count
                    guard headerBytes <= 64 * 1024, lines.count < 1000 else { throw URLError(.dataLengthExceedsMaximum) }
                    lines.append(line.hasPrefix("..") ? String(line.dropFirst()) : line)
                }
                headers.append(lines)
            }
        }
        _ = try? await command("QUIT")
        return POP3CheckResult(messageCount: count, totalBytes: bytes, headerLines: headers)
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let startState = StartState()
            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    guard startState.claim() else { return }
                    continuation.resume(returning: ())
                case let .failed(error), let .waiting(error):
                    guard startState.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard startState.claim() else { return }
                    continuation.resume(throwing: URLError(.timedOut))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func command(_ value: String) async throws -> String {
        try await send(Data("\(value)\r\n".utf8))
        let response = try await readLine()
        try expectOK(response)
        return response
    }

    private func expectOK(_ response: String) throws {
        guard response.hasPrefix("+OK") else {
            throw NSError(
                domain: "POP3",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: response]
            )
        }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data([0x0D, 0x0A])) {
                let line = buffer[..<range.lowerBound]
                buffer.removeSubrange(..<range.upperBound)
                return String(data: line, encoding: .utf8) ?? String(data: line, encoding: .shiftJIS) ?? String(decoding: line, as: UTF8.self)
            }
            let data = try await receive()
            guard !data.isEmpty else { throw URLError(.networkConnectionLost) }
            buffer.append(data)
            guard buffer.count <= 128 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        }
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

enum POP3MailChecker {
    static func check(configuration: POP3Configuration) async throws -> POP3CheckResult {
        try await POP3Connection(configuration: configuration).check(
            user: configuration.user,
            password: configuration.password
        )
    }
}

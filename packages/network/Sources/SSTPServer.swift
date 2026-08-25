import Foundation
import Network

public struct SSTPRequest: Sendable, Equatable {
    public let method: String
    public let version: String
    public let headers: [(name: String, value: String)]

    public init(method: String, version: String, headers: [(name: String, value: String)]) {
        self.method = method
        self.version = version
        self.headers = headers
    }

    public func value(for name: String) -> String? {
        headers.last { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public static func == (lhs: SSTPRequest, rhs: SSTPRequest) -> Bool {
        lhs.method == rhs.method && lhs.version == rhs.version
            && lhs.headers.elementsEqual(rhs.headers, by: { $0.name == $1.name && $0.value == $1.value })
    }
}

public struct SSTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let reason: String
    public let script: String?
    public let headers: [(name: String, value: String)]
    public let additionalData: String?

    public init(
        statusCode: Int = 200,
        reason: String = "OK",
        script: String? = nil,
        headers: [(name: String, value: String)] = [],
        additionalData: String? = nil
    ) {
        self.statusCode = statusCode
        self.reason = reason
        self.script = script
        self.headers = headers
        self.additionalData = additionalData
    }

    public var data: Data {
        var lines = ["SSTP/1.4 \(statusCode) \(reason)", "Charset: UTF-8"]
        if let script {
            lines.append("Script: \(script.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))")
        }
        lines.append(contentsOf: headers.map { "\($0.name): \($0.value)" })
        var source = lines.joined(separator: "\r\n") + "\r\n\r\n"
        if let additionalData {
            source += additionalData + "\r\n\r\n"
        }
        return Data(source.utf8)
    }

    public static func == (lhs: SSTPResponse, rhs: SSTPResponse) -> Bool {
        lhs.statusCode == rhs.statusCode && lhs.reason == rhs.reason && lhs.script == rhs.script
            && lhs.additionalData == rhs.additionalData
            && lhs.headers.elementsEqual(rhs.headers, by: { $0.name == $1.name && $0.value == $1.value })
    }
}

public enum SSTPError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case requestTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: "SSTPリクエストが不正"
        case .requestTooLarge: "SSTPリクエストが上限を超えている"
        }
    }
}

public final class SSTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (SSTPRequest) async -> SSTPResponse
    private let queue = DispatchQueue(label: "dev.utatane.sstp")
    private var listener: NWListener?
    private let maximumRequestBytes: Int

    public init(maximumRequestBytes: Int = 1024 * 1024) {
        self.maximumRequestBytes = maximumRequestBytes
    }

    public func start(port: UInt16 = 9801, handler: @escaping Handler) throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection, handler: handler)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public static func parse(_ data: Data) throws -> SSTPRequest {
        guard let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            throw SSTPError.invalidRequest
        }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let requestLine = lines.first else { throw SSTPError.invalidRequest }
        let requestParts = requestLine.split(separator: " ", maxSplits: 1).map(String.init)
        guard requestParts.count == 2,
              requestParts[1].hasPrefix("SSTP/"),
              let version = Double(requestParts[1].dropFirst("SSTP/".count)),
              version >= 1, version < 3
        else { throw SSTPError.invalidRequest }
        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty {
                break
            }
            guard let separator = line.firstIndex(of: ":") else { throw SSTPError.invalidRequest }
            headers.append((
                String(line[..<separator]).trimmingCharacters(in: .whitespaces),
                String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            ))
        }
        guard headers.contains(where: { $0.name.caseInsensitiveCompare("Charset") == .orderedSame }) else {
            throw SSTPError.invalidRequest
        }
        return SSTPRequest(method: requestParts[0].uppercased(), version: requestParts[1], headers: headers)
    }

    public static func parseHTTPRequest(_ data: Data) throws -> Data {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8)
        else { throw SSTPError.invalidRequest }
        let lines = headerText.components(separatedBy: "\r\n")
        guard lines.first == "POST /api/sstp/v1 HTTP/1.1" else { throw SSTPError.invalidRequest }
        let headers = try httpHeaders(lines.dropFirst())
        guard headers["content-type"]?.lowercased().hasPrefix("text/plain") == true,
              let lengthText = headers["content-length"],
              let length = Int(lengthText), length >= 0
        else { throw SSTPError.invalidRequest }
        if let origin = headers["origin"], !isLocalOrigin(origin) {
            throw SSTPError.invalidRequest
        }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) == length else {
            throw SSTPError.invalidRequest
        }
        return Data(data[bodyStart...])
    }

    public static func httpResponse(for response: SSTPResponse) -> Data {
        let body = response.data
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    private func receive(_ connection: NWConnection, handler: @escaping Handler) {
        connection.start(queue: queue)
        receiveChunk(connection, accumulated: Data(), handler: handler)
    }

    private func receiveChunk(_ connection: NWConnection, accumulated: Data, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var requestData = accumulated
            if let data {
                requestData.append(data)
            }
            if requestData.count > maximumRequestBytes {
                send(
                    SSTPResponse(statusCode: 413, reason: "Payload Too Large"),
                    asHTTP: requestData.starts(with: Data("POST ".utf8)),
                    on: connection
                )
                return
            }
            let terminated = isCompleteRequest(requestData)
            guard terminated || complete || error != nil else {
                receiveChunk(connection, accumulated: requestData, handler: handler)
                return
            }
            Task {
                let response: SSTPResponse
                let isHTTP = requestData.starts(with: Data("POST ".utf8))
                do {
                    let payload = isHTTP ? try Self.parseHTTPRequest(requestData) : requestData
                    let request = try Self.parse(payload)
                    guard ["SEND", "NOTIFY", "COMMUNICATE", "EXECUTE", "GIVE"].contains(request.method) else {
                        self.send(SSTPResponse(statusCode: 501, reason: "Not Implemented"), asHTTP: isHTTP, on: connection)
                        return
                    }
                    response = await handler(request)
                } catch {
                    response = SSTPResponse(statusCode: 400, reason: "Bad Request")
                }
                self.send(response, asHTTP: isHTTP, on: connection)
            }
        }
    }

    private func isCompleteRequest(_ data: Data) -> Bool {
        guard data.starts(with: Data("POST ".utf8)) else {
            return data.range(of: Data("\r\n\r\n".utf8)) != nil || data.range(of: Data("\n\n".utf8)) != nil
        }
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let text = String(data: data[..<headerEnd.lowerBound], encoding: .utf8),
              let headers = try? Self.httpHeaders(text.components(separatedBy: "\r\n").dropFirst()),
              let lengthText = headers["content-length"], let length = Int(lengthText)
        else { return false }
        return data.distance(from: headerEnd.upperBound, to: data.endIndex) >= length
    }

    private static func httpHeaders(_ lines: ArraySlice<String>) throws -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { throw SSTPError.invalidRequest }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        return headers
    }

    private static func isLocalOrigin(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func send(_ response: SSTPResponse, asHTTP: Bool = false, on connection: NWConnection) {
        let data = asHTTP ? Self.httpResponse(for: response) : response.data
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

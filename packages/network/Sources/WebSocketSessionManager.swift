import Foundation

public enum WebSocketSessionEvent: Sendable, Equatable {
    case open(url: String, eventID: String)
    case text(url: String, eventID: String, value: String)
    case binary(url: String, eventID: String, value: Data)
    case close(url: String, eventID: String, reason: String)
    case failure(url: String, eventID: String, message: String)

    public var shioriEvent: (id: String, references: [Int: String]) {
        switch self {
        case let .open(url, eventID):
            (eventID.hasPrefix("On") ? "\(eventID)Open" : "OnExecuteWebSocketOpen", [0: eventID, 1: url, 2: "200"])
        case let .text(url, eventID, value):
            (eventID.hasPrefix("On") ? eventID : "OnExecuteWebSocketReceive", [
                0: eventID, 1: url, 2: "1",
                3: value.replacingOccurrences(of: "\r\n", with: "\u{1}")
                    .replacingOccurrences(of: "\r", with: "\u{1}")
                    .replacingOccurrences(of: "\n", with: "\u{1}")
            ])
        case let .binary(url, eventID, value):
            (eventID.hasPrefix("On") ? eventID : "OnExecuteWebSocketReceive", [
                0: eventID, 1: url, 2: "2", 3: value.base64EncodedString()
            ])
        case let .close(url, eventID, reason):
            (eventID.hasPrefix("On") ? "\(eventID)Close" : "OnExecuteWebSocketClose", [0: eventID, 1: url, 2: reason])
        case let .failure(url, eventID, message):
            (eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExecuteWebSocketFailure", [0: eventID, 1: url, 2: message])
        }
    }
}

public actor WebSocketSessionManager {
    public typealias EventHandler = @Sendable (WebSocketSessionEvent) async -> Void

    private var sessions: [String: WebSocketConnection] = [:]

    public init() {}

    public func connect(
        url: String,
        eventID: String,
        headers: [String: String] = [:],
        protocolName: String? = nil,
        onEvent: @escaping EventHandler
    ) {
        sessions[url]?.cancel(notifies: false)
        guard let parsedURL = URL(string: url), ["ws", "wss"].contains(parsedURL.scheme?.lowercased()) else {
            Task { await onEvent(.failure(url: url, eventID: eventID, message: "invalid URL")) }
            return
        }
        let connection = WebSocketConnection(
            url: parsedURL,
            originalURL: url,
            eventID: eventID,
            headers: headers,
            protocolName: protocolName,
            onEvent: onEvent
        )
        sessions[url] = connection
        connection.start()
    }

    public func sendText(url: String, value: String) async {
        try? await sessions[url]?.send(.string(value))
    }

    public func sendBinary(url: String, value: Data) async {
        try? await sessions[url]?.send(.data(value))
    }

    public func close(url: String, code: Int = 1000) {
        sessions.removeValue(forKey: url)?.close(code: code)
    }

    public func cancel(url: String) {
        sessions.removeValue(forKey: url)?.cancel(notifies: true)
    }

    public func cancelAll() {
        for connection in sessions.values {
            connection.cancel(notifies: true)
        }
        sessions.removeAll()
    }
}

private final class WebSocketConnection: @unchecked Sendable {
    private let originalURL: String
    private let eventID: String
    private let task: URLSessionWebSocketTask
    private let onEvent: WebSocketSessionManager.EventHandler
    private var receiveTask: Task<Void, Never>?

    init(
        url: URL,
        originalURL: String,
        eventID: String,
        headers: [String: String],
        protocolName: String?,
        onEvent: @escaping WebSocketSessionManager.EventHandler
    ) {
        self.originalURL = originalURL
        self.eventID = eventID
        self.onEvent = onEvent
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let protocolName {
            request.setValue(protocolName, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        task = URLSession.shared.webSocketTask(with: request)
    }

    func start() {
        task.resume()
        receiveTask = Task { [task, originalURL, eventID, onEvent] in
            await onEvent(.open(url: originalURL, eventID: eventID))
            do {
                while !Task.isCancelled {
                    switch try await task.receive() {
                    case let .string(value): await onEvent(.text(url: originalURL, eventID: eventID, value: value))
                    case let .data(value): await onEvent(.binary(url: originalURL, eventID: eventID, value: value))
                    @unknown default: break
                    }
                }
            } catch is CancellationError {
            } catch {
                await onEvent(.failure(url: originalURL, eventID: eventID, message: error.localizedDescription))
            }
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }

    func close(code: Int) {
        receiveTask?.cancel()
        task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
        Task { await onEvent(.close(url: originalURL, eventID: eventID, reason: String(code))) }
    }

    func cancel(notifies: Bool) {
        receiveTask?.cancel()
        task.cancel()
        if notifies {
            Task { await onEvent(.close(url: originalURL, eventID: eventID, reason: "userbreak")) }
        }
    }
}

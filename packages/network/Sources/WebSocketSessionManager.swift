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
    private let onEvent: WebSocketSessionManager.EventHandler
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var delegate: WebSocketDelegate?
    private var receiveTask: Task<Void, Never>?
    private let stateLock = NSLock()
    private var didNotifyClose = false

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
        let delegate = WebSocketDelegate(
            onOpen: { [weak self] in self?.notifyOpen() },
            onClose: { [weak self] code in self?.notifyClose(reason: String(code)) }
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.delegate = delegate
        self.session = session
        task = session.webSocketTask(with: request)
    }

    func start() {
        guard let task else { return }
        task.resume()
        receiveTask = Task { [task, originalURL, eventID, onEvent] in
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
        try await task?.send(message)
    }

    func close(code: Int) {
        receiveTask?.cancel()
        task?.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
        notifyClose(reason: String(code))
    }

    func cancel(notifies: Bool) {
        receiveTask?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        if notifies {
            notifyClose(reason: "userbreak")
        }
    }

    private func notifyOpen() {
        Task { await onEvent(.open(url: originalURL, eventID: eventID)) }
    }

    private func notifyClose(reason: String) {
        let shouldNotify = stateLock.withLock {
            guard !didNotifyClose else { return false }
            didNotifyClose = true
            return true
        }
        guard shouldNotify else { return }
        Task { await onEvent(.close(url: originalURL, eventID: eventID, reason: reason)) }
    }
}

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let onOpen: @Sendable () -> Void
    private let onClose: @Sendable (Int) -> Void

    init(onOpen: @escaping @Sendable () -> Void, onClose: @escaping @Sendable (Int) -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose
    }

    func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didOpenWithProtocol _: String?
    ) {
        onOpen()
    }

    func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason _: Data?
    ) {
        onClose(closeCode.rawValue)
    }
}

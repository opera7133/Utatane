import Foundation

public enum WebSocketSessionEvent: Sendable, Equatable {
    case open(url: String, eventID: String)
    case reconnect(url: String, eventID: String)
    case sslInfo(
        url: String,
        eventID: String,
        protocolVersion: String,
        cipherSuite: String,
        subject: String,
        issuer: String,
        chain: [String]
    )
    case text(url: String, eventID: String, value: String)
    case binary(url: String, eventID: String, value: Data)
    case close(url: String, eventID: String, reason: String)
    case failure(url: String, eventID: String, message: String)

    public var shioriEvent: (id: String, references: [Int: String]) {
        switch self {
        case let .open(url, eventID):
            (eventID.hasPrefix("On") ? "\(eventID)Open" : "OnExecuteWebSocketOpen", [0: eventID, 1: url, 2: "200"])
        case let .reconnect(url, eventID):
            (eventID.hasPrefix("On") ? "\(eventID)Reconnect" : "OnExecuteWebSocketReconnect", [
                0: eventID, 1: url, 2: "200"
            ])
        case let .sslInfo(url, eventID, protocolVersion, cipherSuite, subject, issuer, chain):
            ("OnExecuteWebSocket_SSLInfo", [
                0: eventID, 1: url, 2: "200", 3: protocolVersion, 4: cipherSuite,
                5: subject, 6: "", 7: "", 8: issuer, 9: chain.joined(separator: ",")
            ])
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
    private let request: URLRequest
    private let originalURL: String
    private let eventID: String
    private let onEvent: WebSocketSessionManager.EventHandler
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var delegate: WebSocketDelegate?
    private var receiveTask: Task<Void, Never>?
    private let stateLock = NSLock()
    private var didNotifyClose = false
    private var reconnectAttempts = 0
    private var reconnectScheduled = false
    private var closedByUser = false

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
        self.request = request
    }

    func start() {
        open()
    }

    private func open() {
        let isReconnect = stateLock.withLock { reconnectAttempts > 0 }
        let delegate = WebSocketDelegate(
            onOpen: { [weak self] in self?.notifyOpen(isReconnect: isReconnect) },
            onClose: { [weak self] code in self?.connectionClosed(code: code) },
            onTLS: { [weak self] protocolVersion, cipherSuite in
                self?.notifyTLS(protocolVersion: protocolVersion, cipherSuite: cipherSuite)
            }
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.delegate = delegate
        self.session = session
        task = session.webSocketTask(with: request)
        guard let task else { return }
        task.resume()
        receiveTask = Task { [weak self, task, originalURL, eventID, onEvent] in
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
                self?.scheduleReconnect(reason: error.localizedDescription)
            }
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task?.send(message)
    }

    func close(code: Int) {
        stateLock.withLock { closedByUser = true }
        receiveTask?.cancel()
        task?.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
        notifyClose(reason: String(code))
    }

    func cancel(notifies: Bool) {
        stateLock.withLock { closedByUser = true }
        receiveTask?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        if notifies {
            notifyClose(reason: "userbreak")
        }
    }

    private func notifyOpen(isReconnect: Bool) {
        stateLock.withLock { reconnectScheduled = false }
        Task {
            await onEvent(isReconnect
                ? .reconnect(url: originalURL, eventID: eventID)
                : .open(url: originalURL, eventID: eventID))
        }
    }

    private func connectionClosed(code: Int) {
        if code == URLSessionWebSocketTask.CloseCode.normalClosure.rawValue
            || stateLock.withLock({ closedByUser })
        {
            notifyClose(reason: String(code))
        } else {
            scheduleReconnect(reason: String(code))
        }
    }

    private func scheduleReconnect(reason: String) {
        let attempt: Int? = stateLock.withLock {
            guard !closedByUser, !reconnectScheduled else { return nil }
            reconnectAttempts += 1
            guard reconnectAttempts <= 5 else { return 0 }
            reconnectScheduled = true
            return reconnectAttempts
        }
        guard let attempt else { return }
        guard attempt > 0 else {
            Task { await onEvent(.failure(url: originalURL, eventID: eventID, message: "reconnect failed")) }
            return
        }
        receiveTask?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(min(attempt, 5)))
            guard let self else { return }
            stateLock.withLock { reconnectScheduled = false }
            open()
        }
    }

    private func notifyTLS(protocolVersion: String, cipherSuite: String) {
        guard originalURL.lowercased().hasPrefix("wss://") else { return }
        Task {
            await onEvent(.sslInfo(
                url: originalURL,
                eventID: eventID,
                protocolVersion: protocolVersion,
                cipherSuite: cipherSuite,
                subject: "",
                issuer: "",
                chain: []
            ))
        }
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
    private let onTLS: @Sendable (String, String) -> Void

    init(
        onOpen: @escaping @Sendable () -> Void,
        onClose: @escaping @Sendable (Int) -> Void,
        onTLS: @escaping @Sendable (String, String) -> Void
    ) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onTLS = onTLS
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

    func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last,
              let protocolVersion = transaction.negotiatedTLSProtocolVersion
        else { return }
        onTLS(
            String(describing: protocolVersion),
            transaction.negotiatedTLSCipherSuite.map(String.init(describing:)) ?? ""
        )
    }
}

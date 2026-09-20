import Foundation
import Security

struct HTTPTransferTLSInfo: Sendable, Equatable {
    var protocolVersion = ""
    var cipherSuite = ""
    var subject = ""
    var issuer = ""
    var chainCommonNames: [String] = []
}

struct HTTPTransferResult: @unchecked Sendable {
    let data: Data
    let response: URLResponse
    let tlsInfo: HTTPTransferTLSInfo?
}

final class HTTPTransferClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (Data, HTTPURLResponse) async -> Void
    typealias StreamingHandler = @Sendable (String, HTTPURLResponse) async -> Void

    private let progressHandler: ProgressHandler?
    private let streamingHandler: StreamingHandler?
    private var data = Data()
    private var lineBuffer = Data()
    private var response: URLResponse?
    private var tlsInfo: HTTPTransferTLSInfo?
    private var callbackTasks: [Task<Void, Never>] = []
    private var continuation: CheckedContinuation<HTTPTransferResult, Error>?
    private var session: URLSession?

    private init(progress: ProgressHandler?, streaming: StreamingHandler?) {
        progressHandler = progress
        streamingHandler = streaming
    }

    static func perform(
        _ request: URLRequest,
        progress: ProgressHandler? = nil,
        streaming: StreamingHandler? = nil
    ) async throws -> HTTPTransferResult {
        let client = HTTPTransferClient(progress: progress, streaming: streaming)
        return try await withCheckedThrowingContinuation { continuation in
            client.continuation = continuation
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: .default, delegate: client, delegateQueue: queue)
            client.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        guard let response = response as? HTTPURLResponse else { return }
        if let progressHandler {
            let snapshot = data
            callbackTasks.append(Task { await progressHandler(snapshot, response) })
        }
        guard let streamingHandler else { return }
        lineBuffer.append(chunk)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            var line = lineBuffer.prefix(upTo: newline)
            if line.last == 0x0D {
                line = line.dropLast()
            }
            lineBuffer.removeSubrange(...newline)
            let value = String(data: line, encoding: .utf8) ?? ""
            callbackTasks.append(Task { await streamingHandler(value, response) })
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last,
              transaction.negotiatedTLSProtocolVersion != nil
        else { return }
        var info = tlsInfo ?? .init()
        info.protocolVersion = transaction.negotiatedTLSProtocolVersion.map(String.init(describing:)) ?? ""
        info.cipherSuite = transaction.negotiatedTLSCipherSuite.map(String.init(describing:)) ?? ""
        tlsInfo = info
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust
        {
            let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
            let names = certificates.compactMap { SecCertificateCopySubjectSummary($0) as String? }
            var info = tlsInfo ?? .init()
            info.subject = names.first ?? ""
            info.issuer = names.dropFirst().first ?? ""
            info.chainCommonNames = names
            tlsInfo = info
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let streamingHandler, !lineBuffer.isEmpty, let response = response as? HTTPURLResponse {
            let value = String(data: lineBuffer, encoding: .utf8) ?? ""
            callbackTasks.append(Task { await streamingHandler(value, response) })
        }
        let continuation = continuation
        self.continuation = nil
        let callbacks = callbackTasks
        let data = data
        let response = response
        let tlsInfo = tlsInfo
        session?.finishTasksAndInvalidate()
        session = nil
        Task {
            for task in callbacks {
                await task.value
            }
            if let error {
                continuation?.resume(throwing: error)
            } else if let response {
                continuation?.resume(returning: HTTPTransferResult(
                    data: data,
                    response: response,
                    tlsInfo: tlsInfo
                ))
            } else {
                continuation?.resume(throwing: URLError(.badServerResponse))
            }
        }
    }
}

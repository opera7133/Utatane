import Foundation
import Security

public struct HTTPTransferTLSInfo: Sendable, Equatable {
    public var protocolVersion = ""
    public var cipherSuite = ""
    public var subject = ""
    public var issuer = ""
    public var chainCommonNames: [String] = []
}

public struct HTTPTransferResult: @unchecked Sendable {
    public let data: Data
    public let response: URLResponse
    public let tlsInfo: HTTPTransferTLSInfo?
}

public enum HTTPTransferClient {
    public typealias ProgressHandler = @Sendable (Data, HTTPURLResponse) async -> Void
    public typealias StreamingHandler = @Sendable (String, HTTPURLResponse) async -> Void

    public static func perform(
        _ request: URLRequest,
        progress: ProgressHandler? = nil,
        streaming: StreamingHandler? = nil,
        session: URLSession = .shared
    ) async throws -> HTTPTransferResult {
        let delegate = TransferDelegate()
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        defer { bytes.task.cancel() }
        return try await withTaskCancellationHandler {
            let data = try await consume(bytes, response: response, progress: progress, streaming: streaming)
            return HTTPTransferResult(data: data, response: response, tlsInfo: delegate.snapshot())
        } onCancel: {
            bytes.task.cancel()
        }
    }

    /// Await each notification before consuming further bytes. Do not retain a
    /// task and a full-body snapshot for every chunk while a ghost is suspended.
    static func consume<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        response: URLResponse,
        progress: ProgressHandler?,
        streaming: StreamingHandler?
    ) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        var lineBuffer = Data()
        let http = response as? HTTPURLResponse
        var lastProgressCount = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if let http, let streaming {
                if byte == 0x0A {
                    if lineBuffer.last == 0x0D {
                        lineBuffer.removeLast()
                    }
                    await streaming(String(decoding: lineBuffer, as: UTF8.self), http)
                    lineBuffer.removeAll(keepingCapacity: true)
                } else {
                    lineBuffer.append(byte)
                }
            }
            if let http, let progress, data.count - lastProgressCount >= 64 * 1024 {
                await progress(data, http)
                lastProgressCount = data.count
            }
        }
        try Task.checkCancellation()
        if let http, let streaming, !lineBuffer.isEmpty {
            await streaming(String(decoding: lineBuffer, as: UTF8.self), http)
        }
        try Task.checkCancellation()
        if let http, let progress, data.count != lastProgressCount {
            await progress(data, http)
        }
        try Task.checkCancellation()
        return data
    }
}

private final class TransferDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var tlsInfo: HTTPTransferTLSInfo?

    func snapshot() -> HTTPTransferTLSInfo? {
        lock.lock()
        defer { lock.unlock() }
        return tlsInfo
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last,
              transaction.negotiatedTLSProtocolVersion != nil
        else { return }
        lock.lock()
        defer { lock.unlock() }
        var info = tlsInfo ?? .init()
        info.protocolVersion = transaction.negotiatedTLSProtocolVersion.map(String.init(describing:)) ?? ""
        info.cipherSuite = transaction.negotiatedTLSCipherSuite.map(String.init(describing:)) ?? ""
        tlsInfo = info
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust
        {
            let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
            let names = certificates.compactMap { SecCertificateCopySubjectSummary($0) as String? }
            lock.lock()
            var info = tlsInfo ?? .init()
            info.subject = names.first ?? ""
            info.issuer = names.dropFirst().first ?? ""
            info.chainCommonNames = names
            tlsInfo = info
            lock.unlock()
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

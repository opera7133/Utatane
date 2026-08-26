import Foundation

public protocol AkariHTTPFetching: Sendable {
    func fetch(url: URL, maximumBytes: Int) -> Data?
}

public final class AkariURLSessionHTTPFetcher: AkariHTTPFetching, @unchecked Sendable {
    public init() {}

    public func fetch(url: URL, maximumBytes: Int) -> Data? {
        guard ["http", "https"].contains(url.scheme?.lowercased()), maximumBytes > 0 else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        let result = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: url) { data, response, _ in
            defer { semaphore.signal() }
            guard let response = response as? HTTPURLResponse,
                  (200 ..< 300).contains(response.statusCode),
                  ["http", "https"].contains(response.url?.scheme?.lowercased()),
                  response.expectedContentLength <= Int64(maximumBytes),
                  let data, data.count <= maximumBytes
            else { return }
            result.data = data
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 16) == .timedOut {
            task.cancel()
        }
        session.invalidateAndCancel()
        return result.data
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?

    var data: Data? {
        get { lock.withLock { storedData } }
        set { lock.withLock { storedData = newValue } }
    }
}

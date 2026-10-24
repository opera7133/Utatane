import Foundation
import UtataneCore

/// Private host service for conventional httpc's bg request. It deliberately
/// does not add an external SSTP listener or use the currently displayed ghost.
final class LegacyHttpcSession: @unchecked Sendable {
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.utatane.httpc"
        queue.maxConcurrentOperationCount = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))
        return queue
    }()

    private let lock = NSLock()
    private var closed = false
    private var jobs: [UUID: (Job, Lifetime, URL)] = [:]
    private var lifetimes: [URL: Lifetime] = [:]
    private let onEvent: (@Sendable (InternalSaoriEvent) -> Void)?
    private let fetch: @Sendable (URL, Job) -> (Data, String?)?
    private let operationQueue: OperationQueue

    init(onEvent: (@Sendable (InternalSaoriEvent) -> Void)?, queue: OperationQueue? = nil,
         fetch: @escaping @Sendable (URL, Job) -> (Data, String?)? = LegacyHttpcSession.fetchURL)
    {
        self.onEvent = onEvent
        self.fetch = fetch
        operationQueue = queue ?? Self.queue
    }

    private var isCurrent: Bool {
        lock.withLock { !closed }
    }

    func close() {
        let tasks = lock.withLock {
            closed = true
            lifetimes.values.forEach { $0.invalidate() }
            return jobs.values.map(\.0)
        }
        tasks.forEach { $0.cancel() }
    }

    func response(headers: [String: String], charset: String) -> Data {
        func reply(_ status: Int, _ error: String? = nil) -> Data {
            var wire = "SAORI/1.0 \(status) \(status == 204 ? "No Content" : "Bad Request")\r\nCharset: \(charset)\r\n"
            if let error {
                wire += "ErrorDescription: \(error)\r\n"
            }
            return LegacyTextDecoder.encode(wire + "\r\n", charset: charset) ?? Data()
        }
        guard let directory = headers["directory"], directory.hasPrefix("/"),
              (try? URL(filePath: directory).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return reply(400, "invalid parameter") }
        let resourceDirectory = URL(filePath: directory).standardizedFileURL
        let arguments = headers.filter { $0.key.hasPrefix("argument") }
        guard !arguments.isEmpty, arguments.count < 256,
              arguments.keys.allSatisfy({ key in Int(key.dropFirst(8)).map { $0 >= 0 && String($0) == key.dropFirst(8) } == true }),
              (0 ..< arguments.count).allSatisfy({ arguments["argument\($0)"] != nil }) else { return reply(400, "invalid parameter") }
        let args = (0 ..< arguments.count).map { arguments["argument\($0)"]! }
        if args == ["cancel"] {
            let tasks = lock.withLock {
                lifetimes.removeValue(forKey: resourceDirectory)?.invalidate()
                return jobs.values.filter { $0.2 == resourceDirectory }.map(\.0)
            }
            tasks.forEach { $0.cancel() }
            return reply(204)
        }
        guard args.count >= 3, args[0] == "bg", !args[1].isEmpty else { return reply(400, "invalid parameter") }
        guard let onEvent else { return reply(400, "ghost required") }
        var parameters = Array(args.dropFirst(2))
        let options = HttpcTextOptions(arguments: &parameters)
        guard (1 ... 3).contains(parameters.count), let url = URL(string: parameters[0]),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return reply(400, "invalid parameter") }
        let job = Job(), id = UUID()
        let lifetime = lock.withLock { () -> Lifetime? in
            guard !closed, jobs.count < 64, lifetimes[resourceDirectory] != nil || lifetimes.count < 64 else { return nil }
            let lifetime = lifetimes[resourceDirectory] ?? Lifetime()
            lifetimes[resourceDirectory] = lifetime
            jobs[id] = (job, lifetime, resourceDirectory)
            return lifetime
        }
        guard let lifetime else { return reply(400, "too many requests") }
        let requestParameters = parameters, encoding = options.charset, identifier = args[1]
        operationQueue.addOperation { [weak self] in
            guard let self else { return }
            defer { _ = lock.withLock { jobs.removeValue(forKey: id) } }
            guard isCurrent, job.isCurrent, lifetime.isCurrent else { return }
            let response = fetch(url, job)
            guard isCurrent, job.isCurrent, lifetime.isCurrent else { return }
            let results = lock.withLock { () -> [String] in
                guard !closed, job.isCurrent, lifetime.isCurrent else { return [""] }
                guard let (data, charset) = response else { return [requestParameters.count == 2 ? "0" : ""] }
                if requestParameters.count == 2 {
                    let path = requestParameters[1].replacingOccurrences(of: "\\", with: "/")
                    guard !path.isEmpty else { return ["0"] }
                    let file = path.hasPrefix("/") ? URL(filePath: path) : resourceDirectory.appending(path: path)
                    do { try data.write(to: file, options: .atomic); return ["1"] } catch { return ["0"] }
                }
                let text: String? = if let encoding {
                    LegacyTextDecoder.decode(data, strictlyUsing: encoding)
                } else {
                    LegacyTextDecoder.decode(data, preferredCharset: charset)
                }
                guard let text else { return [""] }
                let clean = options.process(text)
                guard clean.utf8.count <= 2 * 1024 * 1024 else { return [""] }
                guard requestParameters.count == 3 else { return [clean] }
                let left = requestParameters[1], right = requestParameters[2]
                guard !left.isEmpty, !right.isEmpty else { return [""] }
                var values: [String] = [], start = clean.startIndex
                while values.count < 254, let begin = clean.range(of: left, range: start ..< clean.endIndex),
                      let end = clean.range(of: right, range: begin.upperBound ..< clean.endIndex)
                {
                    values.append(String(clean[begin.upperBound ..< end.lowerBound])); start = end.upperBound
                }
                return values.isEmpty ? [""] : values
            }
            guard isCurrent, job.isCurrent, lifetime.isCurrent else { return }
            var references = [0: identifier, 1: "-"]
            for (index, value) in results.enumerated() {
                references[index + 2] = value
            }
            onEvent(InternalSaoriEvent(id: "OnHttpcNotify", references: references, validity: { [weak self, lifetime] in
                self?.isCurrent == true && lifetime.isCurrent
            }))
        }
        return reply(204)
    }

    final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var task: URLSessionTask?
        var isCurrent: Bool {
            lock.withLock { !cancelled }
        }

        func install(_ task: URLSessionTask) {
            let cancel = lock.withLock { self.task = task; return cancelled }
            if cancel {
                task.cancel()
            }
        }

        func clear() {
            lock.withLock { task = nil }
        }

        func cancel() {
            let task = lock.withLock { cancelled = true; let value = self.task; self.task = nil; return value }
            task?.cancel()
        }
    }

    private final class Lifetime: @unchecked Sendable {
        private let lock = NSLock()
        private var current = true
        var isCurrent: Bool {
            lock.withLock { current }
        }

        func invalidate() {
            lock.withLock { current = false }
        }
    }

    private static func fetchURL(_ url: URL, job: Job) -> (Data, String?)? {
        let collector = HttpcCollector()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        defer { session.invalidateAndCancel(); job.clear() }
        let task = session.dataTask(with: url)
        job.install(task); task.resume()
        guard collector.ready.wait(timeout: .now() + 35) == .success, job.isCurrent else { return nil }
        return collector.result
    }
}

private final class HttpcCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var succeeded = false
    var result: (Data, String?)? {
        lock.withLock { succeeded ? (data, response?.textEncodingName) : nil }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void)
    {
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), response.expectedContentLength <= 32 * 1024 * 1024 else { completionHandler(.cancel); return }
        lock.withLock { self.response = http }; completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let accepted = lock.withLock {
            guard self.data.count + data.count <= 32 * 1024 * 1024 else { return false }
            self.data.append(data); return true
        }
        if !accepted {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.withLock { succeeded = error == nil && response != nil }; ready.signal()
    }
}

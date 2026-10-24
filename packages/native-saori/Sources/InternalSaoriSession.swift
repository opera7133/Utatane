import Foundation
import UtataneCore

public struct InternalSaoriEvent: Sendable {
    public let id: String
    public let references: [Int: String]
    private let validity: @Sendable () -> Bool
    public var isCurrent: Bool {
        validity()
    }

    init(id: String, references: [Int: String], validity: @escaping @Sendable () -> Bool) {
        self.id = id
        self.references = references
        self.validity = validity
    }
}

/// Owns asynchronous callbacks for exactly one loaded SHIORI lifetime.
public final class InternalSaoriSession: @unchecked Sendable {
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.utatane.internal-saori"
        queue.maxConcurrentOperationCount = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))
        return queue
    }()

    private let diagnosticID = UUID()
    private let lock = NSLock()
    private var closed = false
    private var pending = 0
    private let onEvent: (@Sendable (InternalSaoriEvent) -> Void)?
    private let service: InternalSaoriService
    private let operationQueue: OperationQueue

    public init(onEvent: (@Sendable (InternalSaoriEvent) -> Void)? = nil, service: InternalSaoriService = .init()) {
        self.service = service
        self.onEvent = onEvent
        operationQueue = Self.queue
    }

    init(onEvent: @escaping @Sendable (InternalSaoriEvent) -> Void, queue: OperationQueue) {
        service = .init()
        self.onEvent = onEvent
        operationQueue = queue
    }

    public func close() {
        lock.withLock { closed = true }
    }

    private var isCurrent: Bool {
        lock.withLock { !closed }
    }

    public func response(to data: Data) -> Data {
        let started = DispatchTime.now().uptimeNanoseconds
        let result = process(data)
        InternalSaoriDiagnostics.shared.record(request: data, response: result, started: started, session: diagnosticID)
        return result
    }

    private func process(_ data: Data) -> Data {
        guard isCurrent else { return error("ghost required") }
        guard data.count <= InternalSaoriService.maximumBytes,
              !data.contains(0), data.suffix(4) == Data("\r\n\r\n".utf8),
              let ascii = String(data: data, encoding: .isoLatin1) else { return service.response(to: data) }
        let charsetLine = ascii.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("charset:") }
        let charset = charsetLine?.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "UTF-8"
        guard let wire = LegacyTextDecoder.decode(data, strictlyUsing: charset.lowercased() == "shift_jis" ? "CP932" : charset) else { return service.response(to: data) }
        let lines = wire.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty {
                break
            }
            guard !line.contains("\r"), !line.contains("\n"), let colon = line.firstIndex(of: ":") else { return service.response(to: data) }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { return service.response(to: data) }
            headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard lines.first == "EXECUTE SAORI/1.0", let module = headers["module"].flatMap(InternalSaoriService.moduleName),
              let function = headers["argument0"], let count = InternalSaoriService.positionalCount(module: module, function: function) else { return service.response(to: data) }
        let asyncArguments = headers.compactMap { key, value -> (Int, String)? in
            guard key.hasPrefix("argument"), let index = Int(key.dropFirst(8)), index > count,
                  value.lowercased().hasPrefix("--async=") else { return nil }
            return (index, String(value.dropFirst(8)))
        }
        guard !asyncArguments.isEmpty else { return service.response(to: data) }
        guard let (_, identifier) = asyncArguments.max(by: { $0.0 < $1.0 }),
              !identifier.isEmpty, !identifier.contains("\r"), !identifier.contains("\n") else { return error("invalid parameter", charset: charset) }
        guard onEvent != nil else { return error("ghost required", charset: charset) }
        let argumentKeys = headers.keys.filter { $0.hasPrefix("argument") }
        let indices = argumentKeys.compactMap { Int($0.dropFirst(8)) }
        guard indices.count == argumentKeys.count,
              argumentKeys.allSatisfy({ key in Int(key.dropFirst(8)).map { String($0) == key.dropFirst(8) && $0 >= 0 } == true })
        else {
            return error("invalid parameter", charset: charset)
        }
        guard let last = indices.max(), indices.count == last + 1, last < 256 else { return error("invalid parameter", charset: charset) }
        let asyncIndices = Set(asyncArguments.map(\.0))
        let arguments = (0 ... last).filter { !asyncIndices.contains($0) }.map { headers["argument\($0)"] ?? "" }
        let request = (["EXECUTE SAORI/1.0", "Charset: \(charset)", "Module: \(module)"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
        guard let encoded = LegacyTextDecoder.encode(request, charset: charset) else { return error("invalid encoding", charset: charset) }
        let validation = service.response(to: encoded, validatesOnly: true)
        guard String(decoding: validation.prefix(16), as: UTF8.self).hasPrefix("SAORI/1.0 204") else { return validation }
        let accepted = lock.withLock {
            guard !closed, pending < 64 else { return false }
            pending += 1
            return true
        }
        guard accepted else { return error("too many requests", status: 500, charset: charset) }
        operationQueue.addOperation { [weak self] in
            guard let self else { return }
            defer { lock.withLock { pending -= 1 } }
            guard isCurrent else { return }
            let started = DispatchTime.now().uptimeNanoseconds
            let data = service.response(to: encoded, isCancelled: { [weak self] in self?.isCurrent != true })
            InternalSaoriDiagnostics.shared.record(request: encoded, response: data, started: started, session: diagnosticID, completion: true)
            guard let result = LegacyTextDecoder.decode(data, strictlyUsing: charset.lowercased() == "shift_jis" ? "CP932" : charset) else { return }
            var fields: [String: String] = [:]
            for line in result.components(separatedBy: "\r\n").dropFirst() {
                guard let separator = line.firstIndex(of: ":") else { continue }
                fields[line[..<separator].lowercased()] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            }
            let success = result.hasPrefix("SAORI/1.0 200") || result.hasPrefix("SAORI/1.0 204")
            let id = identifier.hasPrefix("On") ? identifier + (success ? "" : "Failure") : (success ? "OnInternalSaoriComplete" : "OnInternalSaoriFailure")
            var references = [0: identifier, 1: fields[success ? "result" : "errordescription"] ?? "", 2: module, 3: function]
            if success {
                for (key, value) in fields where key.hasPrefix("value") {
                    if let index = Int(key.dropFirst(5)), index >= 0, index < 256 {
                        references[index + 4] = value
                    }
                }
            }
            guard isCurrent else { return }
            onEvent?(InternalSaoriEvent(id: id, references: references, validity: { [weak self] in self?.isCurrent == true }))
        }
        return LegacyTextDecoder.encode("SAORI/1.0 204 No Content\r\nCharset: \(charset)\r\n\r\n", charset: charset) ?? error("invalid encoding")
    }

    private func error(_ description: String, status: Int = 400, charset: String = "UTF-8") -> Data {
        LegacyTextDecoder.encode("SAORI/1.0 \(status) \(status == 500 ? "Internal Server Error" : "Bad Request")\r\nCharset: \(charset)\r\nErrorDescription: \(description)\r\n\r\n", charset: charset) ?? Data()
    }
}

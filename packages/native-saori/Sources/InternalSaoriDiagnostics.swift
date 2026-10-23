import Foundation
import UtataneCore

/// Opt-in metadata only. Argument values, results and async identifiers never enter logs.
public final class InternalSaoriDiagnostics: @unchecked Sendable {
    public static let shared = InternalSaoriDiagnostics()
    private let lock = NSLock()
    private var enabled = false
    private let store: AppLogStore
    public init(store: AppLogStore = .shared) {
        self.store = store
    }

    public var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }

    func record(request: Data, response: Data, started: UInt64, session: UUID, completion: Bool = false) {
        guard isEnabled else { return }
        store.info(Self.summary(request: request, response: response, started: started, session: session, completion: completion), category: "InternalSAORI")
    }

    static func summary(request: Data, response: Data, started: UInt64, session: UUID, completion: Bool) -> String {
        /// Metadata is ASCII. Avoid decoding or retaining potentially sensitive argument bodies.
        func field(_ data: Data, _ name: String) -> String? {
            for line in String(decoding: data.prefix(4096), as: UTF8.self).components(separatedBy: "\r\n") {
                guard let colon = line.firstIndex(of: ":"), line[..<colon].caseInsensitiveCompare(name) == .orderedSame else { continue }
                return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        func token(_ value: String?) -> String {
            guard let value, value.count <= 64, !value.isEmpty,
                  value.utf8.allSatisfy({ (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 95 }) else { return "?" }
            return value
        }
        let status = Int(String(decoding: response.prefix(16), as: UTF8.self).split(separator: " ").dropFirst().first ?? "") ?? 0
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000
        return "session=\(session.uuidString) phase=\(completion ? "complete" : "response") module=\(token(field(request, "Module"))) function=\(token(field(request, "Argument0"))) status=\(status) elapsed_ms=\(String(format: "%.3f", elapsed)) response_bytes=\(response.count)"
    }
}

public struct InternalSaoriProbeResult: Sendable {
    public let response: String
    public let elapsedMilliseconds: Double
}

public enum InternalSaoriProbe {
    /// Direct baseware-only probe. It does not send events to a running ghost.
    public static func run(module: String, arguments: [String]) -> InternalSaoriProbeResult {
        let start = DispatchTime.now().uptimeNanoseconds
        guard InternalSaoriService.moduleName(module) == module, arguments.count <= 256,
              arguments.allSatisfy({ !$0.contains("\r") && !$0.contains("\n") && !$0.contains("\0") }),
              arguments.reduce(0, { $0 + $1.utf8.count }) <= InternalSaoriService.maximumBytes
        else {
            return InternalSaoriProbeResult(response: "SAORI/1.0 400 Bad Request\r\nErrorDescription: invalid parameter\r\n\r\n", elapsedMilliseconds: 0)
        }
        let request = (["EXECUTE SAORI/1.0", "Charset: UTF-8", "Module: \(module)"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
        let session = InternalSaoriSession()
        defer { session.close() }
        let response = session.response(to: Data(request.utf8))
        return InternalSaoriProbeResult(response: String(decoding: response, as: UTF8.self), elapsedMilliseconds: Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000)
    }
}

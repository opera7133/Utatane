import Foundation
import UtataneCore

/// Ordinary native/Wine SAORI metadata. Never accepts request arguments or bodies.
public final class SaoriDiagnostics: @unchecked Sendable {
    public static let shared = SaoriDiagnostics()
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

    public func record(phase: String, source: URL, module: URL, backend: String, status: Int?, elapsedMicroseconds: UInt64 = 0, responseBytes: UInt64 = 0) {
        guard isEnabled else { return }
        func safe(_ value: String) -> String {
            String(value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\0", with: "").prefix(2048))
        }
        store.info("phase=\(safe(phase)) backend=\(safe(backend)) status=\(status.map(String.init) ?? "unknown") elapsed_us=\(elapsedMicroseconds) response_bytes=\(responseBytes) source=\(safe(source.path)) module=\(safe(module.path))", category: "SAORI")
    }

    /// Private helper frame: phase/status Int32, elapsed/size UInt64, then a UTF-8 path.
    public func receive(_ data: Data, source: URL) {
        guard isEnabled, (25 ... 4120).contains(data.count) else { return }
        let bytes = Array(data)
        func value(_ offset: Int, _ count: Int) -> UInt64 {
            (0 ..< count).reduce(0) { $0 | UInt64(bytes[offset + $1]) << ($1 * 8) }
        }
        let phases = [1: "load", 2: "call", 3: "unload"]
        guard let phase = phases[Int(value(0, 4))], let path = String(bytes: bytes.dropFirst(24), encoding: .utf8), !path.utf8.contains(0) else { return }
        record(phase: phase, source: source, module: URL(filePath: path), backend: "dylib", status: Int(Int32(bitPattern: UInt32(value(4, 4)))), elapsedMicroseconds: value(8, 8), responseBytes: value(16, 8))
    }
}

public struct NativeSaoriCallReport: Sendable {
    public let output: String
    public let status: Int?
    public let responseBytes: Int
    public init(output: String, status: Int?, responseBytes: Int) {
        self.output = output; self.status = status; self.responseBytes = responseBytes
    }
}

public protocol ExternalSaoriStatusReporting: ExternalSaoriModule {
    func callReport(arguments: [String]) -> NativeSaoriCallReport
}

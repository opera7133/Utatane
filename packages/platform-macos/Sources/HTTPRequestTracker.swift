import Foundation

/// Identity belongs to an invocation, never to its URL. A cancelled invocation
/// stays tracked until its task exits so later shutdown can retire it too.
@MainActor
public final class HTTPRequestTracker {
    public final class Lease: @unchecked Sendable {
        public let id = UUID()
        public let url: String
        private let lock = NSLock()
        private var state = 0 // active, explicitly cancelled, retired
        init(url: String) {
            self.url = url
        }

        public var isActive: Bool {
            lock.withLock { state == 0 }
        }

        public var mayReportFailure: Bool {
            lock.withLock { state != 2 }
        }

        public var wasCancelled: Bool {
            lock.withLock { state == 1 }
        }

        func cancel(reportFailure: Bool) {
            lock.withLock {
                if state != 2 {
                    state = reportFailure ? 1 : 2
                }
            }
        }

        func retire() {
            lock.withLock { state = 2 }
        }
    }

    private var entries: [UUID: (Lease, () -> Void)] = [:]
    public init() {}
    public var count: Int {
        entries.count
    }

    public func start<Result: Sendable>(url: String, operation: @escaping @MainActor (Lease) async -> Result) -> Task<Result, Never> {
        let lease = Lease(url: url)
        let task = Task { @MainActor in
            defer { lease.retire(); self.entries.removeValue(forKey: lease.id) }
            return await operation(lease)
        }
        entries[lease.id] = (lease, { task.cancel() })
        return task
    }

    public func cancel(url: String? = nil, reportFailure: Bool = true) {
        for (_, (lease, cancel)) in entries where url == nil || lease.url == url {
            lease.cancel(reportFailure: reportFailure)
            cancel()
        }
    }
}

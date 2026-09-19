import Foundation

/// Runs at most one submitted asynchronous operation at a time.
///
/// Periodic event sources can submit again while a slow SHIORI or plug-in is
/// still responding. Dropping that duplicate tick prevents an unbounded queue
/// of tasks from building up during long-running sessions.
@MainActor
public final class CoalescingTaskRunner {
    private var task: Task<Void, Never>?
    private var token: UUID?

    public init() {}

    public var isRunning: Bool {
        task != nil
    }

    @discardableResult
    public func submit(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard task == nil else { return false }
        let token = UUID()
        self.token = token
        task = Task { [weak self] in
            await operation()
            self?.finish(token: token)
        }
        return true
    }

    public func cancel() {
        task?.cancel()
        task = nil
        token = nil
    }

    private func finish(token: UUID) {
        guard self.token == token else { return }
        task = nil
        self.token = nil
    }
}

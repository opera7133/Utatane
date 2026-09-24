import Foundation

/// A clock for work that must retain its remaining delay while suspended.
/// Suspension cancels timer tasks; it never polls while waiting for resume.
@MainActor
public final class SuspensionClock {
    private let now: () -> ContinuousClock.Instant
    private let origin: ContinuousClock.Instant
    private var pausedAt: ContinuousClock.Instant?
    private var pausedDuration: Duration = .zero
    private var finished = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var timers: [UUID: Task<Void, Error>] = [:]

    public var isSuspended: Bool {
        pausedAt != nil
    }

    var waitingCount: Int {
        waiters.count
    }

    var timerCount: Int {
        timers.count
    }

    var elapsed: Duration {
        origin.duration(to: pausedAt ?? now()) - pausedDuration
    }

    public convenience init() {
        self.init(now: { ContinuousClock.now })
    }

    init(now: @escaping () -> ContinuousClock.Instant) {
        self.now = now
        origin = now()
    }

    public func setSuspended(_ suspended: Bool) {
        guard !finished, suspended != isSuspended else { return }
        if suspended {
            pausedAt = now()
            for timer in timers.values {
                timer.cancel()
            }
        } else if let pausedAt {
            pausedDuration += pausedAt.duration(to: now())
            self.pausedAt = nil
            let pending = waiters.values
            waiters.removeAll()
            for waiter in pending {
                waiter.resume(returning: true)
            }
        }
    }

    public func waitUntilActive() async -> Bool {
        while isSuspended, !finished, !Task.isCancelled {
            let id = UUID()
            let resumed = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(returning: false)
                        return
                    }
                    waiters[id] = continuation
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.waiters.removeValue(forKey: id)?.resume(returning: false)
                }
            }
            guard resumed else { return false }
        }
        return !finished && !Task.isCancelled
    }

    public func sleep(for duration: Duration) async -> Bool {
        let deadline = elapsed + max(.zero, duration)
        while await waitUntilActive() {
            let remaining = deadline - elapsed
            guard remaining > .zero else { return true }
            let id = UUID()
            let timer = Task { try await Task.sleep(for: remaining) }
            timers[id] = timer
            await withTaskCancellationHandler {
                _ = try? await timer.value
            } onCancel: {
                timer.cancel()
            }
            timers[id] = nil
        }
        return false
    }

    /// Permanently releases pending work when its owning session is discarded.
    public func finish() {
        finished = true
        for timer in timers.values {
            timer.cancel()
        }
        timers.removeAll()
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: false)
        }
    }
}

import UtataneCore
import UtataneSakuraScript

/// Suspends both new requests and responses already in flight. Lifecycle events
/// use the underlying session directly, so restore/termination cannot deadlock.
@MainActor
public final class SuspendingGhostEventDelivery {
    private let session: GhostSession
    private let clock = SuspensionClock()

    public var isSuspended: Bool {
        clock.isSuspended
    }

    public init(session: GhostSession) {
        self.session = session
    }

    public func setSuspended(_ suspended: Bool) {
        clock.setSuspended(suspended)
    }

    public func finish() {
        clock.finish()
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        guard await clock.waitUntilActive() else { return nil }
        let result = try await session.handle(event: event)
        guard await clock.waitUntilActive() else { return nil }
        return result
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse? {
        guard await clock.waitUntilActive() else { return nil }
        let result = try await session.response(for: event)
        guard await clock.waitUntilActive() else { return nil }
        return result
    }
}

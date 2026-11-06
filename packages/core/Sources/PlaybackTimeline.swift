/// Accumulates frame deadlines without adding render time or timer overshoot.
/// Overdue frames are retained, but their timing debt is discarded so a long
/// stall or machine sleep cannot cause an unbounded burst of catch-up frames.
public struct PlaybackTimeline: Sendable {
    public private(set) var deadline: Duration

    public init(startedAt: Duration) {
        deadline = startedAt
    }

    public mutating func advance(by duration: Duration, now: Duration) -> Duration {
        deadline = max(deadline + max(.zero, duration), now)
        return deadline
    }
}

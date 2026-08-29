public enum GhostStartupEventKind: Sendable, Equatable {
    case firstBoot
    case boot
    case ghostChanged
}

public func ghostStartupEventKind(
    hasBooted: Bool,
    arrivedByGhostChange: Bool
) -> GhostStartupEventKind {
    if !hasBooted {
        return .firstBoot
    }
    return arrivedByGhostChange ? .ghostChanged : .boot
}

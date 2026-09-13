public enum GhostWindowLevelBehavior: String, CaseIterable, Identifiable, Sendable {
    case always
    case whileTalking
    case normal

    public var id: Self {
        self
    }

    public func staysOnTop(isTalking: Bool) -> Bool {
        switch self {
        case .always: true
        case .whileTalking: isTalking
        case .normal: false
        }
    }
}

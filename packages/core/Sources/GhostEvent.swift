public enum GhostEvent: Sendable, Equatable {
    case boot
    case close
    case ghostChanging(name: String?)
    case mouseClick(scope: Int, region: String?)
    case randomTalk
    case choice(id: String, arguments: [String])
}

public enum GhostStopReason: Sendable, Equatable {
    case close
    case ghostChanging(name: String?)
}

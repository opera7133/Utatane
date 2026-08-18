public enum GhostEvent: Sendable, Equatable {
    case boot
    case close
    case mouseClick(region: String?)
    case randomTalk
    case choice(id: String, arguments: [String])
}

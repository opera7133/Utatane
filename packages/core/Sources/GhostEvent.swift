public enum GhostEvent: Sendable, Equatable {
    case boot
    case close
    case ghostChanging(name: String?)
    case mouseClick(scope: Int, region: String?)
    case mouse(GhostMouseEvent)
    case shiori(id: String, references: [Int: String])
    case randomTalk
    case choice(id: String, arguments: [String])
}

public struct GhostMouseEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case move
        case enter
        case leave
        case enterAll
        case leaveAll
        case down
        case up
        case click
        case doubleClick
        case multipleClick(count: Int)
        case dragStart
        case dragEnd
        case hover
        case wheel(delta: Int)
    }

    public let kind: Kind
    public let scope: Int
    public let region: String?
    public let x: Int
    public let y: Int
    public let button: Int

    public init(
        kind: Kind,
        scope: Int,
        region: String?,
        x: Int,
        y: Int,
        button: Int = 0
    ) {
        self.kind = kind
        self.scope = scope
        self.region = region
        self.x = x
        self.y = y
        self.button = button
    }
}

public enum GhostStopReason: Sendable, Equatable {
    case close
    case ghostChanging(name: String?)
}

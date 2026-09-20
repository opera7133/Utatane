public enum GhostEvent: Sendable, Equatable {
    case boot
    case close
    case ghostChanging(name: String?)
    case mouseClick(scope: Int, region: String?)
    case mouse(GhostMouseEvent)
    case shiori(id: String, references: [Int: String])
    case notification(id: String, references: [Int: String])
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

public struct GhostMouseGestureEvent: Sendable, Equatable {
    public let scope: Int
    public let x: Int
    public let y: Int
    public let region: String?
    public let startX: Int
    public let startY: Int
    public let startRegion: String?
    public let direction: String
    public let angle: Int

    public init(
        scope: Int,
        x: Int,
        y: Int,
        region: String?,
        startX: Int,
        startY: Int,
        startRegion: String?,
        direction: String,
        angle: Int
    ) {
        self.scope = scope
        self.x = x
        self.y = y
        self.region = region
        self.startX = startX
        self.startY = startY
        self.startRegion = startRegion
        self.direction = direction
        self.angle = angle
    }

    public var references: [Int: String] {
        [
            0: String(scope),
            1: "\(x)\u{01}\(y)",
            2: region ?? "",
            3: "\(startX)\u{01}\(startY)",
            4: startRegion ?? "",
            5: direction,
            6: String(angle)
        ]
    }
}

public enum GhostStopReason: Sendable, Equatable {
    case close
    case closeDetailed(reason: String, menuScope: Int, windowScope: Int)
    case closeAll(reason: String, menuScope: Int, windowScope: Int)
    case vanish
    case ghostChanging(name: String?)
    case ghostChangingDetailed(name: String?, mode: String, ghostName: String, path: String)
}

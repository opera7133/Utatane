public enum ShellDesktopAlignment: String, Sendable, Equatable {
    case top
    case bottom
    case free
}

public enum ShellBalloonAlignment: String, Sendable, Equatable {
    case none
    case left
    case right
}

public struct ShellBalloonOffsets: Sendable, Equatable {
    public let x: Int?
    public let y: Int?
    public let leftX: Int?
    public let leftY: Int?
    public let rightX: Int?
    public let rightY: Int?

    public init(
        x: Int? = nil,
        y: Int? = nil,
        leftX: Int? = nil,
        leftY: Int? = nil,
        rightX: Int? = nil,
        rightY: Int? = nil
    ) {
        self.x = x
        self.y = y
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
    }
}

public struct ShellScopePresentationSettings: Sendable, Equatable {
    public let desktopAlignment: ShellDesktopAlignment?
    public let defaultX: Int?
    public let defaultY: Int?
    public let defaultLeft: Int?
    public let defaultTop: Int?
    public let balloonOffsets: ShellBalloonOffsets
    public let balloonAlignment: ShellBalloonAlignment?
    public let preventsBalloonMovement: Bool
    public let synchronizesBalloonScale: Bool

    public init(
        desktopAlignment: ShellDesktopAlignment? = nil,
        defaultX: Int? = nil,
        defaultY: Int? = nil,
        defaultLeft: Int? = nil,
        defaultTop: Int? = nil,
        balloonOffsets: ShellBalloonOffsets = .init(),
        balloonAlignment: ShellBalloonAlignment? = nil,
        preventsBalloonMovement: Bool = false,
        synchronizesBalloonScale: Bool = false
    ) {
        self.desktopAlignment = desktopAlignment
        self.defaultX = defaultX
        self.defaultY = defaultY
        self.defaultLeft = defaultLeft
        self.defaultTop = defaultTop
        self.balloonOffsets = balloonOffsets
        self.balloonAlignment = balloonAlignment
        self.preventsBalloonMovement = preventsBalloonMovement
        self.synchronizesBalloonScale = synchronizesBalloonScale
    }
}

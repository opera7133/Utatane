import Foundation

public struct BalloonDefinition: Sendable, Equatable {
    public let directory: URL
    public let name: String
    public let originX: Int
    public let originY: Int
    public let wordWrapPointX: Int
    public let wordWrapPointY: Int
    public let fontHeight: Int
    public let fontColor: BalloonColor
    public let arrow0X: Int
    public let arrow0Y: Int
    public let arrow1X: Int
    public let arrow1Y: Int

    public init(
        directory: URL,
        name: String,
        originX: Int,
        originY: Int,
        wordWrapPointX: Int,
        wordWrapPointY: Int,
        fontHeight: Int,
        fontColor: BalloonColor,
        arrow0X: Int = 0,
        arrow0Y: Int = 0,
        arrow1X: Int = 0,
        arrow1Y: Int = 0
    ) {
        self.directory = directory
        self.name = name
        self.originX = originX
        self.originY = originY
        self.wordWrapPointX = wordWrapPointX
        self.wordWrapPointY = wordWrapPointY
        self.fontHeight = fontHeight
        self.fontColor = fontColor
        self.arrow0X = arrow0X
        self.arrow0Y = arrow0Y
        self.arrow1X = arrow1X
        self.arrow1Y = arrow1Y
    }
}

public struct BalloonColor: Sendable, Equatable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum BalloonSpeaker: Sendable {
    case sakura
    case kero

    var filenameMarker: String {
        switch self {
        case .sakura: "s"
        case .kero: "k"
        }
    }
}

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
    public let cursorStyle: BalloonLinkAppearance
    public let cursorNotSelectedStyle: BalloonLinkAppearance
    public let anchorStyle: BalloonLinkAppearance
    public let anchorNotSelectedStyle: BalloonLinkAppearance

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
        arrow1Y: Int = 0,
        cursorStyle: BalloonLinkAppearance = .defaultSelected,
        cursorNotSelectedStyle: BalloonLinkAppearance = .defaultNotSelected,
        anchorStyle: BalloonLinkAppearance = .defaultSelected,
        anchorNotSelectedStyle: BalloonLinkAppearance = .defaultNotSelected
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
        self.cursorStyle = cursorStyle
        self.cursorNotSelectedStyle = cursorNotSelectedStyle
        self.anchorStyle = anchorStyle
        self.anchorNotSelectedStyle = anchorNotSelectedStyle
    }
}

public struct BalloonLinkAppearance: Sendable, Equatable {
    public let shape: BalloonLinkShape
    public let fontColor: BalloonColor?
    public let penColor: BalloonColor?
    public let brushColor: BalloonColor?

    public init(
        shape: BalloonLinkShape,
        fontColor: BalloonColor? = nil,
        penColor: BalloonColor? = nil,
        brushColor: BalloonColor? = nil
    ) {
        self.shape = shape
        self.fontColor = fontColor
        self.penColor = penColor
        self.brushColor = brushColor
    }

    public static let defaultSelected = BalloonLinkAppearance(
        shape: .underline,
        fontColor: BalloonColor(red: 0, green: 102, blue: 204)
    )
    public static let defaultNotSelected = BalloonLinkAppearance(
        shape: .none,
        fontColor: BalloonColor(red: 0, green: 102, blue: 204)
    )
}

public enum BalloonLinkShape: String, Sendable, Equatable {
    case none
    case underline
    case square
    case squareUnderline = "square+underline"
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

public enum BalloonSpeaker: Sendable, Equatable {
    case sakura
    case kero
    case character(scope: Int)

    var description: String {
        switch self {
        case .sakura: "sakura"
        case .kero: "kero"
        case let .character(scope): "scope \(scope)"
        }
    }

    func imageNames(style: Int) -> [String] {
        switch self {
        case .sakura:
            ["balloons\(style).png"]
        case .kero:
            ["balloonk\(style).png", "balloons\(style).png"]
        case let .character(scope):
            [
                "balloonp\(scope)def\(style).png",
                "balloonk\(style).png",
                "balloons\(style).png"
            ]
        }
    }
}

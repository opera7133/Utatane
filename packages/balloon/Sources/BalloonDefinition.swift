import Foundation

public struct BalloonDefinition: Sendable, Equatable {
    public let directory: URL
    public let name: String
    public let recommendedGhostName: String?
    public let recommendedGhostPath: String?
    public let originX: Int
    public let originY: Int
    public let wordWrapPointX: Int
    public let wordWrapPointY: Int
    public let validRectLeft: Int
    public let validRectTop: Int
    public let validRectRight: Int?
    public let validRectBottom: Int?
    public let isVertical: Bool
    public let fontHeight: Int
    public let fontColor: BalloonColor
    public let fontName: String?
    public let fontShadowColor: BalloonColor?
    public let fontShadowStyle: String?
    public let fontBold: Bool
    public let fontItalic: Bool
    public let fontUnderline: Bool
    public let fontStrike: Bool
    public let fontOutline: Bool
    public let disabledFontStyle: BalloonFontStyle
    public let arrow0X: Int
    public let arrow0Y: Int
    public let arrow1X: Int
    public let arrow1Y: Int
    public let clickWaitMarkerX: Int
    public let clickWaitMarkerY: Int
    public let onlineMarkerX: Int
    public let onlineMarkerY: Int
    public let onlineMarkerIntervalMilliseconds: Int
    public let sstpMarkerX: Int
    public let sstpMarkerY: Int
    public let sstpMessageFontName: String?
    public let sstpMessageFontHeight: Int
    public let sstpMessageFontColor: BalloonColor
    public let sstpMessageX: Int
    public let sstpMessageY: Int
    public let sstpMessageRightX: Int?
    public let sstpMessageBottomY: Int?
    public let numberFontName: String?
    public let numberFontHeight: Int
    public let numberFontColor: BalloonColor
    public let numberRightX: Int
    public let numberY: Int
    public let usesSelfAlpha: Bool
    public let usesFullSelfAlpha: Bool
    public let windowPositionX: BalloonWindowPositionX
    public let windowPositionY: Int
    public let limitsWindowPosition: Bool
    public let communicateBoxFontName: String?
    public let communicateBoxFontHeight: Int
    public let communicateBoxFontColor: BalloonColor
    public let communicateBoxBackgroundColor: BalloonColor?
    public let communicateBoxX: Int
    public let communicateBoxY: Int
    public let communicateBoxWidth: Int?
    public let communicateBoxHeight: Int?
    public let cursorStyle: BalloonLinkAppearance
    public let cursorNotSelectedStyle: BalloonLinkAppearance
    public let anchorStyle: BalloonLinkAppearance
    public let anchorNotSelectedStyle: BalloonLinkAppearance
    public let anchorVisitedStyle: BalloonLinkAppearance

    public init(
        directory: URL,
        name: String,
        recommendedGhostName: String? = nil,
        recommendedGhostPath: String? = nil,
        originX: Int,
        originY: Int,
        wordWrapPointX: Int,
        wordWrapPointY: Int,
        fontHeight: Int,
        fontColor: BalloonColor,
        validRectLeft: Int = 14,
        validRectTop: Int = 14,
        validRectRight: Int? = nil,
        validRectBottom: Int? = nil,
        isVertical: Bool = false,
        fontName: String? = nil,
        fontShadowColor: BalloonColor? = nil,
        fontShadowStyle: String? = nil,
        fontBold: Bool = false,
        fontItalic: Bool = false,
        fontUnderline: Bool = false,
        fontStrike: Bool = false,
        fontOutline: Bool = false,
        disabledFontStyle: BalloonFontStyle = .init(),
        arrow0X: Int = 0,
        arrow0Y: Int = 0,
        arrow1X: Int = 0,
        arrow1Y: Int = 0,
        clickWaitMarkerX: Int? = nil,
        clickWaitMarkerY: Int? = nil,
        onlineMarkerX: Int = 0,
        onlineMarkerY: Int = 0,
        onlineMarkerIntervalMilliseconds: Int = 500,
        sstpMarkerX: Int = 0,
        sstpMarkerY: Int = 0,
        sstpMessageFontName: String? = nil,
        sstpMessageFontHeight: Int = 10,
        sstpMessageFontColor: BalloonColor = .init(red: 0, green: 0, blue: 0),
        sstpMessageX: Int = 0,
        sstpMessageY: Int = 0,
        sstpMessageRightX: Int? = nil,
        sstpMessageBottomY: Int? = nil,
        numberFontName: String? = nil,
        numberFontHeight: Int = 10,
        numberFontColor: BalloonColor = .init(red: 0, green: 0, blue: 0),
        numberRightX: Int = -28,
        numberY: Int = -24,
        usesSelfAlpha: Bool = false,
        usesFullSelfAlpha: Bool = false,
        windowPositionX: BalloonWindowPositionX = .offset(0),
        windowPositionY: Int = 0,
        limitsWindowPosition: Bool = true,
        communicateBoxFontName: String? = nil,
        communicateBoxFontHeight: Int = 13,
        communicateBoxFontColor: BalloonColor = .init(red: 0, green: 0, blue: 0),
        communicateBoxBackgroundColor: BalloonColor? = nil,
        communicateBoxX: Int = 20,
        communicateBoxY: Int = 20,
        communicateBoxWidth: Int? = nil,
        communicateBoxHeight: Int? = nil,
        cursorStyle: BalloonLinkAppearance = .defaultSelected,
        cursorNotSelectedStyle: BalloonLinkAppearance = .defaultNotSelected,
        anchorStyle: BalloonLinkAppearance = .defaultSelected,
        anchorNotSelectedStyle: BalloonLinkAppearance = .defaultNotSelected,
        anchorVisitedStyle: BalloonLinkAppearance = .defaultNotSelected
    ) {
        self.directory = directory
        self.name = name
        self.recommendedGhostName = recommendedGhostName
        self.recommendedGhostPath = recommendedGhostPath
        self.originX = originX
        self.originY = originY
        self.wordWrapPointX = wordWrapPointX
        self.wordWrapPointY = wordWrapPointY
        self.validRectLeft = validRectLeft
        self.validRectTop = validRectTop
        self.validRectRight = validRectRight
        self.validRectBottom = validRectBottom
        self.isVertical = isVertical
        self.fontHeight = fontHeight
        self.fontColor = fontColor
        self.fontName = fontName
        self.fontShadowColor = fontShadowColor
        self.fontShadowStyle = fontShadowStyle
        self.fontBold = fontBold
        self.fontItalic = fontItalic
        self.fontUnderline = fontUnderline
        self.fontStrike = fontStrike
        self.fontOutline = fontOutline
        self.disabledFontStyle = disabledFontStyle
        self.arrow0X = arrow0X
        self.arrow0Y = arrow0Y
        self.arrow1X = arrow1X
        self.arrow1Y = arrow1Y
        self.clickWaitMarkerX = clickWaitMarkerX ?? arrow1X
        self.clickWaitMarkerY = clickWaitMarkerY ?? arrow1Y
        self.onlineMarkerX = onlineMarkerX
        self.onlineMarkerY = onlineMarkerY
        self.onlineMarkerIntervalMilliseconds = max(50, onlineMarkerIntervalMilliseconds)
        self.sstpMarkerX = sstpMarkerX
        self.sstpMarkerY = sstpMarkerY
        self.sstpMessageFontName = sstpMessageFontName
        self.sstpMessageFontHeight = sstpMessageFontHeight
        self.sstpMessageFontColor = sstpMessageFontColor
        self.sstpMessageX = sstpMessageX
        self.sstpMessageY = sstpMessageY
        self.sstpMessageRightX = sstpMessageRightX
        self.sstpMessageBottomY = sstpMessageBottomY
        self.numberFontName = numberFontName
        self.numberFontHeight = numberFontHeight
        self.numberFontColor = numberFontColor
        self.numberRightX = numberRightX
        self.numberY = numberY
        self.usesSelfAlpha = usesSelfAlpha
        self.usesFullSelfAlpha = usesFullSelfAlpha
        self.windowPositionX = windowPositionX
        self.windowPositionY = windowPositionY
        self.limitsWindowPosition = limitsWindowPosition
        self.communicateBoxFontName = communicateBoxFontName
        self.communicateBoxFontHeight = communicateBoxFontHeight
        self.communicateBoxFontColor = communicateBoxFontColor
        self.communicateBoxBackgroundColor = communicateBoxBackgroundColor
        self.communicateBoxX = communicateBoxX
        self.communicateBoxY = communicateBoxY
        self.communicateBoxWidth = communicateBoxWidth
        self.communicateBoxHeight = communicateBoxHeight
        self.cursorStyle = cursorStyle
        self.cursorNotSelectedStyle = cursorNotSelectedStyle
        self.anchorStyle = anchorStyle
        self.anchorNotSelectedStyle = anchorNotSelectedStyle
        self.anchorVisitedStyle = anchorVisitedStyle
    }

    public func isRecommended(forGhostNamed ghostName: String, directory ghostDirectory: URL) -> Bool {
        let matchesName = recommendedGhostName.map {
            $0.caseInsensitiveCompare(ghostName) == .orderedSame
        } ?? true
        let matchesPath = recommendedGhostPath.map { path in
            var expected = Self.pathComponents(of: path)
            if let first = expected.first, first == "ghost" || first == "ghosts" {
                expected.removeFirst()
            }
            guard !expected.isEmpty else { return false }
            return Self.pathComponents(of: ghostDirectory.path).suffix(expected.count) == expected[...]
        } ?? true
        return matchesName && matchesPath
    }

    public var recommendedGhostDescription: String? {
        switch (recommendedGhostName, recommendedGhostPath) {
        case let (.some(name), .some(path)): "\(name)（\(path)）"
        case let (.some(name), nil): name
        case let (nil, .some(path)): path
        case (nil, nil): nil
        }
    }

    private static func pathComponents(of path: String) -> [String] {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map { $0.lowercased() }
            .filter { $0 != "." }
    }
}

public struct BalloonFontStyle: Sendable, Equatable {
    public let name: String?
    public let height: Int?
    public let color: BalloonColor?
    public let shadowColor: BalloonColor?
    public let shadowStyle: String?
    public let bold: Bool?
    public let italic: Bool?
    public let underline: Bool?
    public let strike: Bool?
    public let outline: Bool?

    public init(
        name: String? = nil,
        height: Int? = nil,
        color: BalloonColor? = nil,
        shadowColor: BalloonColor? = nil,
        shadowStyle: String? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strike: Bool? = nil,
        outline: Bool? = nil
    ) {
        self.name = name
        self.height = height
        self.color = color
        self.shadowColor = shadowColor
        self.shadowStyle = shadowStyle
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strike = strike
        self.outline = outline
    }
}

public enum BalloonInputStyle: Int, Sendable, Equatable {
    case send = 0
    case communicate = 1
    case teach = 2
    case input = 3
    case addressBar = 4
}

public enum BalloonWindowPositionX: Sendable, Equatable {
    case offset(Int)
    case center
    case bottom
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

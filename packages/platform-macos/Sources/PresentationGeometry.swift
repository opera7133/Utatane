import AppKit

public struct PresentationScreenGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let bitsPerPixel: Int
    public let scale: CGFloat
    public let isPrimary: Bool

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        bitsPerPixel: Int,
        scale: CGFloat,
        isPrimary: Bool
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.bitsPerPixel = bitsPerPixel
        self.scale = scale
        self.isPrimary = isPrimary
    }
}

@MainActor
public protocol PresentationGeometryProviding: AnyObject {
    var screens: [PresentationScreenGeometry] { get }
    var pointerPosition: CGPoint { get }
}

public extension PresentationGeometryProviding {
    var mainScreen: PresentationScreenGeometry? {
        screens.first(where: \.isPrimary) ?? screens.first
    }

    var visibleFrames: [CGRect] {
        screens.map(\.visibleFrame)
    }
}

@MainActor
public final class SystemPresentationGeometryProvider: PresentationGeometryProviding {
    public init() {}

    public var screens: [PresentationScreenGeometry] {
        NSScreen.screens.enumerated().map { index, screen in
            let bitsPerSample = (screen.deviceDescription[.bitsPerSample] as? NSNumber)?.intValue ?? 8
            return PresentationScreenGeometry(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                bitsPerPixel: bitsPerSample * 4,
                scale: screen.backingScaleFactor,
                isPrimary: index == 0
            )
        }
    }

    public var pointerPosition: CGPoint {
        NSEvent.mouseLocation
    }
}

@MainActor
public final class MutablePresentationGeometryProvider: PresentationGeometryProviding {
    public private(set) var screens: [PresentationScreenGeometry]
    public private(set) var pointerPosition: CGPoint

    public init(
        screens: [PresentationScreenGeometry],
        pointerPosition: CGPoint = .zero
    ) {
        self.screens = screens
        self.pointerPosition = pointerPosition
    }

    public func update(
        screens: [PresentationScreenGeometry],
        pointerPosition: CGPoint? = nil
    ) {
        self.screens = screens
        if let pointerPosition {
            self.pointerPosition = pointerPosition
        }
    }

    public func updatePointerPosition(_ pointerPosition: CGPoint) {
        self.pointerPosition = pointerPosition
    }
}

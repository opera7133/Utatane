import AppKit

@MainActor
public final class WindowPositionStore {
    private let defaults: UserDefaults
    private let namespace: String
    private var contentID: URL?

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = "dev.utatane.window-position"
    ) {
        self.defaults = defaults
        self.namespace = namespace
    }

    public func setContentID(_ contentID: URL?) {
        self.contentID = contentID?.standardizedFileURL
    }

    func save(
        _ origin: NSPoint,
        for kind: FloatingWindowKind,
        scope: Int,
        coordinateSpace: PresentationCoordinateSpace = .desktop
    ) {
        defaults.set(
            ["x": Double(origin.x), "y": Double(origin.y)],
            forKey: key(for: kind, scope: scope, coordinateSpace: coordinateSpace)
        )
    }

    func remove(
        for kind: FloatingWindowKind,
        scope: Int,
        coordinateSpace: PresentationCoordinateSpace = .desktop
    ) {
        defaults.removeObject(forKey: key(for: kind, scope: scope, coordinateSpace: coordinateSpace))
    }

    func restoredOrigin(
        for kind: FloatingWindowKind,
        scope: Int,
        windowSize: NSSize,
        screens: [NSScreen] = NSScreen.screens,
        constrainsToVisibleFrame: Bool = true,
        coordinateSpace: PresentationCoordinateSpace = .desktop
    ) -> NSPoint? {
        restoredOrigin(
            for: kind,
            scope: scope,
            windowSize: windowSize,
            visibleFrames: screens.map(\.visibleFrame),
            constrainsToVisibleFrame: constrainsToVisibleFrame,
            coordinateSpace: coordinateSpace
        )
    }

    func restoredOrigin(
        for kind: FloatingWindowKind,
        scope: Int,
        windowSize: NSSize,
        visibleFrames: [NSRect],
        constrainsToVisibleFrame: Bool = true,
        coordinateSpace: PresentationCoordinateSpace = .desktop
    ) -> NSPoint? {
        guard let value = defaults.dictionary(
            forKey: key(for: kind, scope: scope, coordinateSpace: coordinateSpace)
        ),
            let x = value["x"] as? Double,
            let y = value["y"] as? Double
        else {
            return nil
        }

        let origin = NSPoint(x: x, y: y)
        guard constrainsToVisibleFrame else { return origin }
        guard let visibleFrame = visibleFrames.first(where: {
            $0.intersects(NSRect(origin: origin, size: windowSize))
        }) ?? visibleFrames.first else {
            return origin
        }
        return constrained(origin, windowSize: windowSize, to: visibleFrame)
    }

    private func constrained(_ origin: NSPoint, windowSize: NSSize, to visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)),
            y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - windowSize.height))
        )
    }

    private func key(
        for kind: FloatingWindowKind,
        scope: Int,
        coordinateSpace: PresentationCoordinateSpace
    ) -> String {
        let contentKey = contentID?.path.data(using: .utf8)?.base64EncodedString() ?? "global"
        let spaceComponent = coordinateSpace == .desktop ? "" : ".\(coordinateSpace.rawValue)"
        return "\(namespace).\(contentKey)\(spaceComponent).\(kind.rawValue).\(scope)"
    }
}

enum FloatingWindowKind: String {
    case surface
    case balloon
}

final class FloatingContentWindow: NSWindow, NSWindowDelegate {
    var onCancel: (() -> Void)?
    private let onMove: (NSPoint, PresentationItemMoveReason) -> Void
    private var placementPolicy: FloatingWindowPlacementPolicy
    private let visibleFrames: @MainActor () -> [NSRect]
    private var isApplyingConstraint = false
    private var moveReason = PresentationItemMoveReason.userInteraction

    init(
        title: String,
        placementPolicy: FloatingWindowPlacementPolicy = .free,
        visibleFrames: @escaping @MainActor () -> [NSRect] = { NSScreen.screens.map(\.visibleFrame) },
        onMove: @escaping (NSPoint, PresentationItemMoveReason) -> Void
    ) {
        self.onMove = onMove
        self.placementPolicy = placementPolicy
        self.visibleFrames = visibleFrames
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.title = title
        setAccessibilityLabel(title)
        delegate = self
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }

    func setPlacementPolicy(_ placementPolicy: FloatingWindowPlacementPolicy) {
        self.placementPolicy = placementPolicy
        performMove(reason: .programmatic) {
            applyPlacementConstraint()
        }
    }

    func performMove(reason: PresentationItemMoveReason, _ changes: () -> Void) {
        let previousReason = moveReason
        moveReason = reason
        changes()
        moveReason = previousReason
    }

    func beginMove(reason: PresentationItemMoveReason) -> PresentationItemMoveReason {
        let previousReason = moveReason
        moveReason = reason
        return previousReason
    }

    func endMove(previousReason: PresentationItemMoveReason) {
        moveReason = previousReason
    }

    func windowDidMove(_ notification: Notification) {
        applyPlacementConstraint()
        onMove(frame.origin, moveReason)
    }

    private func applyPlacementConstraint() {
        guard !isApplyingConstraint,
              let constrainedOrigin = placementPolicy.constrainedOrigin(
                  for: frame,
                  visibleFrames: visibleFrames()
              ),
              constrainedOrigin != frame.origin
        else { return }
        isApplyingConstraint = true
        setFrameOrigin(constrainedOrigin)
        isApplyingConstraint = false
    }
}

struct FloatingWindowPlacementPolicy: Equatable {
    enum Edge: Equatable {
        case top
        case bottom
        case left
        case right
    }

    var edge: Edge?
    var keepsOnScreen: Bool

    static let free = Self(edge: nil, keepsOnScreen: false)
    static let desktopBottom = Self(edge: .bottom, keepsOnScreen: true)

    func constrainedOrigin(for frame: NSRect, visibleFrames: [NSRect]) -> NSPoint? {
        guard edge != nil || keepsOnScreen, !visibleFrames.isEmpty else { return nil }
        let screen = visibleFrames.max { lhs, rhs in
            lhs.intersection(frame).area < rhs.intersection(frame).area
        } ?? visibleFrames[0]
        let constrainedX = min(
            max(frame.origin.x, screen.minX),
            max(screen.minX, screen.maxX - frame.width)
        )
        let constrainedY = min(
            max(frame.origin.y, screen.minY),
            max(screen.minY, screen.maxY - frame.height)
        )
        let x: CGFloat = switch edge {
        case .left: screen.minX
        case .right: screen.maxX - frame.width
        default: keepsOnScreen ? constrainedX : frame.origin.x
        }
        let y: CGFloat = switch edge {
        case .top: screen.maxY - frame.height
        case .bottom: screen.minY
        default: keepsOnScreen ? constrainedY : frame.origin.y
        }
        return NSPoint(x: x, y: y)
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}

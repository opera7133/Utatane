import CoreGraphics

public struct DisplayHandoverEvent: Equatable, Sendable {
    public let scope: Int
    public let references: [Int: String]

    public init(scope: Int, references: [Int: String]) {
        self.scope = scope
        self.references = references
    }
}

struct DisplayHandoverTracker {
    private var screensByScope: [Int: PresentationScreenGeometry] = [:]

    mutating func initialize(
        scope: Int,
        windowFrame: CGRect,
        screens: [PresentationScreenGeometry]
    ) -> DisplayHandoverEvent? {
        guard let screen = screen(for: windowFrame, in: screens) else { return nil }
        screensByScope[scope] = screen
        return DisplayHandoverEvent(scope: scope, references: [
            0: "init",
            1: String(scope),
            2: "",
            3: description(of: screen)
        ])
    }

    mutating func update(
        scope: Int,
        windowFrame: CGRect,
        screens: [PresentationScreenGeometry]
    ) -> DisplayHandoverEvent? {
        guard let current = screen(for: windowFrame, in: screens) else { return nil }
        guard let previous = screensByScope[scope] else {
            screensByScope[scope] = current
            return nil
        }
        guard previous != current else { return nil }
        screensByScope[scope] = current
        return DisplayHandoverEvent(scope: scope, references: [
            0: "update",
            1: String(scope),
            2: description(of: previous),
            3: description(of: current)
        ])
    }

    mutating func reset() {
        screensByScope.removeAll()
    }

    private func screen(
        for windowFrame: CGRect,
        in screens: [PresentationScreenGeometry]
    ) -> PresentationScreenGeometry? {
        screens.max { lhs, rhs in
            let lhsIntersection = lhs.frame.intersection(windowFrame)
            let rhsIntersection = rhs.frame.intersection(windowFrame)
            return lhsIntersection.width * lhsIntersection.height
                < rhsIntersection.width * rhsIntersection.height
        }
    }

    private func description(of screen: PresentationScreenGeometry) -> String {
        let frame = screen.frame
        return [
            Int(frame.minX), Int(frame.minY), Int(frame.maxX), Int(frame.maxY),
            screen.bitsPerPixel, screen.isPrimary ? 1 : 0
        ].map(String.init).joined(separator: ",")
    }
}

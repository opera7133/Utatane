import AppKit

@MainActor
public final class WindowPositionStore {
    private let defaults: UserDefaults
    private let namespace: String

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = "dev.utatane.window-position"
    ) {
        self.defaults = defaults
        self.namespace = namespace
    }

    func save(_ origin: NSPoint, for kind: FloatingWindowKind, scope: Int) {
        defaults.set(
            ["x": Double(origin.x), "y": Double(origin.y)],
            forKey: key(for: kind, scope: scope)
        )
    }

    func restoredOrigin(
        for kind: FloatingWindowKind,
        scope: Int,
        windowSize: NSSize,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSPoint? {
        guard let value = defaults.dictionary(forKey: key(for: kind, scope: scope)),
              let x = value["x"] as? Double,
              let y = value["y"] as? Double
        else {
            return nil
        }

        let origin = NSPoint(x: x, y: y)
        guard let screen = screens.first(where: {
            $0.visibleFrame.intersects(NSRect(origin: origin, size: windowSize))
        }) ?? screens.first else {
            return origin
        }
        return constrained(origin, windowSize: windowSize, to: screen.visibleFrame)
    }

    private func constrained(_ origin: NSPoint, windowSize: NSSize, to visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)),
            y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - windowSize.height))
        )
    }

    private func key(for kind: FloatingWindowKind, scope: Int) -> String {
        "\(namespace).\(kind.rawValue).\(scope)"
    }
}

enum FloatingWindowKind: String {
    case surface
    case balloon
}

final class FloatingContentWindow: NSWindow, NSWindowDelegate {
    private let onMove: (NSPoint) -> Void

    init(title: String, onMove: @escaping (NSPoint) -> Void) {
        self.onMove = onMove
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

    func windowDidMove(_ notification: Notification) {
        onMove(frame.origin)
    }
}

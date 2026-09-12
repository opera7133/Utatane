import AppKit

/// The presentation operations shared by independent desktop windows and
/// items embedded in a future window-mode stage.
@MainActor
protocol PresentationItem: AnyObject {
    var frame: NSRect { get }
    var isVisible: Bool { get }
    var contentView: NSView? { get set }
    var contentSize: NSSize { get }
    var alphaValue: CGFloat { get set }
    var captureWindowNumber: Int? { get }

    func setContentSize(_ size: NSSize)
    func setFrameOrigin(_ origin: NSPoint)
    func center()
    func show(activating: Bool)
    func hide()
    func setStaysOnTop(_ staysOnTop: Bool)
    func setPlacementPolicy(_ policy: FloatingWindowPlacementPolicy)
    func orderAbove(_ other: any PresentationItem)
    func animateFrameOrigin(_ origin: NSPoint, duration: TimeInterval) async
    func animateContentSize(_ size: NSSize, duration: TimeInterval) async
    func animateAlphaValue(_ alpha: CGFloat, duration: TimeInterval) async
}

@MainActor
final class DesktopPresentationItem: PresentationItem {
    let window: FloatingContentWindow

    init(window: FloatingContentWindow) {
        self.window = window
    }

    var frame: NSRect {
        window.frame
    }

    var isVisible: Bool {
        window.isVisible
    }

    var contentView: NSView? {
        get { window.contentView }
        set { window.contentView = newValue }
    }

    var alphaValue: CGFloat {
        get { window.alphaValue }
        set { window.alphaValue = newValue }
    }

    var contentSize: NSSize {
        window.contentRect(forFrameRect: window.frame).size
    }

    var captureWindowNumber: Int? {
        window.windowNumber
    }

    func setContentSize(_ size: NSSize) {
        window.setContentSize(size)
    }

    func setFrameOrigin(_ origin: NSPoint) {
        window.setFrameOrigin(origin)
    }

    func center() {
        window.center()
    }

    func show(activating: Bool) {
        if activating {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func setStaysOnTop(_ staysOnTop: Bool) {
        window.level = staysOnTop ? .floating : .normal
    }

    func setPlacementPolicy(_ policy: FloatingWindowPlacementPolicy) {
        window.setPlacementPolicy(policy)
    }

    func orderAbove(_ other: any PresentationItem) {
        guard let other = other as? DesktopPresentationItem else { return }
        window.order(.above, relativeTo: other.window.windowNumber)
    }

    func animateFrameOrigin(_ origin: NSPoint, duration: TimeInterval) async {
        await animate(duration: duration) {
            self.window.animator().setFrameOrigin(origin)
        }
    }

    func animateContentSize(_ size: NSSize, duration: TimeInterval) async {
        await animate(duration: duration) {
            self.window.animator().setContentSize(size)
        }
    }

    func animateAlphaValue(_ alpha: CGFloat, duration: TimeInterval) async {
        await animate(duration: duration, timingFunction: CAMediaTimingFunction(name: .linear)) {
            self.window.animator().alphaValue = alpha
        }
    }

    private func animate(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        changes: @escaping @MainActor () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = timingFunction
                changes()
            } completionHandler: {
                continuation.resume()
            }
        }
    }
}

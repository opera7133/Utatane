import AppKit

@MainActor
final class ScreenSelectionController {
    private var windows: [NSWindow] = []
    private var views: [ScreenSelectionView] = []
    private var startPoint: CGPoint?
    private(set) var selection: CGRect?
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    func begin() {
        closeWindows()
        selection = nil
        startPoint = nil
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            let view = ScreenSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.onMouseDown = { [weak self] point in self?.mouseDown(at: point) }
            view.onMouseDragged = { [weak self] point in self?.mouseDragged(to: point) }
            view.onMouseUp = { [weak self] point in self?.mouseUp(at: point) }
            view.onCancel = { [weak self] in self?.cancel() }
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            views.append(view)
        }
        windows.first?.makeKey()
        NSCursor.crosshair.push()
    }

    func finish() -> CGRect? {
        let result = selection.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        closeWindows()
        return result
    }

    func cancel() {
        selection = nil
        closeWindows()
        onCancel?()
    }

    private func mouseDown(at point: CGPoint) {
        startPoint = point
        selection = CGRect(origin: point, size: .zero)
        updateViews()
        onMouseDown?(point)
    }

    private func mouseDragged(to point: CGPoint) {
        guard let startPoint else { return }
        selection = CGRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        updateViews()
    }

    private func mouseUp(at point: CGPoint) {
        mouseDragged(to: point)
        onMouseUp?(point)
    }

    private func updateViews() {
        for view in views {
            view.selection = selection
            view.needsDisplay = true
        }
    }

    private func closeWindows() {
        if !windows.isEmpty {
            NSCursor.pop()
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
    }
}

private final class ScreenSelectionView: NSView {
    var screenFrame = CGRect.zero
    var selection: CGRect?
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()
        dirtyRect.fill()
        guard let selection else { return }
        let local = selection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        local.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: local)
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with _: NSEvent) {
        onMouseDown?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with _: NSEvent) {
        onMouseDragged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with _: NSEvent) {
        onMouseUp?(NSEvent.mouseLocation)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

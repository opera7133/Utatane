import AppKit

struct SurfaceDragPosition: Equatable {
    let origin: NSPoint
    let delta: NSPoint

    init(frame: NSRect, startOrigin: NSPoint, desktopTop: CGFloat) {
        // Desktop points, with the primary display's top-left as (0, 0).
        // Keep negative coordinates on displays to the left or above it.
        origin = NSPoint(x: frame.minX, y: desktopTop - frame.maxY)
        delta = NSPoint(x: frame.minX - startOrigin.x, y: startOrigin.y - frame.minY)
    }

    var text: String {
        let x = Int(origin.x.rounded())
        let y = Int(origin.y.rounded())
        let dx = Int(delta.x.rounded())
        let dy = Int(delta.y.rounded())
        return "X: \(x)  Y: \(y)\nΔX: \(dx >= 0 ? "+" : "")\(dx)  ΔY: \(dy >= 0 ? "+" : "")\(dy)"
    }
}

@MainActor
final class SurfaceDragFeedback {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private(set) var position: SurfaceDragPosition?

    func show(_ position: SurfaceDragPosition, near pointer: NSPoint) {
        self.position = position
        let panel = panel ?? makePanel()
        label.stringValue = position.text
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: 10, y: 8))
        panel.setContentSize(NSSize(width: label.frame.width + 20, height: label.frame.height + 16))
        var origin = NSPoint(x: pointer.x + 18, y: pointer.y - panel.frame.height - 18)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            let bounds = screen.visibleFrame
            origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - panel.frame.width))
            origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - panel.frame.height))
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        position = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background
        self.panel = panel
        return panel
    }
}

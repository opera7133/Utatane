import AppKit

@MainActor
public final class StatusWindowController {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var currentToken: UUID?

    public init() {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -11)
        ])

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Utatane Status"
        panel.setAccessibilityLabel("Utatane Status")
        panel.contentView = effectView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    @discardableResult
    public func show(_ message: String) -> UUID {
        let token = UUID()
        currentToken = token
        label.stringValue = message
        let fittingWidth = min(max(label.intrinsicContentSize.width + 32, 180), 420)
        panel.setContentSize(NSSize(width: fittingWidth, height: 42))
        positionAtBottomRight()
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        return token
    }

    public func hide(token: UUID? = nil) {
        guard token == nil || token == currentToken else { return }
        currentToken = nil
        panel.orderOut(nil)
    }

    private func positionAtBottomRight() {
        guard let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else {
            panel.center()
            return
        }
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - panel.frame.width - 20,
            y: visibleFrame.minY + 20
        ))
    }
}

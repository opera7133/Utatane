import AppKit

/// Visual half of FIRST's game; the standard InputBox owns input and timeout.
@MainActor
public final class FIRSTEyesightWindowController {
    private var panel: NSPanel?

    public init() {}

    public func show(stage: Int, title: String) {
        close()
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 256, height: 256),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = FIRSTEyesightView(stage: stage)
        panel.center()
        // The independent input box also opens near the screen center. Keep
        // the stimulus alongside it rather than underneath the input window.
        if let screen = panel.screen ?? NSScreen.main {
            var origin = panel.frame.origin
            origin.x = min(screen.visibleFrame.maxX - panel.frame.width - 12, origin.x + 260)
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    public func close() {
        panel?.close()
        panel = nil
    }
}

@MainActor
final class FIRSTEyesightView: NSView {
    let stage: Int

    init(stage: Int) {
        self.stage = stage
        super.init(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        // TEYESIGHTFORM's FormPaint at 0x00470430 draws only stage 0:
        // black "C", font height 192, at (60, 32), on a white 256x256 client.
        // The exact Windows MS PGothic font is replaced with the macOS font.
        guard stage == 0 else { return }
        ("C" as NSString).draw(at: CGPoint(x: 60, y: 32), withAttributes: [
            .font: NSFont.systemFont(ofSize: 192),
            .foregroundColor: NSColor.black
        ])
    }
}

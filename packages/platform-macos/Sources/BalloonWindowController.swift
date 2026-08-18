import AppKit
import UtataneBalloon

public struct BalloonTextLink: Sendable, Equatable {
    public let range: NSRange
    public let id: String
    public let arguments: [String]

    public init(range: NSRange, id: String, arguments: [String]) {
        self.range = range
        self.id = id
        self.arguments = arguments
    }
}

@MainActor
public final class BalloonWindowController {
    private let balloonLoader = BalloonLoader()
    private let imageLoader = SurfaceImageLoader()
    private let positionStore: WindowPositionStore
    private var presentations: [Int: BalloonPresentation] = [:]

    public var onClick: (@MainActor (Int) -> Void)?
    public var onLinkClick: (@MainActor (String, [String]) -> Void)?

    public init(positionStore: WindowPositionStore = WindowPositionStore()) {
        self.positionStore = positionStore
    }

    public var visibleScopes: [Int] {
        presentations.compactMap { scope, presentation in
            presentation.window.isVisible ? scope : nil
        }.sorted()
    }

    public func windowFrame(for scope: Int) -> NSRect? {
        presentations[scope]?.window.frame
    }

    public func show(
        balloon: BalloonDefinition,
        text: String,
        scope: Int = 0,
        speaker: BalloonSpeaker = .sakura,
        near surfaceFrame: NSRect
    ) throws {
        let imageURL = try balloonLoader.imageURL(speaker: speaker, in: balloon)
        let image = try imageLoader.loadUsingTopLeftTransparency(imageURL)
        let arrowImage = balloonLoader.arrowImageURL(index: 1, in: balloon)
            .flatMap { try? imageLoader.loadUsingTopLeftTransparency($0) }
        let contentView = BalloonContentView(
            frame: NSRect(origin: .zero, size: image.size),
            image: image,
            arrowImage: arrowImage,
            balloon: balloon,
            text: text
        )
        contentView.onClick = { [weak self] in
            self?.onClick?(scope)
        }
        contentView.onLinkClick = { [weak self] id, arguments in
            self?.onLinkClick?(id, arguments)
        }

        let existingPresentation = presentations[scope]
        let window = existingPresentation?.window ?? makeWindow(scope: scope)
        let existingOrigin = existingPresentation?.window.frame.origin
        window.contentView = contentView
        window.setContentSize(image.size)
        if let existingOrigin {
            window.setFrameOrigin(existingOrigin)
        } else if let restoredOrigin = positionStore.restoredOrigin(
            for: .balloon,
            scope: scope,
            windowSize: image.size
        ) {
            window.setFrameOrigin(restoredOrigin)
        } else {
            place(window, near: surfaceFrame)
        }
        window.makeKeyAndOrderFront(nil)
        presentations[scope] = BalloonPresentation(window: window, contentView: contentView)
    }

    public func updateText(_ text: String, scope: Int = 0) {
        presentations[scope]?.contentView.text = text
    }

    public func updateContent(text: String, links: [BalloonTextLink], scope: Int = 0) {
        presentations[scope]?.contentView.update(text: text, links: links)
    }

    public func setWaitingForClick(_ waiting: Bool, scope: Int? = nil) {
        if let scope {
            presentations[scope]?.contentView.isWaitingForClick = waiting
        } else {
            for presentation in presentations.values {
                presentation.contentView.isWaitingForClick = waiting
            }
        }
    }

    public func hide(scope: Int = 0) {
        presentations[scope]?.window.orderOut(nil)
    }

    public func hideAll() {
        for presentation in presentations.values {
            presentation.window.orderOut(nil)
        }
    }

    private func makeWindow(scope: Int) -> NSWindow {
        let window = FloatingContentWindow(title: "Ghost Balloon \(scope)") { [positionStore, scope] origin in
            positionStore.save(origin, for: .balloon, scope: scope)
        }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func place(_ window: NSWindow, near surfaceFrame: NSRect) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            window.center()
            return
        }

        let spacing: CGFloat = 8
        let preferredX = surfaceFrame.minX - window.frame.width - spacing
        let x = max(visibleFrame.minX, preferredX)
        let preferredY = surfaceFrame.maxY - window.frame.height
        let y = min(
            max(visibleFrame.minY, preferredY),
            visibleFrame.maxY - window.frame.height
        )
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class BalloonPresentation {
    let window: NSWindow
    let contentView: BalloonContentView

    init(window: NSWindow, contentView: BalloonContentView) {
        self.window = window
        self.contentView = contentView
    }
}

private final class BalloonContentView: NSView {
    var text: String {
        get { textView.string }
        set { update(text: newValue, links: []) }
    }

    private let textView: InteractiveTextView
    private let arrowView: NSImageView?
    private let textFont: NSFont
    private let textColor: NSColor
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    var onClick: (() -> Void)?
    var onLinkClick: ((String, [String]) -> Void)?

    var isWaitingForClick: Bool {
        get { arrowView?.isHidden == false }
        set { arrowView?.isHidden = !newValue }
    }

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    init(
        frame: NSRect,
        image: NSImage,
        arrowImage: NSImage?,
        balloon: BalloonDefinition,
        text: String
    ) {
        textView = InteractiveTextView(frame: .zero)
        arrowView = arrowImage.map(NSImageView.init(image:))
        textFont = .systemFont(ofSize: CGFloat(balloon.fontHeight))
        textColor = NSColor(
            calibratedRed: CGFloat(min(max(balloon.fontColor.red, 0), 255)) / 255,
            green: CGFloat(min(max(balloon.fontColor.green, 0), 255)) / 255,
            blue: CGFloat(min(max(balloon.fontColor.blue, 0), 255)) / 255,
            alpha: 1
        )
        super.init(frame: frame)

        let imageView = PassthroughImageView(frame: bounds)
        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        addSubview(imageView)

        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = textView
        textView.frame = textFrame(for: balloon, imageSize: image.size)
        textView.onBackgroundClick = { [weak self] in
            self?.onClick?()
        }
        textView.onLinkClick = { [weak self] id, arguments in
            self?.onLinkClick?(id, arguments)
        }
        addSubview(textView)
        update(text: text, links: [])

        if let arrowView {
            arrowView.imageScaling = .scaleNone
            let arrowSize = arrowImage?.size ?? .zero
            arrowView.frame = NSRect(
                x: resolvedCoordinate(
                    balloon.arrow1X,
                    extent: image.size.width,
                    itemExtent: arrowSize.width
                ),
                y: resolvedCoordinate(
                    balloon.arrow1Y,
                    extent: image.size.height,
                    itemExtent: arrowSize.height
                ),
                width: arrowSize.width,
                height: arrowSize.height
            )
            arrowView.isHidden = true
            addSubview(arrowView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartMouseLocation, let dragStartWindowOrigin else { return }
        let location = NSEvent.mouseLocation
        let delta = NSPoint(
            x: location.x - dragStartMouseLocation.x,
            y: location.y - dragStartMouseLocation.y
        )
        didDrag = didDrag || abs(delta.x) > 2 || abs(delta.y) > 2
        window.setFrameOrigin(
            NSPoint(x: dragStartWindowOrigin.x + delta.x, y: dragStartWindowOrigin.y + delta.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            didDrag = false
        }
        guard !didDrag else { return }
        onClick?()
    }

    private func textFrame(for balloon: BalloonDefinition, imageSize: NSSize) -> NSRect {
        let originX = CGFloat(balloon.originX)
        let originY = CGFloat(balloon.originY)
        let wrapX = CGFloat(balloon.wordWrapPointX)
        let rightEdge = wrapX < 0 ? imageSize.width + wrapX : wrapX
        let width = max(1, rightEdge - originX)
        let bottomMargin = max(originY, CGFloat(abs(balloon.wordWrapPointY)))
        return NSRect(
            x: originX,
            y: originY,
            width: width,
            height: max(1, imageSize.height - originY - bottomMargin)
        )
    }

    func update(text: String, links: [BalloonTextLink]) {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: textFont,
                .foregroundColor: textColor
            ]
        )
        var argumentsByID: [String: [String]] = [:]
        for link in links where NSMaxRange(link.range) <= attributedText.length {
            attributedText.addAttributes(
                [
                    .link: link.id,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: link.range
            )
            argumentsByID[link.id] = link.arguments
        }
        textView.argumentsByID = argumentsByID
        textView.textStorage?.setAttributedString(attributedText)
    }

    private func resolvedCoordinate(_ value: Int, extent: CGFloat, itemExtent _: CGFloat) -> CGFloat {
        let coordinate = CGFloat(value)
        return coordinate < 0 ? extent + coordinate : coordinate
    }
}

private final class InteractiveTextView: NSTextView, NSTextViewDelegate {
    var argumentsByID: [String: [String]] = [:]
    var onBackgroundClick: (() -> Void)?
    var onLinkClick: ((String, [String]) -> Void)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartMouseLocation, let dragStartWindowOrigin else { return }
        let location = NSEvent.mouseLocation
        let delta = NSPoint(
            x: location.x - dragStartMouseLocation.x,
            y: location.y - dragStartMouseLocation.y
        )
        didDrag = didDrag || abs(delta.x) > 2 || abs(delta.y) > 2
        window.setFrameOrigin(
            NSPoint(x: dragStartWindowOrigin.x + delta.x, y: dragStartWindowOrigin.y + delta.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            didDrag = false
        }
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let id = balloonTextLinkID(at: point, in: self) {
            onLinkClick?(id, argumentsByID[id] ?? [])
            return
        }
        onBackgroundClick?()
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let id = link as? String else { return false }
        onLinkClick?(id, argumentsByID[id] ?? [])
        return true
    }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
func balloonTextLinkID(at point: NSPoint, in textView: NSTextView) -> String? {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer,
          !textView.string.isEmpty
    else {
        return nil
    }

    layoutManager.ensureLayout(for: textContainer)
    let origin = textView.textContainerOrigin
    let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
    guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

    let glyphRange = NSRange(location: glyphIndex, length: 1)
    let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
    guard glyphBounds.contains(containerPoint), characterIndex < (textView.textStorage?.length ?? 0) else {
        return nil
    }
    return textView.textStorage?.attribute(.link, at: characterIndex, effectiveRange: nil) as? String
}

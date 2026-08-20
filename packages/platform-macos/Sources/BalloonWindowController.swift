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
    private var displayScale: CGFloat = 1
    private var textScale: CGFloat = 1

    public var onClick: (@MainActor (Int) -> Void)?
    public var onLinkClick: (@MainActor (String, [String]) -> Void)?

    public init(positionStore: WindowPositionStore = WindowPositionStore()) {
        self.positionStore = positionStore
    }

    public func setPositionContentID(_ contentID: URL?) {
        hideAll()
        presentations.removeAll()
        positionStore.setContentID(contentID)
    }

    public func setDisplayScale(_ scale: Double, textScale: Double) {
        displayScale = CGFloat(min(max(scale, 0.5), 2))
        self.textScale = CGFloat(min(max(textScale, 0.5), 2))
        rebuildPresentations()
    }

    public var visibleScopes: [Int] {
        presentations.compactMap { scope, presentation in
            presentation.window.isVisible ? scope : nil
        }.sorted()
    }

    public func windowFrame(for scope: Int) -> NSRect? {
        presentations[scope]?.window.frame
    }

    func isTextScrollable(scope: Int) -> Bool {
        presentations[scope]?.contentView.isTextScrollable ?? false
    }

    func isTextAtBottom(scope: Int) -> Bool {
        presentations[scope]?.contentView.isTextAtBottom ?? false
    }

    public func show(
        balloon: BalloonDefinition,
        text: String,
        scope: Int = 0,
        speaker: BalloonSpeaker = .sakura,
        style: Int = 0,
        near surfaceFrame: NSRect
    ) throws {
        let imageURL = try balloonLoader.imageURL(speaker: speaker, style: style, in: balloon)
        let image = try imageLoader.loadUsingTopLeftTransparency(imageURL)
        let arrowImage = balloonLoader.arrowImageURL(index: 1, in: balloon)
            .flatMap { try? imageLoader.loadUsingTopLeftTransparency($0) }
        let scaledSize = NSSize(
            width: image.size.width * displayScale,
            height: image.size.height * displayScale
        )
        let contentView = BalloonContentView(
            frame: NSRect(origin: .zero, size: scaledSize),
            image: image,
            arrowImage: arrowImage,
            balloon: balloon,
            text: text,
            displayScale: displayScale,
            textScale: textScale
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
        window.setContentSize(scaledSize)
        if let existingOrigin {
            window.setFrameOrigin(existingOrigin)
        } else if let restoredOrigin = positionStore.restoredOrigin(
            for: .balloon,
            scope: scope,
            windowSize: scaledSize
        ) {
            window.setFrameOrigin(restoredOrigin)
        } else {
            place(window, near: surfaceFrame)
        }
        window.makeKeyAndOrderFront(nil)
        presentations[scope] = BalloonPresentation(
            window: window,
            contentView: contentView,
            balloon: balloon,
            speaker: speaker,
            style: style,
            surfaceFrame: surfaceFrame
        )
    }

    public func updateText(_ text: String, scope: Int = 0) {
        presentations[scope]?.contentView.text = text
        presentations[scope]?.text = text
        presentations[scope]?.links = []
    }

    public func updateContent(text: String, links: [BalloonTextLink], scope: Int = 0) {
        presentations[scope]?.contentView.update(text: text, links: links)
        presentations[scope]?.text = text
        presentations[scope]?.links = links
    }

    public func setWaitingForClick(_ waiting: Bool, scope: Int? = nil) {
        if let scope {
            presentations[scope]?.contentView.isWaitingForClick = waiting
            presentations[scope]?.isWaitingForClick = waiting
        } else {
            for presentation in presentations.values {
                presentation.contentView.isWaitingForClick = waiting
                presentation.isWaitingForClick = waiting
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

    private func rebuildPresentations() {
        let snapshots = presentations.map { scope, presentation in
            (
                scope,
                presentation.balloon,
                presentation.speaker,
                presentation.style,
                presentation.surfaceFrame,
                presentation.text,
                presentation.links,
                presentation.isWaitingForClick,
                presentation.window.isVisible
            )
        }
        for snapshot in snapshots {
            try? show(
                balloon: snapshot.1,
                text: snapshot.5,
                scope: snapshot.0,
                speaker: snapshot.2,
                style: snapshot.3,
                near: snapshot.4
            )
            updateContent(text: snapshot.5, links: snapshot.6, scope: snapshot.0)
            setWaitingForClick(snapshot.7, scope: snapshot.0)
            if !snapshot.8 {
                hide(scope: snapshot.0)
            }
        }
    }
}

@MainActor
private final class BalloonPresentation {
    let window: NSWindow
    let contentView: BalloonContentView
    let balloon: BalloonDefinition
    let speaker: BalloonSpeaker
    let style: Int
    let surfaceFrame: NSRect
    var text: String
    var links: [BalloonTextLink] = []
    var isWaitingForClick = false

    init(
        window: NSWindow,
        contentView: BalloonContentView,
        balloon: BalloonDefinition,
        speaker: BalloonSpeaker,
        style: Int,
        surfaceFrame: NSRect
    ) {
        self.window = window
        self.contentView = contentView
        self.balloon = balloon
        self.speaker = speaker
        self.style = style
        self.surfaceFrame = surfaceFrame
        text = contentView.text
    }
}

private final class BalloonContentView: NSView {
    var text: String {
        get { textView.string }
        set { update(text: newValue, links: []) }
    }

    private let textView: InteractiveTextView
    private let scrollView: NSScrollView
    private let arrowView: NSImageView?
    private let textFont: NSFont
    private let textColor: NSColor
    private let displayScale: CGFloat
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    var onClick: (() -> Void)?
    var onLinkClick: ((String, [String]) -> Void)?

    var isWaitingForClick: Bool {
        get { arrowView?.isHidden == false }
        set { arrowView?.isHidden = !newValue }
    }

    var isTextScrollable: Bool {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return false }
        return layoutManager.usedRect(for: textContainer).height > scrollView.contentSize.height
    }

    var isTextAtBottom: Bool {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return true }
        let textBottom = layoutManager.usedRect(for: textContainer).maxY
        return scrollView.documentVisibleRect.maxY >= textBottom - 1
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
        text: String,
        displayScale: CGFloat,
        textScale: CGFloat
    ) {
        textView = InteractiveTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        arrowView = arrowImage.map(NSImageView.init(image:))
        textFont = .systemFont(ofSize: CGFloat(balloon.fontHeight) * displayScale * textScale)
        self.displayScale = displayScale
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
        imageView.imageScaling = .scaleAxesIndependently
        addSubview(imageView)

        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: textFrame(for: balloon).height)
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: textFrame(for: balloon).width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = textView
        let textFrame = textFrame(for: balloon)
        textView.frame = NSRect(origin: .zero, size: textFrame.size)
        textView.onBackgroundClick = { [weak self] in
            self?.onClick?()
        }
        textView.onLinkClick = { [weak self] id, arguments in
            self?.onLinkClick?(id, arguments)
        }
        scrollView.frame = textFrame
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        addSubview(scrollView)
        update(text: text, links: [])

        if let arrowView {
            arrowView.imageScaling = .scaleAxesIndependently
            let sourceArrowSize = arrowImage?.size ?? .zero
            let arrowSize = NSSize(
                width: sourceArrowSize.width * displayScale,
                height: sourceArrowSize.height * displayScale
            )
            arrowView.frame = NSRect(
                x: scaledCoordinate(
                    balloon.arrow1X,
                    extent: bounds.width
                ),
                y: scaledCoordinate(
                    balloon.arrow1Y,
                    extent: bounds.height
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

    private func textFrame(for balloon: BalloonDefinition) -> NSRect {
        balloonTextFrame(for: balloon, displayedImageSize: bounds.size, displayScale: displayScale)
    }
}

func balloonTextFrame(
    for balloon: BalloonDefinition,
    displayedImageSize: NSSize,
    displayScale: CGFloat
) -> NSRect {
    let originX = CGFloat(balloon.originX) * displayScale
    let originY = CGFloat(balloon.originY) * displayScale
    let wrapX = CGFloat(balloon.wordWrapPointX) * displayScale
    let rightEdge = wrapX < 0 ? displayedImageSize.width + wrapX : wrapX
    let width = max(1, rightEdge - originX)
    let bottomMargin = max(originY, CGFloat(abs(balloon.wordWrapPointY)) * displayScale)
    return NSRect(
        x: originX,
        y: originY,
        width: width,
        height: max(1, displayedImageSize.height - originY - bottomMargin)
    )
}

private extension BalloonContentView {
    func update(text: String, links: [BalloonTextLink]) {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: textFont,
                .foregroundColor: textColor
            ]
        )
        var linkTargets: [String: BalloonTextLink] = [:]
        for (index, link) in links.enumerated() where NSMaxRange(link.range) <= attributedText.length {
            let token = "utatane-link-\(index)"
            attributedText.addAttributes(
                [
                    .link: token,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: link.range
            )
            linkTargets[token] = link
        }
        textView.linkTargets = linkTargets
        textView.textStorage?.setAttributedString(attributedText)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        if attributedText.length > 0 {
            textView.scrollRangeToVisible(NSRange(location: attributedText.length, length: 0))
        }
    }

    private func scaledCoordinate(_ value: Int, extent: CGFloat) -> CGFloat {
        let coordinate = CGFloat(value) * displayScale
        return coordinate < 0 ? extent + coordinate : coordinate
    }
}

private final class InteractiveTextView: NSTextView, NSTextViewDelegate {
    var linkTargets: [String: BalloonTextLink] = [:]
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
        if let token = balloonTextLinkID(at: point, in: self) {
            activateLink(token)
            return
        }
        onBackgroundClick?()
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let token = link as? String else { return false }
        activateLink(token)
        return true
    }

    private func activateLink(_ token: String) {
        if let target = linkTargets[token] {
            onLinkClick?(target.id, target.arguments)
        } else {
            onLinkClick?(token, [])
        }
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

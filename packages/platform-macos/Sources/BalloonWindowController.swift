import AppKit
import UtataneBalloon

public struct BalloonTextLink: Sendable, Equatable {
    public enum Kind: Sendable, Hashable {
        case choice
        case anchor
    }

    public let range: NSRange
    public let id: String
    public let arguments: [String]
    public let kind: Kind
    public let fontColor: BalloonColor?

    public init(
        range: NSRange,
        id: String,
        arguments: [String],
        kind: Kind = .choice,
        fontColor: BalloonColor? = nil
    ) {
        self.range = range
        self.id = id
        self.arguments = arguments
        self.kind = kind
        self.fontColor = fontColor
    }
}

public struct BalloonTextStyle: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable {
        case left
        case center
        case right
    }

    public var fontName: String?
    public var fontHeight: Double?
    public var color: BalloonColor?
    public var shadowColor: BalloonColor?
    public var shadowStyle: String?
    public var outline = false
    public var alignment: Alignment?
    public var anchorFontColor: BalloonColor?
    public var lineHeight: Double?
    public var bold = false
    public var italic = false
    public var strike = false
    public var underline = false
    public var baseline = 0

    public init() {}
}

public struct BalloonTextStyleRun: Sendable, Equatable {
    public let range: NSRange
    public let style: BalloonTextStyle

    public init(range: NSRange, style: BalloonTextStyle) {
        self.range = range
        self.style = style
    }
}

public enum BalloonVerticalAlignment: Sendable, Equatable {
    case top
    case center
    case bottom
}

@MainActor
public final class BalloonWindowController {
    private let balloonLoader = BalloonLoader()
    private let imageLoader = SurfaceImageLoader()
    private let positionStore: WindowPositionStore
    private var presentations: [Int: BalloonPresentation] = [:]
    private var repaintLockedScopes: Set<Int> = []
    private var movementLockedScopes: Set<Int> = []
    private var markerTextByScope: [Int: String] = [:]
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
        repaintLockedScopes.removeAll()
        movementLockedScopes.removeAll()
        markerTextByScope.removeAll()
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

    func style(for scope: Int) -> Int? {
        presentations[scope]?.style
    }

    func isTextScrollable(scope: Int) -> Bool {
        presentations[scope]?.contentView.isTextScrollable ?? false
    }

    func isTextAtBottom(scope: Int) -> Bool {
        presentations[scope]?.contentView.isTextAtBottom ?? false
    }

    func textAttributes(at location: Int, scope: Int) -> [NSAttributedString.Key: Any]? {
        presentations[scope]?.contentView.textAttributes(at: location)
    }

    func verticalContentInset(scope: Int) -> CGFloat? {
        presentations[scope]?.contentView.verticalContentInset
    }

    func markerText(scope: Int) -> String? {
        markerTextByScope[scope]
    }

    func displayedMarkerText(scope: Int) -> String? {
        presentations[scope]?.contentView.markerText
    }

    func textAndLinks(for scope: Int) -> (String, [BalloonTextLink])? {
        presentations[scope].map { ($0.text, $0.links) }
    }

    func displayedText(for scope: Int) -> String? {
        presentations[scope]?.contentView.text
    }

    func isRepaintLocked(scope: Int) -> Bool {
        repaintLockedScopes.contains(scope)
    }

    func isMovementLocked(scope: Int) -> Bool {
        movementLockedScopes.contains(scope)
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
        let markerImage = balloonLoader.markerImageURL(speaker: speaker, in: balloon)
            .flatMap { try? imageLoader.loadUsingTopLeftTransparency($0) }
        let scaledSize = NSSize(
            width: image.size.width * displayScale,
            height: image.size.height * displayScale
        )
        let existingPresentation = presentations[scope]
        let contentView = BalloonContentView(
            frame: NSRect(origin: .zero, size: scaledSize),
            image: image,
            arrowImage: arrowImage,
            markerImage: markerImage,
            balloon: balloon,
            text: repaintLockedScopes.contains(scope) ? existingPresentation?.contentView.text ?? "" : text,
            displayScale: displayScale,
            textScale: textScale
        )
        contentView.onClick = { [weak self] in
            self?.onClick?(scope)
        }
        contentView.onLinkClick = { [weak self] id, arguments in
            self?.onLinkClick?(id, arguments)
        }
        contentView.isMovementLocked = movementLockedScopes.contains(scope)
        contentView.setMarkerText(markerTextByScope[scope] ?? "")

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
        let presentation = BalloonPresentation(
            window: window,
            contentView: contentView,
            balloon: balloon,
            speaker: speaker,
            style: style,
            surfaceFrame: surfaceFrame
        )
        presentation.text = text
        presentations[scope] = presentation
    }

    public func updateText(_ text: String, scope: Int = 0) {
        presentations[scope]?.text = text
        presentations[scope]?.links = []
        presentations[scope]?.styles = []
        guard !repaintLockedScopes.contains(scope) else { return }
        presentations[scope]?.contentView.text = text
    }

    public func updateContent(text: String, links: [BalloonTextLink], scope: Int = 0) {
        updateContent(text: text, links: links, styles: [], scope: scope)
    }

    public func updateContent(
        text: String,
        links: [BalloonTextLink],
        styles: [BalloonTextStyleRun],
        autoscroll: Bool = true,
        scope: Int = 0
    ) {
        presentations[scope]?.text = text
        presentations[scope]?.links = links
        presentations[scope]?.styles = styles
        guard !repaintLockedScopes.contains(scope) else { return }
        presentations[scope]?.contentView.update(
            text: text,
            links: links,
            styles: styles,
            autoscroll: autoscroll
        )
    }

    public func setRepaintLocked(_ locked: Bool, scope: Int) {
        if locked {
            repaintLockedScopes.insert(scope)
            return
        }
        repaintLockedScopes.remove(scope)
        guard let presentation = presentations[scope] else { return }
        presentation.contentView.update(
            text: presentation.text,
            links: presentation.links,
            styles: presentation.styles
        )
    }

    public func setMovementLocked(_ locked: Bool, scope: Int) {
        if locked {
            movementLockedScopes.insert(scope)
        } else {
            movementLockedScopes.remove(scope)
        }
        presentations[scope]?.contentView.isMovementLocked = locked
    }

    public func changeStyle(_ style: Int, scope: Int = 0) throws {
        guard let presentation = presentations[scope] else { return }
        let wasVisible = presentation.window.isVisible
        try show(
            balloon: presentation.balloon,
            text: presentation.text,
            scope: scope,
            speaker: presentation.speaker,
            style: style,
            near: presentation.surfaceFrame
        )
        updateContent(
            text: presentation.text,
            links: presentation.links,
            styles: presentation.styles,
            scope: scope
        )
        setWaitingForClick(presentation.isWaitingForClick, scope: scope)
        if !wasVisible {
            hide(scope: scope)
        }
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

    public func setAutomaticLineWrapping(_ enabled: Bool, scope: Int) {
        presentations[scope]?.contentView.setAutomaticLineWrapping(enabled)
    }

    public func setVerticalAlignment(_ alignment: BalloonVerticalAlignment, scope: Int) {
        presentations[scope]?.contentView.setVerticalAlignment(alignment)
    }

    public func setMarkerText(_ text: String, scope: Int) {
        if text.isEmpty {
            markerTextByScope.removeValue(forKey: scope)
        } else {
            markerTextByScope[scope] = text
        }
        presentations[scope]?.contentView.setMarkerText(text)
    }

    public func hide(scope: Int = 0) {
        presentations[scope]?.window.orderOut(nil)
    }

    public func hideAll() {
        for presentation in presentations.values {
            presentation.window.orderOut(nil)
        }
    }

    public func resetWindowPositions() {
        for (scope, presentation) in presentations {
            positionStore.remove(for: .balloon, scope: scope)
            place(presentation.window, near: presentation.surfaceFrame)
            positionStore.remove(for: .balloon, scope: scope)
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
        window.acceptsMouseMovedEvents = true
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
                presentation.styles,
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
            updateContent(text: snapshot.5, links: snapshot.6, styles: snapshot.7, scope: snapshot.0)
            setWaitingForClick(snapshot.8, scope: snapshot.0)
            if !snapshot.9 {
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
    var styles: [BalloonTextStyleRun] = []
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
    private let markerImage: NSImage?
    private let markerTextField = NSTextField(labelWithString: "")
    private let textFont: NSFont
    private let textColor: NSColor
    private let displayScale: CGFloat
    private let textScale: CGFloat
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    var isMovementLocked = false
    private var verticalAlignment: BalloonVerticalAlignment = .top
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

    var verticalContentInset: CGFloat {
        scrollView.contentInsets.top
    }

    var markerText: String {
        markerTextField.stringValue
    }

    func textAttributes(at location: Int) -> [NSAttributedString.Key: Any]? {
        guard let textStorage = textView.textStorage,
              location >= 0,
              location < textStorage.length
        else { return nil }
        return textStorage.attributes(at: location, effectiveRange: nil)
    }

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    func setAutomaticLineWrapping(_ enabled: Bool) {
        textView.textContainer?.widthTracksTextView = enabled
        textView.textContainer?.lineBreakMode = enabled ? .byWordWrapping : .byClipping
        textView.textContainer?.containerSize.width = enabled
            ? textView.frame.width
            : .greatestFiniteMagnitude
        textView.needsLayout = true
    }

    func setVerticalAlignment(_ alignment: BalloonVerticalAlignment) {
        verticalAlignment = alignment
        updateVerticalAlignment()
    }

    func setMarkerText(_ text: String) {
        markerTextField.stringValue = text
        markerTextField.isHidden = text.isEmpty
    }

    init(
        frame: NSRect,
        image: NSImage,
        arrowImage: NSImage?,
        markerImage: NSImage?,
        balloon: BalloonDefinition,
        text: String,
        displayScale: CGFloat,
        textScale: CGFloat
    ) {
        textView = InteractiveTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        arrowView = arrowImage.map(NSImageView.init(image:))
        self.markerImage = markerImage
        textFont = .systemFont(ofSize: CGFloat(balloon.fontHeight) * displayScale * textScale)
        self.displayScale = displayScale
        self.textScale = textScale
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
        textView.defaultTextColor = textColor
        textView.appearanceByKind = [
            .choice: (balloon.cursorNotSelectedStyle, balloon.cursorStyle),
            .anchor: (balloon.anchorNotSelectedStyle, balloon.anchorStyle)
        ]
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

        markerTextField.alignment = .center
        markerTextField.font = .systemFont(ofSize: max(9, textFont.pointSize * 0.75))
        markerTextField.textColor = textColor
        markerTextField.drawsBackground = false
        markerTextField.isBordered = false
        markerTextField.isHidden = true
        markerTextField.frame = NSRect(
            x: textFrame.minX,
            y: max(textFrame.maxY, bounds.height - markerTextField.intrinsicContentSize.height - 2),
            width: textFrame.width,
            height: markerTextField.intrinsicContentSize.height
        )
        addSubview(markerTextField)

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
        guard !isMovementLocked else { return }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isMovementLocked else { return }
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
    func update(
        text: String,
        links: [BalloonTextLink],
        styles: [BalloonTextStyleRun] = [],
        autoscroll: Bool = true
    ) {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: textFont,
                .foregroundColor: textColor
            ]
        )
        for run in styles where NSMaxRange(run.range) <= attributedText.length {
            attributedText.addAttributes(attributes(for: run.style), range: run.range)
        }
        var linkTargets: [String: BalloonTextLink] = [:]
        for (index, link) in links.enumerated() where NSMaxRange(link.range) <= attributedText.length {
            let token = "utatane-link-\(index)"
            let fontColor = link.fontColor.map(NSColor.init(balloonColor:)) ?? NSColor.linkColor
            attributedText.addAttributes(
                [
                    .link: token,
                    .foregroundColor: fontColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: link.range
            )
            linkTargets[token] = link
        }
        if let markerImage {
            let source = attributedText.string as NSString
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let range = source.range(of: "\u{FFFC}", options: [], range: searchRange)
                guard range.location != NSNotFound else { break }
                let attachment = NSTextAttachment()
                attachment.image = markerImage
                let markerHeight = min(markerImage.size.height * displayScale, textFont.pointSize)
                let markerWidth = markerImage.size.height > 0
                    ? markerImage.size.width * markerHeight / markerImage.size.height
                    : markerHeight
                attachment.bounds = NSRect(
                    x: 0,
                    y: textFont.descender,
                    width: markerWidth,
                    height: markerHeight
                )
                attributedText.addAttribute(.attachment, value: attachment, range: range)
                let nextLocation = NSMaxRange(range)
                searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
            }
        }
        textView.linkTargets = linkTargets
        textView.textStorage?.setAttributedString(attributedText)
        textView.refreshLinkAppearance()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        updateVerticalAlignment()
        if autoscroll, attributedText.length > 0 {
            textView.scrollRangeToVisible(NSRange(location: attributedText.length, length: 0))
        }
    }

    private func updateVerticalAlignment() {
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        layoutManager.ensureLayout(for: textContainer)
        let remaining = max(0, scrollView.bounds.height - layoutManager.usedRect(for: textContainer).height)
        let top = switch verticalAlignment {
        case .top: CGFloat.zero
        case .center: remaining / 2
        case .bottom: remaining
        }
        scrollView.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
    }

    private func attributes(for style: BalloonTextStyle) -> [NSAttributedString.Key: Any] {
        let defaultUnscaledSize = textFont.pointSize / displayScale
        let size = style.fontHeight.map { CGFloat($0) * displayScale * textScale }
            ?? defaultUnscaledSize * displayScale
        let baseFont = style.fontName.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if style.bold {
            traits.insert(.boldFontMask)
        }
        if style.italic {
            traits.insert(.italicFontMask)
        }
        let font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
        var result: [NSAttributedString.Key: Any] = [:]
        if style.fontName != nil || style.fontHeight != nil || style.bold || style.italic {
            result[.font] = font
        }
        if let color = style.color {
            result[.foregroundColor] = NSColor(balloonColor: color)
        }
        if style.strike {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.underline {
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.baseline != 0 {
            result[.baselineOffset] = CGFloat(style.baseline) * font.pointSize * 0.3
        }
        if style.alignment != nil || style.lineHeight != nil {
            let paragraph = NSMutableParagraphStyle()
            if let alignment = style.alignment {
                paragraph.alignment = switch alignment {
                case .left: .left
                case .center: .center
                case .right: .right
                }
            }
            if let lineHeight = style.lineHeight {
                paragraph.minimumLineHeight = CGFloat(lineHeight) * displayScale * textScale
                paragraph.maximumLineHeight = CGFloat(lineHeight) * displayScale * textScale
            }
            result[.paragraphStyle] = paragraph
        }
        if let shadowColor = style.shadowColor {
            let color = NSColor(balloonColor: shadowColor)
            if style.shadowStyle == "outline" {
                result[.strokeColor] = color
                result[.strokeWidth] = -3
            } else {
                let shadow = NSShadow()
                shadow.shadowColor = color
                shadow.shadowOffset = NSSize(
                    width: max(1, displayScale),
                    height: -max(1, displayScale)
                )
                shadow.shadowBlurRadius = 0
                result[.shadow] = shadow
            }
        }
        if style.outline {
            result[.strokeColor] = NSColor.white
            result[.strokeWidth] = 3
        }
        return result
    }

    private func scaledCoordinate(_ value: Int, extent: CGFloat) -> CGFloat {
        let coordinate = CGFloat(value) * displayScale
        return coordinate < 0 ? extent + coordinate : coordinate
    }
}

private final class InteractiveTextView: NSTextView, NSTextViewDelegate {
    var linkTargets: [String: BalloonTextLink] = [:]
    var appearanceByKind: [BalloonTextLink.Kind: (normal: BalloonLinkAppearance, hovered: BalloonLinkAppearance)] = [:]
    var defaultTextColor = NSColor.textColor
    var onBackgroundClick: (() -> Void)?
    var onLinkClick: ((String, [String]) -> Void)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    private var hoveredLinkToken: String?
    private var mouseTrackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let token = balloonTextLinkID(at: point, in: self)
        guard token != hoveredLinkToken else { return }
        hoveredLinkToken = token
        refreshLinkAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredLinkToken != nil else { return }
        hoveredLinkToken = nil
        refreshLinkAppearance()
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

    func refreshLinkAppearance() {
        guard let textStorage else { return }
        for (token, link) in linkTargets where NSMaxRange(link.range) <= textStorage.length {
            textStorage.removeAttribute(.backgroundColor, range: link.range)
            textStorage.removeAttribute(.underlineStyle, range: link.range)
            textStorage.removeAttribute(.underlineColor, range: link.range)
            let pair = appearanceByKind[link.kind]
            let appearance = token == hoveredLinkToken ? pair?.hovered : pair?.normal
            textStorage.addAttribute(
                .foregroundColor,
                value: link.fontColor.map(NSColor.init(balloonColor:))
                    ?? appearance?.fontColor.map(NSColor.init(balloonColor:))
                    ?? defaultTextColor,
                range: link.range
            )
            guard let appearance else { continue }
            if appearance.shape == .square || appearance.shape == .squareUnderline {
                textStorage.addAttribute(
                    .backgroundColor,
                    value: appearance.brushColor.map(NSColor.init(balloonColor:)) ?? NSColor.selectedTextBackgroundColor,
                    range: link.range
                )
            }
            if appearance.shape == .underline || appearance.shape == .squareUnderline {
                textStorage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: link.range
                )
                if let penColor = appearance.penColor {
                    textStorage.addAttribute(
                        .underlineColor,
                        value: NSColor(balloonColor: penColor),
                        range: link.range
                    )
                }
            }
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

private extension NSColor {
    convenience init(balloonColor: BalloonColor) {
        self.init(
            calibratedRed: CGFloat(min(max(balloonColor.red, 0), 255)) / 255,
            green: CGFloat(min(max(balloonColor.green, 0), 255)) / 255,
            blue: CGFloat(min(max(balloonColor.blue, 0), 255)) / 255,
            alpha: 1
        )
    }
}

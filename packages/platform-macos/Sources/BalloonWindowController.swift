import AppKit
import UtataneBalloon
import UtataneCore
import UtataneShell

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
    public let normalAppearance: BalloonLinkAppearanceOverride?
    public let hoveredAppearance: BalloonLinkAppearanceOverride?
    public let visitedAppearance: BalloonLinkAppearanceOverride?

    public init(
        range: NSRange,
        id: String,
        arguments: [String],
        kind: Kind = .choice,
        fontColor: BalloonColor? = nil,
        normalAppearance: BalloonLinkAppearanceOverride? = nil,
        hoveredAppearance: BalloonLinkAppearanceOverride? = nil,
        visitedAppearance: BalloonLinkAppearanceOverride? = nil
    ) {
        self.range = range
        self.id = id
        self.arguments = arguments
        self.kind = kind
        self.fontColor = fontColor
        self.normalAppearance = normalAppearance
        self.hoveredAppearance = hoveredAppearance
        self.visitedAppearance = visitedAppearance
    }
}

public struct BalloonLinkAppearanceOverride: Sendable, Equatable {
    public var shape: BalloonLinkShape?
    public var fontColor: BalloonColor?
    public var penColor: BalloonColor?
    public var brushColor: BalloonColor?

    public init(
        shape: BalloonLinkShape? = nil,
        fontColor: BalloonColor? = nil,
        penColor: BalloonColor? = nil,
        brushColor: BalloonColor? = nil
    ) {
        self.shape = shape
        self.fontColor = fontColor
        self.penColor = penColor
        self.brushColor = brushColor
    }

    func applying(to base: BalloonLinkAppearance) -> BalloonLinkAppearance {
        BalloonLinkAppearance(
            shape: shape ?? base.shape,
            fontColor: fontColor ?? base.fontColor,
            penColor: penColor ?? base.penColor,
            brushColor: brushColor ?? base.brushColor
        )
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
    public var cursorAppearance = BalloonLinkAppearanceOverride()
    public var cursorNotSelectedAppearance = BalloonLinkAppearanceOverride()
    public var anchorAppearance = BalloonLinkAppearanceOverride()
    public var anchorNotSelectedAppearance = BalloonLinkAppearanceOverride()
    public var anchorVisitedAppearance = BalloonLinkAppearanceOverride()
    public var lineHeight: Double?
    public var paragraphIndent: Double?
    public var paragraphSpacingBefore: Double?
    public var rightTabStop: Double?
    public var bold = false
    public var italic = false
    public var strike = false
    public var underline = false
    public var baseline = 0
    public var resetsFontDecorations = false

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

public enum BalloonWindowAlignment: Sendable, Equatable {
    case left
    case center
    case right
    case bottom
    case automatic

    init(_ alignment: ShellBalloonAlignment) {
        self = switch alignment {
        case .none: .automatic
        case .left: .left
        case .right: .right
        }
    }
}

@MainActor
public final class BalloonWindowController {
    private struct RuntimeOffset {
        let point: NSPoint
        let isRelativeX: Bool
        let isRelativeY: Bool
    }

    private let balloonLoader = BalloonLoader()
    private let imageLoader = SurfaceImageLoader()
    private let positionStore: WindowPositionStore
    private let geometryProvider: any PresentationGeometryProviding
    private let presentationHost: any PresentationHosting
    private var presentations: [Int: BalloonPresentation] = [:]
    private var repaintLockedScopes: Set<Int> = []
    private var movementLockedScopes: Set<Int> = []
    private var markerTextByScope: [Int: String] = [:]
    private var numberTextByScope: [Int: String] = [:]
    private var onlineModeScopes: Set<Int> = []
    private var sstpMessageByScope: [Int: String] = [:]
    private var offsetByScope: [Int: RuntimeOffset] = [:]
    private var placementOriginByScope: [Int: NSPoint] = [:]
    private var alignmentByScope: [Int: BalloonWindowAlignment] = [:]
    private var shellPresentationSettings: [Int: ShellScopePresentationSettings] = [:]
    private var displayScale: CGFloat = 1
    private var surfaceDisplayScale: CGFloat = 1
    private var textScale: CGFloat = 1
    private var stayOnTop = true
    private var presentationHidden = false
    private var visitedAnchorIDs: Set<String> = []

    public var onClick: (@MainActor (Int) -> Void)?
    public var onDoubleClick: (@MainActor (Int) -> Void)?
    public var onLinkClick: (@MainActor (String, [String]) -> Void)?
    public var onLinkActivate: (@MainActor (BalloonTextLink, String) -> Void)?
    public var onLinkEnter: (@MainActor (BalloonTextLink?, String?) -> Void)?
    public var onLinkHover: (@MainActor (BalloonTextLink, String) -> Void)?

    public init(
        positionStore: WindowPositionStore = WindowPositionStore(),
        geometryProvider: any PresentationGeometryProviding = SystemPresentationGeometryProvider()
    ) {
        self.positionStore = positionStore
        self.geometryProvider = geometryProvider
        presentationHost = DesktopPresentationHost(geometryProvider: geometryProvider)
    }

    public init(
        positionStore: WindowPositionStore = WindowPositionStore(),
        presentationSession: GhostPresentationSession
    ) {
        self.positionStore = positionStore
        geometryProvider = presentationSession.geometryProvider
        presentationHost = presentationSession.presentationHost
    }

    init(
        positionStore: WindowPositionStore = WindowPositionStore(),
        presentationHost: any PresentationHosting
    ) {
        self.positionStore = positionStore
        geometryProvider = presentationHost.geometryProvider
        self.presentationHost = presentationHost
    }

    public func setStayOnTop(_ stayOnTop: Bool) {
        self.stayOnTop = stayOnTop
        for presentation in presentations.values {
            presentation.item.setStaysOnTop(stayOnTop)
        }
    }

    public func setPresentationHidden(_ hidden: Bool) {
        presentationHidden = hidden
        for presentation in presentations.values {
            presentation.item.alphaValue = hidden ? 0 : 1
        }
    }

    public func setPositionContentID(_ contentID: URL?) {
        resetContent()
        positionStore.setContentID(contentID)
    }

    public func resetContent() {
        for presentation in presentations.values {
            presentation.item.discard()
        }
        presentations.removeAll()
        repaintLockedScopes.removeAll()
        movementLockedScopes.removeAll()
        markerTextByScope.removeAll()
        numberTextByScope.removeAll()
        onlineModeScopes.removeAll()
        sstpMessageByScope.removeAll()
        visitedAnchorIDs.removeAll()
        offsetByScope.removeAll()
        placementOriginByScope.removeAll()
        alignmentByScope.removeAll()
        shellPresentationSettings.removeAll()
    }

    public func setDisplayScale(_ scale: Double, textScale: Double, surfaceScale: Double? = nil) {
        displayScale = CGFloat(min(max(scale, 0.5), 2))
        if let surfaceScale {
            surfaceDisplayScale = CGFloat(min(max(surfaceScale, 0.5), 2))
        }
        self.textScale = CGFloat(min(max(textScale, 0.5), 2))
        rebuildPresentations()
    }

    public func configure(shell: ShellDefinition) {
        shellPresentationSettings = shell.presentationSettings
        for (scope, presentation) in presentations {
            presentation.contentView.isMovementLocked = effectiveMovementLock(scope: scope)
        }
        rebuildPresentations()
        for scope in presentations.keys {
            reposition(scope: scope)
        }
    }

    public var visibleScopes: [Int] {
        presentations.compactMap { scope, presentation in
            presentation.item.isVisible ? scope : nil
        }.sorted()
    }

    public var windowNumbers: [Int] {
        presentations.keys.sorted().compactMap { presentations[$0]?.item.captureWindowNumber }
    }

    public func windowFrame(for scope: Int) -> NSRect? {
        presentations[scope]?.item.frame
    }

    public var layoutPresetPositions: [Int: CGPoint] {
        presentations.mapValues { $0.item.frame.origin }
    }

    public func restoreLayoutPresetPositions(_ positions: [Int: CGPoint]) {
        for (scope, origin) in positions where origin.x.isFinite && origin.y.isFinite {
            positionStore.remove(for: .balloon, scope: scope, coordinateSpace: geometryProvider.coordinateSpace)
            positionStore.save(origin, for: .balloon, scope: scope, coordinateSpace: geometryProvider.coordinateSpace)
            if let item = presentations[scope]?.item {
                let restored = positionStore.restoredOrigin(
                    for: .balloon, scope: scope, windowSize: item.frame.size,
                    visibleFrames: geometryProvider.visibleFrames, coordinateSpace: geometryProvider.coordinateSpace
                ) ?? origin
                if let base = placementOriginByScope[scope] {
                    positionStore.saveBalloonDragOffset(NSPoint(x: restored.x - base.x, y: restored.y - base.y),
                                                        scope: scope, coordinateSpace: geometryProvider.coordinateSpace)
                }
                item.setFrameOrigin(restored)
            }
        }
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

    func scrollArrowVisibility(scope: Int) -> (previous: Bool, next: Bool)? {
        presentations[scope]?.contentView.scrollArrowVisibility
    }

    func isOnlineMarkerVisible(scope: Int) -> Bool {
        presentations[scope]?.contentView.isOnlineMarkerVisible ?? false
    }

    func displayedSSTPMessage(scope: Int) -> String? {
        presentations[scope]?.contentView.sstpMessage
    }

    func textAttributes(at location: Int, scope: Int) -> [NSAttributedString.Key: Any]? {
        presentations[scope]?.contentView.textAttributes(at: location)
    }

    func positionedImageFrames(scope: Int) -> [NSRect] {
        presentations[scope]?.contentView.positionedImageFrames ?? []
    }

    func textLayoutOrientation(scope: Int) -> NSLayoutManager.TextLayoutOrientation? {
        presentations[scope]?.contentView.textLayoutOrientation
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

    func numberText(scope: Int) -> String? {
        numberTextByScope[scope]
    }

    func offset(scope: Int) -> NSPoint? {
        offsetByScope[scope]?.point
    }

    func alignment(scope: Int) -> BalloonWindowAlignment? {
        alignmentByScope[scope]
            ?? shellPresentationSettings[scope]?.balloonAlignment.map(BalloonWindowAlignment.init)
    }

    func markAnchorVisited(_ id: String) {
        visitedAnchorIDs.insert(id)
        for presentation in presentations.values {
            presentation.contentView.visitedAnchorIDs = visitedAnchorIDs
        }
    }

    func textAndLinks(for scope: Int) -> (String, [BalloonTextLink])? {
        presentations[scope].map { ($0.text, $0.links) }
    }

    func contentSnapshots(scopes: some Sequence<Int>) -> [Int: BalloonContentSnapshot] {
        Dictionary(uniqueKeysWithValues: scopes.compactMap { scope in
            presentations[scope].map { presentation in
                (scope, BalloonContentSnapshot(
                    text: presentation.text,
                    links: presentation.links,
                    styles: presentation.styles,
                    inlineImages: presentation.inlineImages
                ))
            }
        })
    }

    func displayedText(for scope: Int) -> String? {
        presentations[scope]?.contentView.text
    }

    func isRepaintLocked(scope: Int) -> Bool {
        repaintLockedScopes.contains(scope)
    }

    func isMovementLocked(scope: Int) -> Bool {
        effectiveMovementLock(scope: scope)
    }

    public func show(
        balloon: BalloonDefinition,
        text: String,
        scope: Int = 0,
        speaker: BalloonSpeaker = .sakura,
        style: Int = 0,
        near surfaceFrame: NSRect
    ) throws {
        let effectiveBalloon = balloonLoader.effectiveDefinition(for: balloon, speaker: speaker, style: style)
        let imageURL = try balloonLoader.imageURL(speaker: speaker, style: style, in: effectiveBalloon)
        let image = try loadImage(imageURL, balloon: effectiveBalloon)
        let clickWaitMarkerImage = balloonLoader.clickWaitMarkerImageURL(
            speaker: speaker,
            style: style,
            in: effectiveBalloon
        ).flatMap { try? loadImage($0, balloon: effectiveBalloon) }
        let scrollArrow0Image = balloonLoader.arrowImageURL(
            index: 0,
            speaker: speaker,
            style: style,
            in: effectiveBalloon
        ).flatMap { try? loadImage($0, balloon: effectiveBalloon) }
        let scrollArrow1Image = balloonLoader.arrowImageURL(
            index: 1,
            speaker: speaker,
            style: style,
            in: effectiveBalloon
        ).flatMap { try? loadImage($0, balloon: effectiveBalloon) }
        let onlineMarkerImages = balloonLoader.onlineMarkerImageURLs(
            speaker: speaker,
            style: style,
            in: effectiveBalloon
        ).compactMap { try? loadImage($0, balloon: effectiveBalloon) }
        let sstpMarkerImage = balloonLoader.sstpMarkerImageURL(
            speaker: speaker,
            style: style,
            in: effectiveBalloon
        ).flatMap { try? loadImage($0, balloon: effectiveBalloon) }
        let markerImage = balloonLoader.markerImageURL(speaker: speaker, style: style, in: effectiveBalloon)
            .flatMap { try? loadImage($0, balloon: effectiveBalloon) }
        let scopeDisplayScale = effectiveDisplayScale(scope: scope)
        let scaledSize = NSSize(
            width: image.size.width * scopeDisplayScale,
            height: image.size.height * scopeDisplayScale
        )
        let existingPresentation = presentations[scope]
        let existingPositionedImages = existingPresentation?.positionedImages ?? []
        let contentView = BalloonContentView(
            frame: NSRect(origin: .zero, size: scaledSize),
            image: image,
            clickWaitMarkerImage: clickWaitMarkerImage,
            scrollArrow0Image: scrollArrow0Image,
            scrollArrow1Image: scrollArrow1Image,
            onlineMarkerImages: onlineMarkerImages,
            sstpMarkerImage: sstpMarkerImage,
            markerImage: markerImage,
            balloon: effectiveBalloon,
            text: repaintLockedScopes.contains(scope) ? existingPresentation?.contentView.text ?? "" : text,
            displayScale: scopeDisplayScale,
            textScale: textScale
        )
        contentView.visitedAnchorIDs = visitedAnchorIDs
        contentView.onClick = { [weak self] in
            self?.onClick?(scope)
        }
        contentView.onDoubleClick = { [weak self] in
            self?.onDoubleClick?(scope)
        }
        contentView.onLinkClick = { [weak self] id, arguments in
            self?.onLinkClick?(id, arguments)
        }
        contentView.onLinkActivate = { [weak self] link, label in
            if link.kind == .anchor {
                self?.markAnchorVisited(link.id)
            }
            self?.onLinkActivate?(link, label)
        }
        contentView.onLinkEnter = { [weak self] link, label in self?.onLinkEnter?(link, label) }
        contentView.onLinkHover = { [weak self] link, label in self?.onLinkHover?(link, label) }
        contentView.isMovementLocked = effectiveMovementLock(scope: scope)
        contentView.setMarkerText(markerTextByScope[scope] ?? "")
        contentView.setNumberText(numberTextByScope[scope] ?? "")
        contentView.setOnlineMode(onlineModeScopes.contains(scope))
        contentView.setSSTPMessage(sstpMessageByScope[scope])
        contentView.setPositionedImages(existingPositionedImages)

        let item = existingPresentation?.item ?? makePresentationItem(scope: scope)
        item.contentView = contentView
        item.setContentSize(scaledSize)
        configureDragging(contentView, item: item)
        place(item, near: surfaceFrame, scope: scope, balloon: effectiveBalloon)
        // Migrate legacy absolute positions once. New drags are stored separately
        // from the script/shell offset so subsequent layout changes preserve them.
        if positionStore.balloonDragOffset(scope: scope, coordinateSpace: geometryProvider.coordinateSpace) == nil,
           let restored = positionStore.restoredOrigin(
               for: .balloon, scope: scope, windowSize: scaledSize,
               visibleFrames: geometryProvider.visibleFrames, coordinateSpace: geometryProvider.coordinateSpace
           ), let base = placementOriginByScope[scope]
        {
            positionStore.saveBalloonDragOffset(NSPoint(x: restored.x - base.x, y: restored.y - base.y),
                                                scope: scope, coordinateSpace: geometryProvider.coordinateSpace)
            place(item, near: surfaceFrame, scope: scope, balloon: effectiveBalloon)
        }
        item.show(activating: true)
        item.alphaValue = presentationHidden ? 0 : 1
        let presentation = BalloonPresentation(
            item: item,
            contentView: contentView,
            balloon: effectiveBalloon,
            speaker: speaker,
            style: style,
            surfaceFrame: surfaceFrame
        )
        presentation.text = text
        presentation.positionedImages = existingPositionedImages
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

    public func addPositionedImage(
        _ image: NSImage,
        x: Int,
        y: Int,
        foreground: Bool = false,
        scope: Int = 0
    ) {
        guard let presentation = presentations[scope] else { return }
        let item = PositionedBalloonImage(image: image, x: x, y: y, foreground: foreground)
        presentation.positionedImages.append(item)
        presentation.contentView.setPositionedImages(presentation.positionedImages)
    }

    public func clearPositionedImages(scope: Int? = nil) {
        let targetScopes = scope.map { [$0] } ?? Array(presentations.keys)
        for targetScope in targetScopes {
            guard let presentation = presentations[targetScope] else { continue }
            presentation.positionedImages.removeAll()
            presentation.contentView.setPositionedImages([])
        }
    }

    public func textCursorPosition(scope: Int) -> NSPoint {
        presentations[scope]?.contentView.textCursorPosition ?? .zero
    }

    public func textContentSize(scope: Int) -> NSSize {
        presentations[scope]?.contentView.textContentSize ?? .zero
    }

    public func updateContent(
        text: String,
        links: [BalloonTextLink],
        styles: [BalloonTextStyleRun],
        inlineImages: [NSRange: NSImage] = [:],
        autoscroll: Bool = true,
        scope: Int = 0
    ) {
        presentations[scope]?.text = text
        presentations[scope]?.links = links
        presentations[scope]?.styles = styles
        presentations[scope]?.inlineImages = inlineImages
        guard !repaintLockedScopes.contains(scope) else { return }
        presentations[scope]?.contentView.update(
            text: text,
            links: links,
            styles: styles,
            inlineImages: inlineImages,
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
            styles: presentation.styles,
            inlineImages: presentation.inlineImages
        )
    }

    public func setMovementLocked(_ locked: Bool, scope: Int) {
        if locked {
            movementLockedScopes.insert(scope)
        } else {
            movementLockedScopes.remove(scope)
        }
        presentations[scope]?.contentView.isMovementLocked = effectiveMovementLock(scope: scope)
    }

    public func changeStyle(_ style: Int, scope: Int = 0) throws {
        guard let presentation = presentations[scope] else { return }
        if style < 0 {
            hide(scope: scope)
            return
        }
        let wasVisible = presentation.item.isVisible
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

    public func setOnlineMode(_ enabled: Bool, scope: Int) {
        if enabled {
            onlineModeScopes.insert(scope)
        } else {
            onlineModeScopes.remove(scope)
        }
        presentations[scope]?.contentView.setOnlineMode(enabled)
    }

    public func setSSTPMessage(_ message: String?, scope: Int = 0) {
        if let message, !message.isEmpty {
            sstpMessageByScope[scope] = message
        } else {
            sstpMessageByScope.removeValue(forKey: scope)
        }
        presentations[scope]?.contentView.setSSTPMessage(message)
    }

    public func setNumber(file: String, current: String, maximum: String, scope: Int) {
        let components = [file, current, maximum].filter { !$0.isEmpty }
        let text = if !current.isEmpty, !maximum.isEmpty {
            [file, "\(current)/\(maximum)"].filter { !$0.isEmpty }.joined(separator: " ")
        } else {
            components.joined(separator: " ")
        }
        if text.isEmpty {
            numberTextByScope.removeValue(forKey: scope)
        } else {
            numberTextByScope[scope] = text
        }
        presentations[scope]?.contentView.setNumberText(text)
    }

    public func setOffset(
        x: Int,
        y: Int,
        isRelativeX: Bool = true,
        isRelativeY: Bool = true,
        near surfaceFrame: NSRect? = nil,
        scope: Int
    ) {
        if let surfaceFrame {
            presentations[scope]?.surfaceFrame = surfaceFrame
        }
        offsetByScope[scope] = RuntimeOffset(
            point: NSPoint(x: x, y: y),
            isRelativeX: isRelativeX,
            isRelativeY: isRelativeY
        )
        reposition(scope: scope)
    }

    public func resetOffset(scope: Int, near surfaceFrame: NSRect? = nil) {
        if let surfaceFrame {
            presentations[scope]?.surfaceFrame = surfaceFrame
        }
        offsetByScope.removeValue(forKey: scope)
        reposition(scope: scope)
    }

    public func setAlignment(_ alignment: BalloonWindowAlignment, scope: Int) {
        alignmentByScope[scope] = alignment
        reposition(scope: scope)
    }

    public func hide(scope: Int = 0) {
        presentations[scope]?.item.hide()
    }

    public func moveWithSurface(by delta: NSPoint, scope: Int) {
        moveWithSurface(by: delta, scope: scope, reason: .programmatic)
    }

    func moveWithSurface(
        by delta: NSPoint,
        scope: Int,
        reason: PresentationItemMoveReason
    ) {
        guard let presentation = presentations[scope] else { return }
        presentation.surfaceFrame.origin.x += delta.x
        presentation.surfaceFrame.origin.y += delta.y
        if let base = placementOriginByScope[scope] {
            placementOriginByScope[scope] = NSPoint(x: base.x + delta.x, y: base.y + delta.y)
        }
        let origin = presentation.item.frame.origin
        presentation.item.setFrameOrigin(
            NSPoint(x: origin.x + delta.x, y: origin.y + delta.y),
            reason: reason
        )
    }

    public func hideAll() {
        for presentation in presentations.values {
            presentation.item.hide()
        }
    }

    public func resetWindowPositions() {
        for (scope, presentation) in presentations {
            positionStore.remove(
                for: .balloon,
                scope: scope,
                coordinateSpace: geometryProvider.coordinateSpace
            )
            place(presentation.item, near: presentation.surfaceFrame, scope: scope, balloon: presentation.balloon)
            positionStore.remove(
                for: .balloon,
                scope: scope,
                coordinateSpace: geometryProvider.coordinateSpace
            )
        }
    }

    private func makePresentationItem(scope: Int) -> any PresentationItem {
        let item = presentationHost.makeItem(
            kind: .balloon,
            title: "Ghost Balloon \(scope)",
            restoredOrigin: { [positionStore, scope] coordinateSpace, itemSize, visibleFrames in
                positionStore.restoredOrigin(
                    for: .balloon,
                    scope: scope,
                    windowSize: itemSize,
                    visibleFrames: visibleFrames,
                    coordinateSpace: coordinateSpace
                )
            },
            onMove: { [weak self, positionStore, geometryProvider, scope] origin, reason in
                if reason == .rehost {
                    self?.placementOriginByScope.removeValue(forKey: scope)
                }
                if reason == .userInteraction {
                    if let base = self?.placementOriginByScope[scope] {
                        positionStore.saveBalloonDragOffset(NSPoint(x: origin.x - base.x, y: origin.y - base.y),
                                                            scope: scope, coordinateSpace: geometryProvider.coordinateSpace)
                    }
                    positionStore.save(
                        origin,
                        for: .balloon,
                        scope: scope,
                        coordinateSpace: geometryProvider.coordinateSpace
                    )
                }
            },
            onCancel: nil
        )
        item.setStaysOnTop(stayOnTop)
        return item
    }

    private func reposition(scope: Int) {
        guard let presentation = presentations[scope] else { return }
        place(
            presentation.item,
            near: presentation.surfaceFrame,
            scope: scope,
            balloon: presentation.balloon
        )
    }

    private func resolvedAlignment(
        for surfaceFrame: NSRect,
        balloon: BalloonDefinition,
        scope: Int
    ) -> BalloonWindowAlignment {
        let visibleFrame = geometryProvider.mainScreen?.visibleFrame ?? surfaceFrame
        let automatic: BalloonWindowAlignment = surfaceFrame.midX < visibleFrame.midX ? .right : .left
        let requested: BalloonWindowAlignment = switch balloon.windowPositionX {
        case .center: .center
        case .bottom: .bottom
        case .offset:
            alignmentByScope[scope]
                ?? shellPresentationSettings[scope]?.balloonAlignment.map(BalloonWindowAlignment.init)
                ?? .automatic
        }
        return requested == .automatic ? automatic : requested
    }

    private func configureDragging(_ contentView: BalloonContentView, item: any PresentationItem) {
        contentView.configurePresentationItem(
            frame: { [weak item] in item?.frame },
            setOrigin: { [weak item] origin in
                item?.setFrameOrigin(origin, reason: .userInteraction)
            }
        )
    }

    private func place(
        _ item: any PresentationItem,
        near surfaceFrame: NSRect,
        scope: Int,
        balloon: BalloonDefinition
    ) {
        guard let visibleFrame = geometryProvider.mainScreen?.visibleFrame else {
            item.center()
            return
        }

        let spacing: CGFloat = 8
        let alignment = resolvedAlignment(for: surfaceFrame, balloon: balloon, scope: scope)
        var x: CGFloat
        var y: CGFloat
        switch alignment {
        case .left:
            x = surfaceFrame.minX - item.frame.width - spacing
            y = surfaceFrame.maxY - item.frame.height
        case .right:
            x = surfaceFrame.maxX + spacing
            y = surfaceFrame.maxY - item.frame.height
        case .center:
            x = surfaceFrame.midX - item.frame.width / 2
            y = surfaceFrame.maxY + spacing
        case .bottom:
            x = surfaceFrame.midX - item.frame.width / 2
            y = surfaceFrame.minY - item.frame.height - spacing
        case .automatic:
            assertionFailure("automatic alignment must be resolved before placement")
            x = surfaceFrame.minX - item.frame.width - spacing
            y = surfaceFrame.maxY - item.frame.height
        }
        let runtimeOffset = offsetByScope[scope]
        let shellOffset = effectiveShellOffset(scope: scope, alignment: alignment)
        let balloonOffsetX: CGFloat = switch balloon.windowPositionX {
        case let .offset(value): CGFloat(value) * effectiveDisplayScale(scope: scope)
        case .center, .bottom: 0
        }
        x += (runtimeOffset?.point.x ?? 0)
            + (runtimeOffset?.isRelativeX == false ? 0 : shellOffset.x)
        if alignment == .left {
            x += balloonOffsetX
        } else if alignment == .right {
            x -= balloonOffsetX
        }
        y -= (runtimeOffset?.point.y ?? 0)
            + (runtimeOffset?.isRelativeY == false ? 0 : shellOffset.y)
            + CGFloat(balloon.windowPositionY) * effectiveDisplayScale(scope: scope)
        placementOriginByScope[scope] = NSPoint(x: x, y: y)
        let userOffset = positionStore.balloonDragOffset(scope: scope, coordinateSpace: geometryProvider.coordinateSpace) ?? .zero
        x += userOffset.x
        y += userOffset.y
        if balloon.limitsWindowPosition {
            x = min(max(visibleFrame.minX, x), visibleFrame.maxX - item.frame.width)
            y = min(max(visibleFrame.minY, y), visibleFrame.maxY - item.frame.height)
        }
        item.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func loadImage(_ url: URL, balloon: BalloonDefinition) throws -> NSImage {
        let maskURL = url.deletingPathExtension().appendingPathExtension("pna")
        let asset = SurfaceAsset(
            id: -1,
            imageURL: url,
            alphaMaskURL: FileManager.default.fileExists(atPath: maskURL.path) ? maskURL : nil
        )
        return try imageLoader.load(
            asset,
            usesSelfAlpha: balloon.usesSelfAlpha,
            usesFullSelfAlpha: balloon.usesFullSelfAlpha
        )
    }

    private func effectiveDisplayScale(scope: Int) -> CGFloat {
        shellPresentationSettings[scope]?.synchronizesBalloonScale == true
            ? surfaceDisplayScale
            : displayScale
    }

    private func effectiveMovementLock(scope: Int) -> Bool {
        movementLockedScopes.contains(scope)
            || shellPresentationSettings[scope]?.preventsBalloonMovement == true
    }

    private func effectiveShellOffset(scope: Int, alignment: BalloonWindowAlignment) -> NSPoint {
        guard let offsets = shellPresentationSettings[scope]?.balloonOffsets else { return .zero }
        let x: Int?
        let y: Int?
        switch alignment {
        case .left:
            x = offsets.leftX ?? offsets.x
            y = offsets.leftY ?? offsets.y
        case .right:
            x = offsets.rightX.map(-) ?? offsets.x
            y = offsets.rightY ?? offsets.y
        case .center, .bottom, .automatic:
            x = offsets.x
            y = offsets.y
        }
        let scale = effectiveDisplayScale(scope: scope)
        return NSPoint(x: CGFloat(x ?? 0) * scale, y: CGFloat(y ?? 0) * scale)
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
                presentation.item.isVisible,
                presentation.inlineImages,
                presentation.positionedImages
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
            updateContent(
                text: snapshot.5,
                links: snapshot.6,
                styles: snapshot.7,
                inlineImages: snapshot.10,
                scope: snapshot.0
            )
            presentations[snapshot.0]?.positionedImages = snapshot.11
            presentations[snapshot.0]?.contentView.setPositionedImages(snapshot.11)
            setWaitingForClick(snapshot.8, scope: snapshot.0)
            if !snapshot.9 {
                hide(scope: snapshot.0)
            }
        }
    }
}

struct BalloonContentSnapshot {
    let text: String
    let links: [BalloonTextLink]
    let styles: [BalloonTextStyleRun]
    let inlineImages: [NSRange: NSImage]
}

private struct PositionedBalloonImage {
    let image: NSImage
    let x: Int
    let y: Int
    let foreground: Bool
}

@MainActor
private final class BalloonPresentation {
    let item: any PresentationItem
    let contentView: BalloonContentView
    let balloon: BalloonDefinition
    let speaker: BalloonSpeaker
    let style: Int
    var surfaceFrame: NSRect
    var text: String
    var links: [BalloonTextLink] = []
    var styles: [BalloonTextStyleRun] = []
    var inlineImages: [NSRange: NSImage] = [:]
    var positionedImages: [PositionedBalloonImage] = []
    var isWaitingForClick = false

    init(
        item: any PresentationItem,
        contentView: BalloonContentView,
        balloon: BalloonDefinition,
        speaker: BalloonSpeaker,
        style: Int,
        surfaceFrame: NSRect
    ) {
        self.item = item
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
    private let clickWaitMarkerView: NSImageView?
    private let scrollArrow0View: ClickableImageView?
    private let scrollArrow1View: ClickableImageView?
    private let onlineMarkerView: AnimatedBalloonImageView?
    private let sstpMarkerView: NSImageView?
    private let sstpMessageField = NSTextField(labelWithString: "")
    private let markerImage: NSImage?
    private let markerTextField = NSTextField(labelWithString: "")
    private let numberTextField = NSTextField(labelWithString: "")
    private let textFont: NSFont
    private let textColor: NSColor
    private let defaultTextStyle: BalloonTextStyle
    private let displayScale: CGFloat
    private let textScale: CGFloat
    private let isVerticalWriting: Bool
    private var positionedImageViews: [NSImageView] = []
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    var isMovementLocked = false
    private var verticalAlignment: BalloonVerticalAlignment = .top
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onLinkClick: ((String, [String]) -> Void)?
    var onLinkActivate: ((BalloonTextLink, String) -> Void)?
    var onLinkEnter: ((BalloonTextLink?, String?) -> Void)?
    var onLinkHover: ((BalloonTextLink, String) -> Void)?
    private var presentationFrame: (() -> NSRect?)?
    private var setPresentationOrigin: ((NSPoint) -> Void)?

    func configurePresentationItem(
        frame: @escaping () -> NSRect?,
        setOrigin: @escaping (NSPoint) -> Void
    ) {
        presentationFrame = frame
        setPresentationOrigin = setOrigin
        textView.presentationFrame = frame
        textView.setPresentationOrigin = setOrigin
    }

    var isWaitingForClick: Bool {
        get { clickWaitMarkerView?.isHidden == false }
        set { clickWaitMarkerView?.isHidden = !newValue }
    }

    var isTextScrollable: Bool {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return false }
        let used = layoutManager.usedRect(for: textContainer)
        return isVerticalWriting
            ? used.width > scrollView.contentSize.width + 1
            : used.height > scrollView.contentSize.height + 1
    }

    var isTextAtBottom: Bool {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return true }
        let textBottom = layoutManager.usedRect(for: textContainer).maxY
        return scrollView.documentVisibleRect.maxY >= textBottom - 1
    }

    var scrollArrowVisibility: (previous: Bool, next: Bool) {
        (scrollArrow0View?.isHidden == false, scrollArrow1View?.isHidden == false)
    }

    var isOnlineMarkerVisible: Bool {
        onlineMarkerView?.isHidden == false
    }

    var sstpMessage: String? {
        sstpMessageField.isHidden ? nil : sstpMessageField.stringValue
    }

    var verticalContentInset: CGFloat {
        scrollView.contentInsets.top
    }

    var textLayoutOrientation: NSLayoutManager.TextLayoutOrientation {
        textView.layoutOrientation
    }

    var markerText: String {
        markerTextField.stringValue
    }

    var textCursorPosition: NSPoint {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              !textView.string.isEmpty
        else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        if textView.string.hasSuffix("\n") {
            let rect = layoutManager.extraLineFragmentRect
            return NSPoint(x: rect.minX / displayScale, y: rect.minY / displayScale)
        }
        let characterIndex = (textView.string as NSString).length - 1
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return .zero }
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return NSPoint(x: rect.maxX / displayScale, y: rect.minY / displayScale)
    }

    var textContentSize: NSSize {
        NSSize(
            width: scrollView.contentSize.width / displayScale,
            height: scrollView.contentSize.height / displayScale
        )
    }

    var positionedImageFrames: [NSRect] {
        positionedImageViews.map(\.frame)
    }

    func setPositionedImages(_ images: [PositionedBalloonImage]) {
        positionedImageViews.forEach { $0.removeFromSuperview() }
        positionedImageViews = images.map { item in
            let size = NSSize(
                width: item.image.size.width * displayScale,
                height: item.image.size.height * displayScale
            )
            let imageView = PassthroughImageView(frame: NSRect(
                x: CGFloat(item.x) * displayScale,
                y: CGFloat(item.y) * displayScale,
                width: size.width,
                height: size.height
            ))
            imageView.image = item.image
            imageView.imageScaling = .scaleAxesIndependently
            addSubview(
                imageView,
                positioned: item.foreground ? .above : .below,
                relativeTo: scrollView
            )
            return imageView
        }
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
        textView.textContainer?.lineBreakMode = enabled ? .byWordWrapping : .byClipping
        if isVerticalWriting {
            textView.textContainer?.heightTracksTextView = enabled
            textView.textContainer?.containerSize.height = enabled
                ? textView.frame.height
                : .greatestFiniteMagnitude
        } else {
            textView.textContainer?.widthTracksTextView = enabled
            textView.textContainer?.containerSize.width = enabled
                ? textView.frame.width
                : .greatestFiniteMagnitude
        }
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

    func setNumberText(_ text: String) {
        numberTextField.stringValue = text
        numberTextField.isHidden = text.isEmpty
    }

    func setOnlineMode(_ enabled: Bool) {
        onlineMarkerView?.setAnimating(enabled)
    }

    func setSSTPMessage(_ message: String?) {
        let message = message ?? ""
        sstpMessageField.stringValue = message
        sstpMessageField.isHidden = message.isEmpty
        sstpMarkerView?.isHidden = message.isEmpty
    }

    init(
        frame: NSRect,
        image: NSImage,
        clickWaitMarkerImage: NSImage?,
        scrollArrow0Image: NSImage?,
        scrollArrow1Image: NSImage?,
        onlineMarkerImages: [NSImage],
        sstpMarkerImage: NSImage?,
        markerImage: NSImage?,
        balloon: BalloonDefinition,
        text: String,
        displayScale: CGFloat,
        textScale: CGFloat
    ) {
        textView = InteractiveTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        clickWaitMarkerView = clickWaitMarkerImage.map(NSImageView.init(image:))
        scrollArrow0View = scrollArrow0Image.map(ClickableImageView.init(image:))
        scrollArrow1View = scrollArrow1Image.map(ClickableImageView.init(image:))
        onlineMarkerView = onlineMarkerImages.isEmpty ? nil : AnimatedBalloonImageView(
            images: onlineMarkerImages,
            intervalMilliseconds: balloon.onlineMarkerIntervalMilliseconds
        )
        sstpMarkerView = sstpMarkerImage.map(NSImageView.init(image:))
        self.markerImage = markerImage
        let fontSize = CGFloat(balloon.fontHeight) * displayScale * textScale
        let namedFont = ghostDialogueFont(named: balloon.fontName, size: fontSize)
        textFont = decoratedFont(namedFont, bold: balloon.fontBold, italic: balloon.fontItalic)
        var defaultTextStyle = BalloonTextStyle()
        defaultTextStyle.fontName = balloon.fontName
        defaultTextStyle.fontHeight = Double(balloon.fontHeight)
        defaultTextStyle.shadowColor = balloon.fontShadowColor
        defaultTextStyle.shadowStyle = balloon.fontShadowStyle
        defaultTextStyle.bold = balloon.fontBold
        defaultTextStyle.italic = balloon.fontItalic
        defaultTextStyle.underline = balloon.fontUnderline
        defaultTextStyle.strike = balloon.fontStrike
        defaultTextStyle.outline = balloon.fontOutline
        self.defaultTextStyle = defaultTextStyle
        self.displayScale = displayScale
        self.textScale = textScale
        isVerticalWriting = balloon.isVertical
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
        textView.setLayoutOrientation(balloon.isVertical ? .vertical : .horizontal)
        textView.isVerticallyResizable = !balloon.isVertical
        textView.isHorizontallyResizable = balloon.isVertical
        textView.minSize = textFrame(for: balloon).size
        textView.autoresizingMask = balloon.isVertical ? [.height] : [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = !balloon.isVertical
        textView.textContainer?.heightTracksTextView = balloon.isVertical
        textView.textContainer?.containerSize = NSSize(
            width: balloon.isVertical ? CGFloat.greatestFiniteMagnitude : textFrame(for: balloon).width,
            height: balloon.isVertical ? textFrame(for: balloon).height : CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = textView
        textView.defaultTextColor = textColor
        textView.appearanceByKind = [
            .choice: (balloon.cursorNotSelectedStyle, balloon.cursorStyle),
            .anchor: (balloon.anchorNotSelectedStyle, balloon.anchorStyle)
        ]
        textView.anchorVisitedAppearance = balloon.anchorVisitedStyle
        let textFrame = textFrame(for: balloon)
        textView.frame = NSRect(origin: .zero, size: textFrame.size)
        textView.onBackgroundClick = { [weak self] in
            self?.onClick?()
        }
        textView.onBackgroundDoubleClick = { [weak self] in
            self?.onDoubleClick?()
        }
        textView.onLinkClick = { [weak self] id, arguments in
            self?.onLinkClick?(id, arguments)
        }
        textView.onLinkActivate = { [weak self] link, label in
            self?.onLinkActivate?(link, label)
        }
        textView.onLinkEnter = { [weak self] link, label in self?.onLinkEnter?(link, label) }
        textView.onLinkHover = { [weak self] link, label in self?.onLinkHover?(link, label) }
        scrollView.frame = textFrame
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = !balloon.isVertical
        scrollView.hasHorizontalScroller = balloon.isVertical
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let observingClipView = ObservingClipView()
        observingClipView.drawsBackground = false
        observingClipView.onBoundsChange = { [weak self] in
            self?.updateScrollArrowVisibility()
        }
        scrollView.contentView = observingClipView
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

        numberTextField.alignment = .center
        numberTextField.font = ghostDialogueFont(
            named: balloon.numberFontName,
            size: CGFloat(balloon.numberFontHeight) * displayScale
        )
        numberTextField.textColor = NSColor(balloonColor: balloon.numberFontColor)
        numberTextField.drawsBackground = false
        numberTextField.isBordered = false
        numberTextField.isHidden = true
        let numberRight = scaledCoordinate(balloon.numberRightX, extent: bounds.width)
        numberTextField.frame = NSRect(
            x: textFrame.minX,
            y: scaledCoordinate(balloon.numberY, extent: bounds.height),
            width: max(1, numberRight - textFrame.minX),
            height: numberTextField.intrinsicContentSize.height
        )
        addSubview(numberTextField)

        if let clickWaitMarkerView {
            clickWaitMarkerView.imageScaling = .scaleAxesIndependently
            let sourceArrowSize = clickWaitMarkerImage?.size ?? .zero
            let arrowSize = NSSize(
                width: sourceArrowSize.width * displayScale,
                height: sourceArrowSize.height * displayScale
            )
            clickWaitMarkerView.frame = NSRect(
                x: scaledCoordinate(
                    balloon.clickWaitMarkerX,
                    extent: bounds.width
                ),
                y: scaledCoordinate(
                    balloon.clickWaitMarkerY,
                    extent: bounds.height
                ),
                width: arrowSize.width,
                height: arrowSize.height
            )
            clickWaitMarkerView.isHidden = true
            addSubview(clickWaitMarkerView)
        }

        configureScrollArrow(
            scrollArrow0View,
            image: scrollArrow0Image,
            x: balloon.arrow0X,
            y: balloon.arrow0Y,
            direction: .previous
        )
        configureScrollArrow(
            scrollArrow1View,
            image: scrollArrow1Image,
            x: balloon.arrow1X,
            y: balloon.arrow1Y,
            direction: .next
        )
        if let onlineMarkerView {
            onlineMarkerView.frame = NSRect(
                x: scaledCoordinate(balloon.onlineMarkerX, extent: bounds.width),
                y: scaledCoordinate(balloon.onlineMarkerY, extent: bounds.height),
                width: onlineMarkerView.imageSize.width * displayScale,
                height: onlineMarkerView.imageSize.height * displayScale
            )
            onlineMarkerView.imageScaling = .scaleAxesIndependently
            onlineMarkerView.isHidden = true
            addSubview(onlineMarkerView)
        }
        if let sstpMarkerView {
            sstpMarkerView.imageScaling = .scaleAxesIndependently
            sstpMarkerView.frame = NSRect(
                x: scaledCoordinate(balloon.sstpMarkerX, extent: bounds.width),
                y: scaledCoordinate(balloon.sstpMarkerY, extent: bounds.height),
                width: (sstpMarkerImage?.size.width ?? 0) * displayScale,
                height: (sstpMarkerImage?.size.height ?? 0) * displayScale
            )
            sstpMarkerView.isHidden = true
            addSubview(sstpMarkerView)
        }
        sstpMessageField.font = ghostDialogueFont(
            named: balloon.sstpMessageFontName,
            size: CGFloat(balloon.sstpMessageFontHeight) * displayScale
        )
        sstpMessageField.textColor = NSColor(balloonColor: balloon.sstpMessageFontColor)
        sstpMessageField.drawsBackground = false
        sstpMessageField.isBordered = false
        sstpMessageField.lineBreakMode = .byTruncatingTail
        let sstpMessageX = scaledCoordinate(balloon.sstpMessageX, extent: bounds.width)
        let sstpMessageY = scaledCoordinate(balloon.sstpMessageY, extent: bounds.height)
        let sstpMessageRight = balloon.sstpMessageRightX.map {
            scaledCoordinate($0, extent: bounds.width)
        } ?? bounds.width
        let sstpMessageBottom = balloon.sstpMessageBottomY.map {
            scaledCoordinate($0, extent: bounds.height)
        } ?? (sstpMessageY + sstpMessageField.intrinsicContentSize.height)
        sstpMessageField.frame = NSRect(
            x: sstpMessageX,
            y: sstpMessageY,
            width: max(1, sstpMessageRight - sstpMessageX),
            height: max(sstpMessageField.intrinsicContentSize.height, sstpMessageBottom - sstpMessageY)
        )
        sstpMessageField.isHidden = true
        addSubview(sstpMessageField)
        updateScrollArrowVisibility()
    }

    var visitedAnchorIDs: Set<String> {
        get { textView.visitedAnchorIDs }
        set {
            textView.visitedAnchorIDs = newValue
            textView.refreshLinkAppearance()
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
        dragStartWindowOrigin = presentationFrame?()?.origin ?? window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isMovementLocked else { return }
        guard let dragStartMouseLocation, let dragStartWindowOrigin else { return }
        let location = NSEvent.mouseLocation
        let delta = NSPoint(
            x: location.x - dragStartMouseLocation.x,
            y: location.y - dragStartMouseLocation.y
        )
        didDrag = didDrag || abs(delta.x) > 2 || abs(delta.y) > 2
        let origin = NSPoint(x: dragStartWindowOrigin.x + delta.x, y: dragStartWindowOrigin.y + delta.y)
        if let setPresentationOrigin {
            setPresentationOrigin(origin)
        } else {
            window?.setFrameOrigin(origin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            didDrag = false
        }
        guard !didDrag else { return }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
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
    let scaledOriginX = CGFloat(balloon.originX) * displayScale
    let originX = balloon.originX < 0 ? displayedImageSize.width + scaledOriginX : scaledOriginX
    let originY = CGFloat(balloon.originY) * displayScale
    if balloon.isVertical {
        let leftEdge = CGFloat(balloon.validRectLeft) * displayScale
        let wrapY = CGFloat(balloon.wordWrapPointY) * displayScale
        let bottomEdge: CGFloat = if wrapY < 0 {
            displayedImageSize.height + wrapY
        } else if wrapY > 0 {
            wrapY
        } else if let validRectBottom = balloon.validRectBottom {
            CGFloat(validRectBottom) * displayScale
        } else {
            displayedImageSize.height - CGFloat(balloon.validRectTop) * displayScale
        }
        return NSRect(
            x: leftEdge,
            y: originY,
            width: max(1, originX - leftEdge),
            height: max(1, bottomEdge - originY)
        )
    }
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
        inlineImages: [NSRange: NSImage] = [:],
        autoscroll: Bool = true
    ) {
        var baseAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor
        ]
        if isVerticalWriting {
            baseAttributes[.verticalGlyphForm] = 1
        }
        baseAttributes.merge(attributes(for: defaultTextStyle)) { _, new in new }
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes
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
        let source = attributedText.string as NSString
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let range = source.range(of: "\u{FFFC}", options: [], range: searchRange)
            guard range.location != NSNotFound else { break }
            let image = inlineImages[range] ?? markerImage
            if let image {
                let attachment = NSTextAttachment()
                attachment.image = image
                let font = (attributedText.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? textFont
                let imgHeight = min(image.size.height * displayScale, font.pointSize * 2)
                let imgWidth = image.size.height > 0
                    ? image.size.width * imgHeight / image.size.height
                    : imgHeight
                attachment.bounds = NSRect(
                    x: 0,
                    y: (font.capHeight - imgHeight) / 2,
                    width: imgWidth,
                    height: imgHeight
                )
                attributedText.addAttribute(.attachment, value: attachment, range: range)
            }
            let nextLocation = NSMaxRange(range)
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        textView.linkTargets = linkTargets
        textView.textStorage?.setAttributedString(attributedText)
        textView.refreshLinkAppearance()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        resizeTextDocumentToFitLayout()
        updateVerticalAlignment()
        if autoscroll, attributedText.length > 0 {
            textView.scrollRangeToVisible(NSRange(location: attributedText.length, length: 0))
        } else if attributedText.length > 0 {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        updateScrollArrowVisibility()
    }

    private func resizeTextDocumentToFitLayout() {
        guard !isVerticalWriting,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        layoutManager.ensureLayout(for: textContainer)
        let height = max(scrollView.contentSize.height, ceil(layoutManager.usedRect(for: textContainer).maxY))
        if abs(textView.frame.height - height) > 0.5 {
            textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: height))
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
        let baseFont = ghostDialogueFont(named: style.fontName, size: size)
        let font = decoratedFont(baseFont, bold: style.bold, italic: style.italic)
        var result: [NSAttributedString.Key: Any] = [:]
        if style.fontName != nil || style.fontHeight != nil || style.bold || style.italic {
            result[.font] = font
        }
        if style.italic {
            result[.obliqueness] = 0.2
        } else if style.resetsFontDecorations {
            result[.obliqueness] = 0
        }
        if let color = style.color {
            result[.foregroundColor] = NSColor(balloonColor: color)
        }
        if style.strike || style.resetsFontDecorations {
            result[.strikethroughStyle] = style.strike ? NSUnderlineStyle.single.rawValue : 0
        }
        if style.underline || style.resetsFontDecorations {
            result[.underlineStyle] = style.underline ? NSUnderlineStyle.single.rawValue : 0
        }
        if style.baseline != 0 {
            result[.baselineOffset] = CGFloat(style.baseline) * font.pointSize * 0.3
        }
        if style.alignment != nil || style.lineHeight != nil || style.paragraphIndent != nil
            || style.paragraphSpacingBefore != nil || style.rightTabStop != nil
        {
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
            if let indent = style.paragraphIndent {
                paragraph.firstLineHeadIndent = CGFloat(indent) * displayScale
                paragraph.headIndent = CGFloat(indent) * displayScale
            }
            if let spacing = style.paragraphSpacingBefore {
                paragraph.paragraphSpacingBefore = CGFloat(spacing) * displayScale
            }
            if let rightTabStop = style.rightTabStop {
                paragraph.tabStops = [NSTextTab(
                    textAlignment: .right,
                    location: CGFloat(rightTabStop) * displayScale
                )]
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
        } else if style.resetsFontDecorations, style.shadowStyle != "outline" {
            result[.strokeWidth] = 0
        }
        return result
    }

    private func scaledCoordinate(_ value: Int, extent: CGFloat) -> CGFloat {
        let coordinate = CGFloat(value) * displayScale
        return coordinate < 0 ? extent + coordinate : coordinate
    }

    private enum ScrollArrowDirection {
        case previous
        case next
    }

    private func configureScrollArrow(
        _ view: ClickableImageView?,
        image: NSImage?,
        x: Int,
        y: Int,
        direction: ScrollArrowDirection
    ) {
        guard let view, let image else { return }
        view.imageScaling = .scaleAxesIndependently
        view.frame = NSRect(
            x: scaledCoordinate(x, extent: bounds.width),
            y: scaledCoordinate(y, extent: bounds.height),
            width: image.size.width * displayScale,
            height: image.size.height * displayScale
        )
        view.isHidden = true
        view.onClick = { [weak self] in
            self?.scrollText(direction)
        }
        addSubview(view)
    }

    private func updateScrollArrowVisibility() {
        guard isTextScrollable else {
            scrollArrow0View?.isHidden = true
            scrollArrow1View?.isHidden = true
            return
        }
        let visible = scrollView.documentVisibleRect
        let document = textView.bounds
        if isVerticalWriting {
            scrollArrow0View?.isHidden = visible.maxX >= document.maxX - 1
            scrollArrow1View?.isHidden = visible.minX <= document.minX + 1
        } else {
            scrollArrow0View?.isHidden = visible.minY <= document.minY + 1
            scrollArrow1View?.isHidden = visible.maxY >= document.maxY - 1
        }
    }

    private func scrollText(_ direction: ScrollArrowDirection) {
        var origin = scrollView.documentVisibleRect.origin
        if isVerticalWriting {
            let distance = max(1, scrollView.contentSize.width * 0.85)
            origin.x += direction == .previous ? distance : -distance
            origin.x = min(max(origin.x, textView.bounds.minX), max(textView.bounds.minX, textView.bounds.maxX - scrollView.contentSize.width))
        } else {
            let distance = max(1, scrollView.contentSize.height * 0.85)
            origin.y += direction == .previous ? -distance : distance
            origin.y = min(max(origin.y, textView.bounds.minY), max(textView.bounds.minY, textView.bounds.maxY - scrollView.contentSize.height))
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateScrollArrowVisibility()
    }
}

private final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?

    convenience init(image: NSImage) {
        self.init(frame: .zero)
        self.image = image
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class ObservingClipView: NSClipView {
    var onBoundsChange: (() -> Void)?

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        onBoundsChange?()
    }
}

private final class AnimatedBalloonImageView: NSImageView {
    let imageSize: NSSize
    private let images: [NSImage]
    private let intervalNanoseconds: UInt64
    private var animationTask: Task<Void, Never>?
    private var imageIndex = 0

    init(images: [NSImage], intervalMilliseconds: Int) {
        self.images = images
        imageSize = images.first?.size ?? .zero
        intervalNanoseconds = UInt64(max(50, intervalMilliseconds)) * 1_000_000
        super.init(frame: .zero)
        image = images.first
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnimating(_ enabled: Bool) {
        animationTask?.cancel()
        animationTask = nil
        isHidden = !enabled
        guard enabled, images.count > 1 else { return }
        animationTask = Task { @MainActor [weak self, intervalNanoseconds] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled, let self else { return }
                imageIndex = (imageIndex + 1) % images.count
                image = images[imageIndex]
            }
        }
    }
}

func ghostDialogueFont(named name: String?, size: CGFloat) -> NSFont {
    if let names = name?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        for name in names {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
    }

    let systemFont = NSFont.systemFont(ofSize: size)
    guard let japaneseFont = NSFont(name: "Hiragino Sans", size: size) else {
        return systemFont
    }
    let descriptor = systemFont.fontDescriptor.addingAttributes([
        .cascadeList: [japaneseFont.fontDescriptor]
    ])
    return NSFont(descriptor: descriptor, size: size) ?? systemFont
}

private func decoratedFont(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
    var traits = base.fontDescriptor.symbolicTraits
    if bold {
        traits.insert(.bold)
    }
    if italic {
        traits.insert(.italic)
    }
    let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
    return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
}

private final class InteractiveTextView: NSTextView, NSTextViewDelegate {
    var linkTargets: [String: BalloonTextLink] = [:]
    var appearanceByKind: [BalloonTextLink.Kind: (normal: BalloonLinkAppearance, hovered: BalloonLinkAppearance)] = [:]
    var anchorVisitedAppearance: BalloonLinkAppearance?
    var visitedAnchorIDs: Set<String> = []
    var defaultTextColor = NSColor.textColor
    var onBackgroundClick: (() -> Void)?
    var onBackgroundDoubleClick: (() -> Void)?
    var onLinkClick: ((String, [String]) -> Void)?
    var onLinkActivate: ((BalloonTextLink, String) -> Void)?
    var onLinkEnter: ((BalloonTextLink?, String?) -> Void)?
    var onLinkHover: ((BalloonTextLink, String) -> Void)?
    var presentationFrame: (() -> NSRect?)?
    var setPresentationOrigin: ((NSPoint) -> Void)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    private var hoveredLinkToken: String?
    private var mouseTrackingArea: NSTrackingArea?
    private var hoverWorkItem: DispatchWorkItem?

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
        hoverWorkItem?.cancel()
        hoveredLinkToken = token
        refreshLinkAppearance()
        guard let token, let link = linkTargets[token] else {
            onLinkEnter?(nil, nil)
            return
        }
        let label = linkLabel(for: token)
        onLinkEnter?(link, label)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, hoveredLinkToken == token else { return }
            onLinkHover?(link, label)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredLinkToken != nil else { return }
        hoverWorkItem?.cancel()
        hoveredLinkToken = nil
        refreshLinkAppearance()
        onLinkEnter?(nil, nil)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = presentationFrame?()?.origin ?? window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartMouseLocation, let dragStartWindowOrigin else { return }
        let location = NSEvent.mouseLocation
        let delta = NSPoint(
            x: location.x - dragStartMouseLocation.x,
            y: location.y - dragStartMouseLocation.y
        )
        didDrag = didDrag || abs(delta.x) > 2 || abs(delta.y) > 2
        let origin = NSPoint(x: dragStartWindowOrigin.x + delta.x, y: dragStartWindowOrigin.y + delta.y)
        if let setPresentationOrigin {
            setPresentationOrigin(origin)
        } else {
            window?.setFrameOrigin(origin)
        }
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
        if event.clickCount >= 2 {
            onBackgroundDoubleClick?()
        } else {
            onBackgroundClick?()
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let token = link as? String else { return false }
        activateLink(token)
        return true
    }

    private func activateLink(_ token: String) {
        if let target = linkTargets[token] {
            let label = linkLabel(for: token)
            onLinkActivate?(target, label)
            onLinkClick?(target.id, target.arguments)
        } else {
            onLinkClick?(token, [])
        }
    }

    private func linkLabel(for token: String) -> String {
        guard let link = linkTargets[token] else { return "" }
        return textStorage.map { ($0.string as NSString).substring(with: link.range) } ?? ""
    }

    func refreshLinkAppearance() {
        guard let textStorage else { return }
        for (token, link) in linkTargets where NSMaxRange(link.range) <= textStorage.length {
            textStorage.removeAttribute(.backgroundColor, range: link.range)
            textStorage.removeAttribute(.underlineStyle, range: link.range)
            textStorage.removeAttribute(.underlineColor, range: link.range)
            let pair = appearanceByKind[link.kind]
            let baseAppearance = if token == hoveredLinkToken {
                pair?.hovered
            } else if link.kind == .anchor, visitedAnchorIDs.contains(link.id) {
                anchorVisitedAppearance ?? pair?.normal
            } else {
                pair?.normal
            }
            let appearanceOverride = if token == hoveredLinkToken {
                link.hoveredAppearance
            } else if link.kind == .anchor, visitedAnchorIDs.contains(link.id) {
                link.visitedAppearance ?? link.normalAppearance
            } else {
                link.normalAppearance
            }
            let appearance = if let baseAppearance, let appearanceOverride {
                appearanceOverride.applying(to: baseAppearance)
            } else {
                baseAppearance
            }
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
    if glyphBounds.contains(containerPoint), characterIndex < (textView.textStorage?.length ?? 0),
       let token = textView.textStorage?.attribute(.link, at: characterIndex, effectiveRange: nil) as? String
    {
        return token
    }

    guard let textStorage = textView.textStorage else { return nil }
    var index = 0
    while index < textStorage.length {
        var range = NSRange()
        let value = textStorage.attribute(.link, at: index, effectiveRange: &range)
        if let token = value as? String {
            let linkGlyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let linkBounds = layoutManager.boundingRect(forGlyphRange: linkGlyphRange, in: textContainer)
                .insetBy(dx: -4, dy: -2)
            if linkBounds.contains(containerPoint) {
                return token
            }
        }
        index = max(index + 1, NSMaxRange(range))
    }
    return nil
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

import AppKit
import UtataneCore
import UtataneShell

@MainActor
public final class SurfaceWindowController {
    private var characters: [Int: CharacterSurfaceController] = [:]
    private var shell: ShellDefinition?
    private let positionStore: WindowPositionStore
    private var defaultSurfaceIDs: [Int: Int] = [:]
    private var presentationHidden = false
    private var displayScale: CGFloat = 1
    private var locksToDesktopBottom = true
    private var keepsOnScreen = true

    public var onMouseClick: (@MainActor (Int, String?) -> Void)?
    public var onMouseEvent: (@MainActor (GhostMouseEvent) -> Void)?
    public var onNarDrop: (@MainActor (Int, [URL]) -> Void)?
    public var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?

    public init(positionStore: WindowPositionStore = WindowPositionStore()) {
        self.positionStore = positionStore
    }

    public func setPositionContentID(_ contentID: URL?) {
        positionStore.setContentID(contentID)
    }

    public func setPresentationHidden(_ hidden: Bool) {
        presentationHidden = hidden
        for character in characters.values {
            character.setPresentationHidden(hidden)
        }
    }

    public func setDisplayScale(_ scale: Double) {
        displayScale = CGFloat(min(max(scale, 0.5), 2))
        for character in characters.values {
            character.setDisplayScale(displayScale)
        }
    }

    public func setPlacement(locksToDesktopBottom: Bool, keepsOnScreen: Bool) {
        self.locksToDesktopBottom = locksToDesktopBottom
        self.keepsOnScreen = keepsOnScreen
        for character in characters.values {
            character.setPlacement(
                locksToDesktopBottom: locksToDesktopBottom,
                keepsOnScreen: keepsOnScreen
            )
        }
    }

    public var windowFrame: NSRect? {
        windowFrame(for: 0)
    }

    public var visibleScopes: [Int] {
        characters.compactMap { scope, character in
            character.visibleWindowFrame == nil ? nil : scope
        }.sorted()
    }

    public func windowFrame(for scope: Int) -> NSRect? {
        characters[scope]?.windowFrame
    }

    public func surfaceID(for scope: Int) -> Int? {
        characters[scope]?.currentSurfaceID
    }

    public func show(shell: ShellDefinition, surfaceID: Int) throws {
        try show(shell: shell, scope: 0, surfaceID: surfaceID)
    }

    public func show(shell: ShellDefinition, defaultSurfaceIDs: [Int: Int]) throws {
        hideAll()
        self.shell = shell
        self.defaultSurfaceIDs = defaultSurfaceIDs

        for (scope, surfaceID) in defaultSurfaceIDs.sorted(by: { $0.key < $1.key }) {
            do {
                let character = characterController(for: scope)
                try character.show(shell: shell, surfaceID: surfaceID)
                character.setPresentationHidden(presentationHidden)
                placeInitialWindow(for: scope)
            } catch where scope != 0 {
                continue
            }
        }
    }

    public func show(shell: ShellDefinition, scope: Int, surfaceID: Int) throws {
        self.shell = shell
        defaultSurfaceIDs[scope] = defaultSurfaceIDs[scope] ?? surfaceID
        let character = characterController(for: scope)
        try character.show(shell: shell, surfaceID: surfaceID)
        placeInitialWindow(for: scope)
    }

    public func playAnimation(
        id: Int,
        scope: Int = 0,
        minimumFrameDurationMilliseconds: Int = 0
    ) {
        characters[scope]?.playAnimation(
            id: id,
            minimumFrameDurationMilliseconds: minimumFrameDurationMilliseconds
        )
    }

    public func changeSurface(scope: Int = 0, to surfaceID: Int) throws {
        if let character = characters[scope] {
            try character.changeSurface(to: surfaceID)
            return
        }

        guard surfaceID >= 0, let shell else { return }
        let character = characterController(for: scope)
        try character.show(shell: shell, surfaceID: surfaceID)
        placeInitialWindow(for: scope)
    }

    public func changeSurface(scope: Int = 0, named identifier: String) throws {
        guard let surfaceID = shell?.resolveSurface(identifier, scope: scope)
            ?? defaultSurfaceIDs[scope]
        else { return }
        try changeSurface(scope: scope, to: surfaceID)
    }

    public func hideAll() {
        for character in characters.values {
            character.hide()
        }
    }

    public func resetToDefaultSurfaces() {
        for (scope, surfaceID) in defaultSurfaceIDs {
            try? characters[scope]?.changeSurface(to: surfaceID)
        }
    }

    private func characterController(for scope: Int) -> CharacterSurfaceController {
        if let character = characters[scope] {
            return character
        }

        let character = CharacterSurfaceController(
            scope: scope,
            positionStore: positionStore,
            displayScale: displayScale,
            locksToDesktopBottom: locksToDesktopBottom,
            keepsOnScreen: keepsOnScreen
        )
        character.onMouseClick = { [weak self] region in
            self?.onMouseClick?(scope, region)
        }
        character.onMouseEvent = { [weak self] event in
            self?.onMouseEvent?(event)
        }
        character.onNarDrop = { [weak self] urls in
            self?.onNarDrop?(scope, urls)
        }
        character.contextMenuItems = { [weak self] in
            self?.contextMenuItems?() ?? []
        }
        characters[scope] = character
        return character
    }

    private func placeInitialWindow(for scope: Int) {
        guard let character = characters[scope],
              let frame = character.windowFrame
        else {
            characters[scope]?.center()
            return
        }

        let margin: CGFloat = 40
        let spacing: CGFloat = 24
        if let restoredOrigin = positionStore.restoredOrigin(
            for: .surface,
            scope: scope,
            windowSize: frame.size,
            constrainsToVisibleFrame: keepsOnScreen
        ) {
            character.setOrigin(restoredOrigin)
            return
        }
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            if let previousFrame = nearestVisibleFrame(before: scope) {
                character.setOrigin(NSPoint(
                    x: previousFrame.minX - frame.width - spacing,
                    y: previousFrame.minY
                ))
            } else {
                character.center()
            }
            return
        }
        let x: CGFloat = if scope == 0 {
            visibleFrame.maxX - frame.width - margin
        } else if let previousFrame = nearestVisibleFrame(before: scope) {
            previousFrame.minX - frame.width - spacing
        } else {
            visibleFrame.maxX - frame.width - margin
        }

        character.setOrigin(
            NSPoint(
                x: max(visibleFrame.minX, x),
                y: visibleFrame.minY
            )
        )
    }

    private func nearestVisibleFrame(before scope: Int) -> NSRect? {
        stride(from: scope - 1, through: 0, by: -1)
            .compactMap { characters[$0]?.visibleWindowFrame }
            .first
    }
}

@MainActor
private final class CharacterSurfaceController {
    private let scope: Int
    private let positionStore: WindowPositionStore
    private let imageLoader = SurfaceImageLoader()
    private let shellLoader = ShellLoader()
    private var window: NSWindow?
    private weak var imageView: SurfaceImageView?
    private var shell: ShellDefinition?
    private var baseSurfaceID: Int?
    private var baseImage: NSImage?
    private var animationTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var isAnimating = false
    private var displayScale: CGFloat
    private var locksToDesktopBottom: Bool
    private var keepsOnScreen: Bool

    var onMouseClick: (@MainActor (String?) -> Void)?
    var onMouseEvent: (@MainActor (GhostMouseEvent) -> Void)?
    var onNarDrop: (@MainActor ([URL]) -> Void)?
    var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?

    init(
        scope: Int,
        positionStore: WindowPositionStore,
        displayScale: CGFloat,
        locksToDesktopBottom: Bool,
        keepsOnScreen: Bool
    ) {
        self.scope = scope
        self.positionStore = positionStore
        self.displayScale = displayScale
        self.locksToDesktopBottom = locksToDesktopBottom
        self.keepsOnScreen = keepsOnScreen
    }

    var windowFrame: NSRect? {
        window?.frame
    }

    var visibleWindowFrame: NSRect? {
        guard window?.isVisible == true else { return nil }
        return window?.frame
    }

    var currentSurfaceID: Int? {
        baseSurfaceID
    }

    func show(shell: ShellDefinition, surfaceID: Int) throws {
        animationTask?.cancel()
        schedulerTask?.cancel()

        let rendered = try render(surfaceID: surfaceID, shell: shell)
        let window = window ?? makeWindow()
        window.contentView = rendered.view
        window.setContentSize(displaySize(for: rendered.image))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        imageView = rendered.view
        self.shell = shell
        baseSurfaceID = surfaceID
        baseImage = rendered.image
        scheduleAutomaticAnimations()
    }

    func playAnimation(id: Int, minimumFrameDurationMilliseconds: Int = 0) {
        guard let animation = currentSurfaceDefinition?.animations.first(where: { $0.id == id }) else {
            return
        }
        window?.makeKeyAndOrderFront(nil)
        animationTask?.cancel()
        animationTask = Task { [weak self] in
            await self?.run(
                animation,
                minimumFrameDurationMilliseconds: minimumFrameDurationMilliseconds
            )
        }
    }

    func changeSurface(to surfaceID: Int) throws {
        guard let shell, let window else { return }
        animationTask?.cancel()
        schedulerTask?.cancel()

        if surfaceID < 0 {
            window.orderOut(nil)
            return
        }

        let origin = window.frame.origin
        let rendered = try render(surfaceID: surfaceID, shell: shell)
        window.contentView = rendered.view
        window.setContentSize(displaySize(for: rendered.image))
        window.setFrameOrigin(origin)
        window.orderFront(nil)
        imageView = rendered.view
        baseSurfaceID = surfaceID
        baseImage = rendered.image
        scheduleAutomaticAnimations()
    }

    func hide() {
        animationTask?.cancel()
        schedulerTask?.cancel()
        window?.orderOut(nil)
    }

    func setPresentationHidden(_ hidden: Bool) {
        window?.alphaValue = hidden ? 0 : 1
    }

    func setDisplayScale(_ scale: CGFloat) {
        guard displayScale != scale else { return }
        displayScale = scale
        guard let shell, let baseSurfaceID, let window else { return }
        let origin = window.frame.origin
        guard let rendered = try? render(surfaceID: baseSurfaceID, shell: shell) else { return }
        window.contentView = rendered.view
        window.setContentSize(displaySize(for: rendered.image))
        window.setFrameOrigin(origin)
        imageView = rendered.view
        baseImage = rendered.image
        scheduleAutomaticAnimations()
    }

    func setPlacement(locksToDesktopBottom: Bool, keepsOnScreen: Bool) {
        self.locksToDesktopBottom = locksToDesktopBottom
        self.keepsOnScreen = keepsOnScreen
        imageView?.locksVerticalMovement = locksToDesktopBottom
        (window as? FloatingContentWindow)?.setPlacementPolicy(.init(
            locksToDesktopBottom: locksToDesktopBottom,
            keepsOnScreen: keepsOnScreen
        ))
    }

    private func displaySize(for image: NSImage) -> NSSize {
        NSSize(
            width: image.size.width * displayScale,
            height: image.size.height * displayScale
        )
    }

    func center() {
        window?.center()
    }

    func setOrigin(_ origin: NSPoint) {
        window?.setFrameOrigin(origin)
    }

    private func render(
        surfaceID: Int,
        shell: ShellDefinition,
        excludingInitialAnimations excludedAnimationIDs: Set<Int> = []
    ) throws -> (image: NSImage, view: SurfaceImageView) {
        let definition = shell.surfaces[surfaceID]
        let image: NSImage
        do {
            if let elements = definition?.elements, !elements.isEmpty {
                image = try render(elements: elements, shell: shell)
            } else {
                let surface = try shellLoader.loadSurface(id: surfaceID, from: shell.directory)
                image = try imageLoader.load(surface, usesSelfAlpha: shell.usesSelfAlpha)
            }
        } catch let error as ShellError {
            guard case .missingSurface = error,
                  let elements = definition?.elements,
                  !elements.isEmpty
            else { throw error }
            image = try render(elements: elements, shell: shell)
        }
        let boundImage = try applyInitialAnimations(
            to: image,
            definition: definition,
            shell: shell,
            excludedAnimationIDs: excludedAnimationIDs
        )
        let scaledSize = NSSize(
            width: boundImage.size.width * displayScale,
            height: boundImage.size.height * displayScale
        )
        let imageView = SurfaceImageView(frame: NSRect(origin: .zero, size: scaledSize))
        imageView.image = boundImage
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.coordinateScale = displayScale
        imageView.locksVerticalMovement = locksToDesktopBottom
        imageView.collisions = definition?.collisions ?? []
        imageView.onMouseClick = { [weak self] region in
            self?.onMouseClick?(region)
        }
        imageView.onMouseEvent = { [weak self] kind, region, x, y, button in
            guard let self else { return }
            onMouseEvent?(
                GhostMouseEvent(
                    kind: kind,
                    scope: scope,
                    region: region,
                    x: x,
                    y: y,
                    button: button
                )
            )
        }
        imageView.contextMenuItems = { [weak self] in
            self?.contextMenuItems?() ?? []
        }
        imageView.onNarDrop = { [weak self] urls in
            self?.onNarDrop?(urls)
        }
        return (boundImage, imageView)
    }

    private func render(elements: [SurfaceElement], shell: ShellDefinition) throws -> NSImage {
        guard let first = elements.first else {
            throw ShellError.missingSurface(id: -1, directory: shell.directory)
        }
        var result = try imageLoader.load(
            shellLoader.loadElement(filename: first.filename, from: shell.directory),
            usesSelfAlpha: shell.usesSelfAlpha
        )
        for element in elements.dropFirst() where element.method.lowercased() == "overlay" {
            let overlay = try imageLoader.load(
                shellLoader.loadElement(filename: element.filename, from: shell.directory),
                usesSelfAlpha: shell.usesSelfAlpha
            )
            result = imageLoader.composite(
                base: result,
                overlay: overlay,
                x: element.x,
                y: element.y
            )
        }
        return result
    }

    private func applyInitialAnimations(
        to base: NSImage,
        definition: SurfaceDefinition?,
        shell: ShellDefinition,
        visited: Set<Int> = [],
        excludedAnimationIDs: Set<Int> = []
    ) throws -> NSImage {
        guard let definition else { return base }
        let enabled = shell.defaultBindGroups[scope] ?? []
        var result = base
        for animation in definition.animations.sorted(by: { $0.id < $1.id }) {
            guard !excludedAnimationIDs.contains(animation.id) else { continue }
            let interval = animation.interval?.lowercased() ?? ""
            let isBound = interval.contains("bind")
            let isInitial = interval.contains("runonce") && !isBound
            guard isInitial || (isBound && enabled.contains(animation.id)) else { continue }
            for pattern in animation.patterns.sorted(by: { $0.order < $1.order })
                where pattern.waitMilliseconds == 0
                && pattern.surfaceID >= 0
                && pattern.method.lowercased() == "overlay"
            {
                let overlay = try renderLayer(
                    surfaceID: pattern.surfaceID,
                    shell: shell,
                    visited: visited
                )
                result = imageLoader.composite(
                    base: result,
                    overlay: overlay,
                    x: pattern.x,
                    y: pattern.y
                )
            }
        }
        return result
    }

    private func renderLayer(surfaceID: Int, shell: ShellDefinition, visited: Set<Int>) throws -> NSImage {
        guard !visited.contains(surfaceID) else {
            throw ShellError.missingSurface(id: surfaceID, directory: shell.directory)
        }
        if let asset = try? shellLoader.loadSurface(id: surfaceID, from: shell.directory) {
            return try imageLoader.load(asset, usesSelfAlpha: shell.usesSelfAlpha)
        }
        guard let definition = shell.surfaces[surfaceID], !definition.elements.isEmpty else {
            throw ShellError.missingSurface(id: surfaceID, directory: shell.directory)
        }
        let base = try render(elements: definition.elements, shell: shell)
        return try applyInitialAnimations(
            to: base,
            definition: definition,
            shell: shell,
            visited: visited.union([surfaceID])
        )
    }

    private func makeWindow() -> NSWindow {
        let window = FloatingContentWindow(
            title: "Ghost Surface \(scope)",
            placementPolicy: .init(
                locksToDesktopBottom: locksToDesktopBottom,
                keepsOnScreen: keepsOnScreen
            )
        ) { [positionStore, scope] origin in
            positionStore.save(origin, for: .surface, scope: scope)
        }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private var currentSurfaceDefinition: SurfaceDefinition? {
        guard let baseSurfaceID else { return nil }
        return shell?.surfaces[baseSurfaceID]
    }

    private func scheduleAutomaticAnimations() {
        let enabled = shell?.defaultBindGroups[scope] ?? []
        let animations = currentSurfaceDefinition?.animations.filter { animation in
            let interval = animation.interval?.lowercased() ?? ""
            let components = Set(interval.split(separator: "+").map(String.init))
            guard components.contains("sometimes") || components.contains("rarely") else {
                return false
            }
            guard components.contains("bind") else { return true }
            // SERIKO shells commonly pair a default static group (100) with
            // its automatic blink group (101).
            return enabled.contains(animation.id) || enabled.contains(animation.id - 1)
        } ?? []
        guard !animations.isEmpty else { return }

        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let animation = animations.randomElement() else { return }
                let isRare = animation.interval?.lowercased().split(separator: "+").contains("rarely") == true
                do {
                    try await Task.sleep(
                        for: .seconds(Int.random(in: isRare ? 7 ... 14 : 4 ... 8))
                    )
                } catch {
                    return
                }
                guard let self else { return }
                await run(animation)
            }
        }
    }

    private func run(
        _ animation: SurfaceAnimation,
        minimumFrameDurationMilliseconds: Int = 0
    ) async {
        guard !isAnimating,
              let shell,
              let baseSurfaceID,
              let baseImage,
              let imageView
        else { return }
        isAnimating = true
        defer {
            imageView.image = baseImage
            isAnimating = false
        }

        let stoppedAnimationIDs = Set(animation.patterns.compactMap { pattern in
            pattern.method.lowercased() == "stop" && pattern.surfaceID >= 0
                ? pattern.surfaceID
                : nil
        })
        let animationBase = (try? render(
            surfaceID: baseSurfaceID,
            shell: shell,
            excludingInitialAnimations: stoppedAnimationIDs
        ).image) ?? baseImage

        for pattern in animation.patterns {
            guard !Task.isCancelled else { return }

            if pattern.surfaceID < 0 {
                imageView.image = animationBase
            } else if pattern.method.lowercased() == "overlay" {
                do {
                    let overlay = try renderLayer(
                        surfaceID: pattern.surfaceID,
                        shell: shell,
                        visited: []
                    )
                    imageView.image = imageLoader.composite(
                        base: animationBase,
                        overlay: overlay,
                        x: pattern.x,
                        y: pattern.y
                    )
                } catch {
                    continue
                }
            }

            do {
                try await Task.sleep(
                    for: .milliseconds(max(pattern.waitMilliseconds, minimumFrameDurationMilliseconds))
                )
            } catch {
                return
            }
        }
    }
}

private final class SurfaceImageView: NSImageView {
    var collisions: [SurfaceCollision] = []
    var coordinateScale: CGFloat = 1
    var onMouseClick: ((String?) -> Void)?
    var onMouseEvent: ((GhostMouseEvent.Kind, String?, Int, Int, Int) -> Void)?
    var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?
    var onNarDrop: (([URL]) -> Void)?
    var locksVerticalMovement = true
    private var hoveredRegion: String?
    private var lastStrokePoint: NSPoint?
    private var lastStrokeRegion: String?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, let window else {
            super.mouseDown(with: event)
            return
        }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startMouseLocation = dragStartMouseLocation,
              let startWindowOrigin = dragStartWindowOrigin
        else {
            super.mouseDragged(with: event)
            return
        }
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - startMouseLocation.x
        let deltaY = currentMouseLocation.y - startMouseLocation.y
        didDrag = didDrag || hypot(deltaX, deltaY) >= 2
        window.setFrameOrigin(NSPoint(
            x: startWindowOrigin.x + deltaX,
            y: locksVerticalMovement ? startWindowOrigin.y : startWindowOrigin.y + deltaY
        ))
    }

    override func updateTrackingAreas() {
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        ))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(for: event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRegion = nil
        lastStrokePoint = nil
        lastStrokeRegion = nil
        NSCursor.arrow.set()
        super.mouseExited(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
        sendStrokeEventIfNeeded(event)
        super.mouseMoved(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragStartMouseLocation != nil && didDrag
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        guard !wasDragging else { return }
        let hit = hitTest(event)
        if event.clickCount >= 2 {
            onMouseEvent?(.doubleClick, hit.region, hit.x, hit.y, buttonNumber(event))
        } else {
            onMouseClick?(hit.region)
            onMouseEvent?(.click, hit.region, hit.x, hit.y, buttonNumber(event))
        }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Int(event.scrollingDeltaY.rounded())
        guard delta != 0 else { return }
        sendMouseEvent(.wheel(delta: delta), event: event)
        super.scrollWheel(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        narURLs(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !narURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = narURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onNarDrop?(urls)
        return true
    }

    private func narURLs(from draggingInfo: any NSDraggingInfo) -> [URL] {
        guard let items = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        else { return [] }
        return SurfaceDropPayload.narURLs(from: items)
    }

    private func sendMouseEvent(_ kind: GhostMouseEvent.Kind, event: NSEvent) {
        let hit = hitTest(event)
        onMouseEvent?(kind, hit.region, hit.x, hit.y, buttonNumber(event))
    }

    private func sendStrokeEventIfNeeded(_ event: NSEvent) {
        let hit = hitTest(event)
        guard let region = hit.region else {
            lastStrokePoint = nil
            lastStrokeRegion = nil
            return
        }
        let point = NSPoint(x: hit.x, y: hit.y)
        guard lastStrokeRegion == region, let previous = lastStrokePoint else {
            lastStrokeRegion = region
            lastStrokePoint = point
            return
        }
        let distance = hypot(point.x - previous.x, point.y - previous.y)
        guard distance >= 4 else { return }
        lastStrokePoint = point
        onMouseEvent?(.move, region, hit.x, hit.y, buttonNumber(event))
    }

    private func updateCursor(for event: NSEvent) {
        let region = hitTest(event).region
        hoveredRegion = region
        SurfaceCursorStyle(region: region).cursor.set()
    }

    private func hitTest(_ event: NSEvent) -> (region: String?, x: Int, y: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let surfaceX = Int(point.x / coordinateScale)
        let surfaceY = Int((bounds.height - point.y) / coordinateScale)
        let region = collisions.first { $0.contains(x: surfaceX, y: surfaceY) }?.name
        return (region, surfaceX, surfaceY)
    }

    private func buttonNumber(_ event: NSEvent) -> Int {
        switch event.buttonNumber {
        case 1: 1
        case 2: 2
        default: 0
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let contextMenuItems else { return nil }
        let items = contextMenuItems()
        return items.isEmpty ? nil : SurfaceContextMenuBuilder().build(from: items)
    }
}

enum SurfaceDropPayload {
    static func narURLs(from urls: [URL]) -> [URL] {
        urls.filter { $0.pathExtension.caseInsensitiveCompare("nar") == .orderedSame }
    }
}

enum SurfaceCursorStyle: Equatable {
    case arrow
    case pointingHand
    case openHand

    init(region: String?) {
        guard let region, !region.isEmpty else {
            self = .arrow
            return
        }
        let normalized = region
            .lowercased()
            .filter { !$0.isNumber && $0 != "_" && $0 != "-" }
        let pettableRegions: Set = [
            "bust", "ear", "face", "hair", "hand", "head", "leg",
            "ponytail", "ribbon", "skirt", "tail"
        ]
        self = pettableRegions.contains(normalized) ? .openHand : .pointingHand
    }

    var cursor: NSCursor {
        switch self {
        case .arrow:
            .arrow
        case .pointingHand:
            .pointingHand
        case .openHand:
            .openHand
        }
    }
}

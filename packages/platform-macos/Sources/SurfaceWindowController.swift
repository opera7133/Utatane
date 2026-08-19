import AppKit
import UtataneCore
import UtataneShell

@MainActor
public final class SurfaceWindowController {
    private var characters: [Int: CharacterSurfaceController] = [:]
    private var shell: ShellDefinition?
    private let positionStore: WindowPositionStore
    private var defaultSurfaceIDs: [Int: Int] = [:]

    public var onMouseClick: (@MainActor (Int, String?) -> Void)?
    public var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?

    public init(positionStore: WindowPositionStore = WindowPositionStore()) {
        self.positionStore = positionStore
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

        let character = CharacterSurfaceController(scope: scope, positionStore: positionStore)
        character.onMouseClick = { [weak self] region in
            self?.onMouseClick?(scope, region)
        }
        character.contextMenuItems = { [weak self] in
            self?.contextMenuItems?() ?? []
        }
        characters[scope] = character
        return character
    }

    private func placeInitialWindow(for scope: Int) {
        guard let visibleFrame = NSScreen.main?.visibleFrame,
              let character = characters[scope],
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
            windowSize: frame.size
        ) {
            character.setOrigin(restoredOrigin)
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

    var onMouseClick: (@MainActor (String?) -> Void)?
    var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?

    init(scope: Int, positionStore: WindowPositionStore) {
        self.scope = scope
        self.positionStore = positionStore
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
        window.setContentSize(rendered.image.size)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        imageView = rendered.view
        self.shell = shell
        baseSurfaceID = surfaceID
        baseImage = rendered.image
        scheduleSometimesAnimations()
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
        window.setContentSize(rendered.image.size)
        window.setFrameOrigin(origin)
        window.orderFront(nil)
        imageView = rendered.view
        baseSurfaceID = surfaceID
        baseImage = rendered.image
        scheduleSometimesAnimations()
    }

    func hide() {
        animationTask?.cancel()
        schedulerTask?.cancel()
        window?.orderOut(nil)
    }

    func center() {
        window?.center()
    }

    func setOrigin(_ origin: NSPoint) {
        window?.setFrameOrigin(origin)
    }

    private func render(surfaceID: Int, shell: ShellDefinition) throws -> (image: NSImage, view: SurfaceImageView) {
        let definition = shell.surfaces[surfaceID]
        let image: NSImage
        do {
            let surface = try shellLoader.loadSurface(id: surfaceID, from: shell.directory)
            image = try imageLoader.load(surface)
        } catch let error as ShellError {
            guard case .missingSurface = error,
                  let elements = definition?.elements,
                  !elements.isEmpty
            else { throw error }
            image = try render(elements: elements, shellDirectory: shell.directory)
        }
        let imageView = SurfaceImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        imageView.collisions = definition?.collisions ?? []
        imageView.onMouseClick = { [weak self] region in
            self?.onMouseClick?(region)
        }
        imageView.contextMenuItems = { [weak self] in
            self?.contextMenuItems?() ?? []
        }
        return (image, imageView)
    }

    private func render(elements: [SurfaceElement], shellDirectory: URL) throws -> NSImage {
        guard let first = elements.first else {
            throw ShellError.missingSurface(id: -1, directory: shellDirectory)
        }
        var result = try imageLoader.load(
            shellLoader.loadElement(filename: first.filename, from: shellDirectory)
        )
        for element in elements.dropFirst() where element.method.lowercased() == "overlay" {
            let overlay = try imageLoader.load(
                shellLoader.loadElement(filename: element.filename, from: shellDirectory)
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

    private func makeWindow() -> NSWindow {
        let window = FloatingContentWindow(
            title: "Ghost Surface \(scope)",
            placementPolicy: .desktopBottom
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

    private func scheduleSometimesAnimations() {
        let animations = currentSurfaceDefinition?.animations.filter {
            $0.interval?.lowercased() == "sometimes"
        } ?? []
        guard !animations.isEmpty else { return }

        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Int.random(in: 4 ... 8)))
                } catch {
                    return
                }
                guard let self, let animation = animations.randomElement() else { return }
                await run(animation)
            }
        }
    }

    private func run(
        _ animation: SurfaceAnimation,
        minimumFrameDurationMilliseconds: Int = 0
    ) async {
        guard !isAnimating, let shell, let baseImage, let imageView else { return }
        isAnimating = true
        defer {
            imageView.image = baseImage
            isAnimating = false
        }

        for pattern in animation.patterns {
            guard !Task.isCancelled else { return }

            if pattern.surfaceID < 0 {
                imageView.image = baseImage
            } else if pattern.method.lowercased() == "overlay" {
                do {
                    let asset = try shellLoader.loadSurface(
                        id: pattern.surfaceID,
                        from: shell.directory
                    )
                    let overlay = try imageLoader.load(asset)
                    imageView.image = imageLoader.composite(
                        base: baseImage,
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
    var onMouseClick: ((String?) -> Void)?
    var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let surfaceX = Int(point.x)
        let surfaceY = Int(bounds.height - point.y)
        let region = collisions.first { $0.contains(x: surfaceX, y: surfaceY) }?.name
        onMouseClick?(region)
        super.mouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let contextMenuItems else { return nil }
        let items = contextMenuItems()
        return items.isEmpty ? nil : SurfaceContextMenuBuilder().build(from: items)
    }
}

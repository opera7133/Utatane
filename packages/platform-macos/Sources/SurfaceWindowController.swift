import AppKit
import UtataneCore
import UtataneShell

func automaticSurfaceFitScale(imageSize: NSSize, visibleSize: NSSize?) -> CGFloat {
    guard let visibleSize, imageSize.width > 0, imageSize.height > 0,
          visibleSize.width > 0, visibleSize.height > 0
    else { return 1 }
    return min(
        1,
        visibleSize.width * 0.9 / imageSize.width,
        visibleSize.height * 0.75 / imageSize.height
    )
}

func automaticAnimationRandomDenominator(components: Set<String>, parameter: Int?) -> Int? {
    if components.contains("sometimes") {
        return 2
    }
    if components.contains("rarely") {
        return 4
    }
    if components.contains("random") {
        return max(parameter ?? 1, 1)
    }
    return nil
}

public struct DressupChange: Sendable, Equatable {
    public let scope: Int
    public let group: ShellBindGroup
    public let enabled: Bool
}

public struct DressupInfo: Sendable, Equatable {
    public let scope: Int
    public let group: ShellBindGroup
    public let enabled: Bool
    public let options: ShellBindOptions
}

public enum SurfaceDesktopAlignment: Sendable, Equatable {
    case top
    case bottom
    case left
    case right
    case free
    case defaultValue
}

public struct SERIKOInspectorSnapshot: Identifiable, Sendable, Equatable {
    public let scope: Int
    public let surfaceID: Int
    public let currentAnimationID: Int?
    public let persistentAnimationIDs: [Int]
    public let pausedAnimationIDs: [Int]
    public let animationOffsets: [Int: SurfacePoint]
    public let isAnimating: Bool
    public let isRepaintLocked: Bool
    public let isMovementLocked: Bool
    public let alpha: Double
    public let scaleX: Double
    public let scaleY: Double

    public var id: Int {
        scope
    }
}

@MainActor
public final class SurfaceWindowController {
    private var characters: [Int: CharacterSurfaceController] = [:]
    private var shell: ShellDefinition?
    private let positionStore: WindowPositionStore
    private var defaultSurfaceIDs: [Int: Int] = [:]
    private var enabledBindGroups: [Int: Set<Int>] = [:]
    private var presentationHidden = false
    private var startupPresentationHidden = false

    private var displayScale: CGFloat = 1
    private var automaticallyFitsLargeSurfaces = true
    private var locksToDesktopBottom = true
    private var keepsOnScreen = true
    private var stayOnTop = true
    private var stickyGroups: [Set<Int>] = []
    private var collisionMode = (enabled: false, showsNames: true)

    public var onMouseClick: (@MainActor (Int, String?) -> Void)?
    public var onMouseEvent: (@MainActor (GhostMouseEvent) -> Void)?
    public var onSurfaceChange: (@MainActor (Int, Int?, Int) -> Void)?
    public var onWindowMove: (@MainActor (Int, NSPoint) -> Void)?
    public var onNarDrop: (@MainActor (Int, [URL]) -> Void)?
    public var onFileDropping: (@MainActor (Int, [URL]) -> Void)?
    public var onFileDrop: (@MainActor (Int, [URL]) -> Void)?
    public var onURLDropping: (@MainActor (Int, URL) -> Void)?
    public var onURLDrop: (@MainActor (Int, URL) -> Void)?
    public var onTextDrop: (@MainActor (Int, String) -> Void)?
    public var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?
    public var onUserDressupChange: (@MainActor ([DressupChange]) -> Void)?

    public init(positionStore: WindowPositionStore = WindowPositionStore()) {
        self.positionStore = positionStore
    }

    public func setStayOnTop(_ stayOnTop: Bool) {
        self.stayOnTop = stayOnTop
        for character in characters.values {
            character.setStayOnTop(stayOnTop)
        }
    }

    public func setCollisionMode(_ enabled: Bool, showsNames: Bool = true) {
        collisionMode = (enabled, showsNames)
        for character in characters.values {
            character.setCollisionMode(enabled, showsNames: showsNames)
        }
    }

    public func setPositionContentID(_ contentID: URL?) {
        positionStore.setContentID(contentID)
    }

    public func setPresentationHidden(_ hidden: Bool) {
        presentationHidden = hidden
        for character in characters.values {
            character.setPresentationHidden(hidden || startupPresentationHidden)
        }
    }

    public func setStartupPresentationHidden(_ hidden: Bool) {
        startupPresentationHidden = hidden
        setPresentationHidden(presentationHidden)
    }

    public func setDisplayScale(_ scale: Double) {
        displayScale = CGFloat(min(max(scale, 0.5), 2))
        for character in characters.values {
            character.setDisplayScale(displayScale)
        }
    }

    public func setAutomaticallyFitsLargeSurfaces(_ enabled: Bool) {
        automaticallyFitsLargeSurfaces = enabled
        for character in characters.values {
            character.setAutomaticallyFitsLargeSurfaces(enabled)
        }
    }

    public func dressupContextMenuItem(title: String) -> SurfaceContextMenuItem? {
        let infos = dressupInfo()
        guard !infos.isEmpty else { return nil }
        let grouped = Dictionary(grouping: infos) { "\($0.scope)\u{0}\($0.group.category)" }
        let categories = grouped.values.sorted {
            ($0.first?.scope ?? 0, $0.first?.group.category ?? "")
                < ($1.first?.scope ?? 0, $1.first?.group.category ?? "")
        }.map { categoryInfos in
            let category = categoryInfos.first?.group.category ?? ""
            let items = categoryInfos.sorted { $0.group.id < $1.group.id }.map { info in
                let selectedCount = categoryInfos.count(where: \.enabled)
                return SurfaceContextMenuItem.action(
                    title: info.group.part,
                    isSelected: info.enabled,
                    isEnabled: !(info.enabled && info.options.mustSelect && selectedCount == 1),
                    handler: { [weak self] in
                        guard let self else { return }
                        let changes = changeBind(
                            scope: info.scope,
                            category: info.group.category,
                            part: info.group.part,
                            enabled: nil
                        )
                        if !changes.isEmpty {
                            onUserDressupChange?(changes)
                        }
                    }
                )
            }
            return SurfaceContextMenuItem.submenu(title: category, items: items)
        }
        return .submenu(title: title, items: categories)
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

    public func setDesktopAlignment(_ alignment: SurfaceDesktopAlignment, scope: Int) {
        characters[scope]?.setDesktopAlignment(alignment)
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

    public var serikoInspectorSnapshots: [SERIKOInspectorSnapshot] {
        characters.keys.sorted().compactMap { characters[$0]?.serikoInspectorSnapshot }
    }

    public var windowNumbers: [Int] {
        characters.keys.sorted().compactMap { characters[$0]?.windowNumber }
    }

    public func renderedImage(for scope: Int = 0) -> NSImage? {
        characters[scope]?.renderedImage
    }

    public func balloonOffset(for scope: Int) -> NSPoint {
        characters[scope]?.balloonOffset ?? .zero
    }

    public func show(shell: ShellDefinition, surfaceID: Int) throws {
        try show(shell: shell, scope: 0, surfaceID: surfaceID)
    }

    public struct ReloadPresentation {
        fileprivate let surfaces: [Int: Int]
        fileprivate let bindings: [Int: Set<Int>]
    }

    public func captureReloadPresentation() -> ReloadPresentation {
        ReloadPresentation(
            surfaces: characters.compactMapValues { $0.visibleWindowFrame == nil ? -1 : $0.currentSurfaceID },
            bindings: enabledBindGroups
        )
    }

    public func show(shell: ShellDefinition, defaultSurfaceIDs: [Int: Int], restoring presentation: ReloadPresentation? = nil) throws {
        hideAll()
        self.shell = shell
        self.defaultSurfaceIDs = defaultSurfaceIDs
        enabledBindGroups = presentation?.bindings ?? shell.defaultBindGroups

        let surfaces = defaultSurfaceIDs.merging(presentation?.surfaces ?? [:]) { _, restored in restored }
        for (scope, surfaceID) in surfaces.sorted(by: { $0.key < $1.key }) {
            do {
                let character = characterController(for: scope)
                character.setPresentationHidden(presentationHidden || startupPresentationHidden)
                character.setBindGroups(enabledBindGroups[scope] ?? [], redraw: false)
                try character.show(shell: shell, surfaceID: surfaceID < 0 ? (defaultSurfaceIDs[scope] ?? 0) : surfaceID)
                if surfaceID < 0 {
                    try character.changeSurface(to: surfaceID)
                }
                character.setPresentationHidden(presentationHidden || startupPresentationHidden)
                placeInitialWindow(for: scope)
            } catch where scope != 0 {
                continue
            }
        }
    }

    public func show(shell: ShellDefinition, scope: Int, surfaceID: Int) throws {
        self.shell = shell
        defaultSurfaceIDs[scope] = defaultSurfaceIDs[scope] ?? surfaceID
        enabledBindGroups[scope] = enabledBindGroups[scope] ?? shell.defaultBindGroups[scope] ?? []
        let character = characterController(for: scope)
        character.setBindGroups(enabledBindGroups[scope] ?? [], redraw: false)
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

    public func playAnimationAndWait(
        id: Int,
        scope: Int = 0,
        minimumFrameDurationMilliseconds: Int = 0
    ) async {
        await characters[scope]?.playAnimationAndWait(
            id: id,
            minimumFrameDurationMilliseconds: minimumFrameDurationMilliseconds
        )
    }

    public func playAnimation(identifier: String, scope: Int = 0) {
        characters[scope]?.playAnimation(identifier: identifier)
    }

    @discardableResult
    public func playTalkAnimation(scope: Int = 0) -> Bool {
        characters[scope]?.playTalkAnimation() ?? false
    }

    @discardableResult
    public func playIntervalAnimation(_ interval: String, scope: Int = 0) -> Bool {
        characters[scope]?.playIntervalAnimation(interval) ?? false
    }

    public func playIntervalAnimationAndWait(_ interval: String, scope: Int = 0) async {
        await characters[scope]?.playIntervalAnimationAndWait(interval)
    }

    public func playAnimationAndWait(identifier: String, scope: Int = 0) async {
        await characters[scope]?.playAnimationAndWait(identifier: identifier)
    }

    public func stopAnimation(id: Int, scope: Int = 0) {
        characters[scope]?.stopAnimation(id: id)
    }

    public func pauseAnimation(id: Int, scope: Int = 0) {
        characters[scope]?.pauseAnimation(id: id)
    }

    public func resumeAnimation(id: Int, scope: Int = 0) {
        characters[scope]?.resumeAnimation(id: id)
    }

    public func waitForAnimation(id: Int, scope: Int = 0) async {
        await characters[scope]?.waitForAnimation(id: id)
    }

    public func stopAnimation(identifier: String, scope: Int = 0) {
        characters[scope]?.stopAnimation(identifier: identifier)
    }

    public func pauseAnimation(identifier: String, scope: Int = 0) {
        characters[scope]?.pauseAnimation(identifier: identifier)
    }

    public func resumeAnimation(identifier: String, scope: Int = 0) {
        characters[scope]?.resumeAnimation(identifier: identifier)
    }

    public func waitForAnimation(identifier: String, scope: Int = 0) async {
        await characters[scope]?.waitForAnimation(identifier: identifier)
    }

    public func setAnimationOffset(identifier: String, x: Int, y: Int, scope: Int = 0) {
        characters[scope]?.setAnimationOffset(identifier: identifier, x: x, y: y)
    }

    public func setRepaintLocked(_ locked: Bool, scope: Int) {
        characters[scope]?.setRepaintLocked(locked)
    }

    public func setAlpha(
        _ alpha: Double?,
        scope: Int,
        durationMilliseconds: Int = 0
    ) async {
        await characters[scope]?.setAlpha(
            alpha.map { CGFloat($0) },
            durationMilliseconds: durationMilliseconds
        )
    }

    func alpha(for scope: Int) -> Double? {
        characters[scope].map { Double($0.surfaceAlpha) }
    }

    func dragPosition(for scope: Int) -> SurfaceDragPosition? {
        characters[scope]?.dragFeedback.position
    }

    public func setRuntimeScale(
        horizontal: Double,
        vertical: Double,
        scope: Int,
        durationMilliseconds: Int = 0
    ) async {
        await characters[scope]?.setRuntimeScale(
            horizontal: CGFloat(horizontal),
            vertical: CGFloat(vertical),
            durationMilliseconds: durationMilliseconds
        )
    }

    func runtimeScale(for scope: Int) -> NSSize? {
        characters[scope].map {
            NSSize(width: $0.runtimeScaleX, height: $0.runtimeScaleY)
        }
    }

    public func moveSurface(
        scope: Int = 0,
        x: Int?,
        y: Int?,
        time: Int,
        isAsync: Bool,
        options: [String] = []
    ) async {
        guard let character = characters[scope], let currentFrame = character.windowFrame else { return }
        let targetX = x.map { CGFloat($0) } ?? currentFrame.minX
        let targetY = y.map { CGFloat($0) } ?? currentFrame.minY
        let targetOrigin = NSPoint(x: targetX, y: targetY)

        if isAsync {
            Task { @MainActor in
                await character.moveOrigin(to: targetOrigin, durationMilliseconds: time)
            }
        } else {
            await character.moveOrigin(to: targetOrigin, durationMilliseconds: time)
        }
    }

    public func setFixedPosition(x: Int, y: Int, scope: Int) async {
        guard let character = characters[scope] else { return }
        character.setMovementLocked(true)
        await character.moveOrigin(
            to: NSPoint(x: CGFloat(x), y: CGFloat(y)),
            durationMilliseconds: 0
        )
    }

    public func resetFixedPositions() {
        for character in characters.values {
            character.setMovementLocked(false)
        }
    }

    func isMovementLocked(scope: Int) -> Bool {
        characters[scope]?.isMovementLocked ?? false
    }

    public func separateCharacters(scope: Int = 0) async {
        guard let currentFrame = characters[scope]?.windowFrame else { return }
        let otherScope = scope == 0 ? 1 : 0
        guard let otherFrame = characters[otherScope]?.windowFrame else { return }

        let moveDelta: CGFloat = currentFrame.midX < otherFrame.midX ? -60 : 60
        let targetOrigin = NSPoint(x: currentFrame.minX + moveDelta, y: currentFrame.minY)
        await characters[scope]?.moveOrigin(to: targetOrigin, durationMilliseconds: 300)
    }

    public func approachCharacters(scope: Int = 0) async {
        guard let currentFrame = characters[scope]?.windowFrame else { return }
        let otherScope = scope == 0 ? 1 : 0
        guard let otherFrame = characters[otherScope]?.windowFrame else { return }

        let targetX: CGFloat = if currentFrame.midX < otherFrame.midX {
            otherFrame.minX - currentFrame.width
        } else {
            otherFrame.maxX
        }
        let targetOrigin = NSPoint(x: targetX, y: currentFrame.minY)
        await characters[scope]?.moveOrigin(to: targetOrigin, durationMilliseconds: 300)
    }

    public func setStickyWindows(scopes: [Int]) {
        if scopes.isEmpty {
            stickyGroups = [Set(characters.keys)]
        } else {
            stickyGroups.append(Set(scopes))
        }
    }

    public func resetStickyWindows() {
        stickyGroups.removeAll()
    }

    private func handleWindowDragDelta(scope: Int, delta: NSPoint) {
        for group in stickyGroups where group.contains(scope) {
            for otherScope in group where otherScope != scope {
                characters[otherScope]?.moveBy(delta: delta)
            }
        }
    }

    public func setZOrder(_ order: [String]) {
        var previousWindowNumber: Int?
        for item in order {
            let scope: Int?
            if let directScope = Int(item) {
                scope = directScope
            } else if item.lowercased().hasPrefix("s") || item.lowercased().hasPrefix("surface") {
                let suffix = item.lowercased().replacingOccurrences(of: "surface", with: "").replacingOccurrences(of: "s", with: "")
                scope = Int(suffix)
            } else {
                scope = nil
            }
            if let scope, let character = characters[scope], let windowNumber = character.windowNumber {
                if let previousWindowNumber {
                    character.orderAbove(relativeTo: previousWindowNumber)
                }
                previousWindowNumber = windowNumber
            }
        }
    }

    public func resetZOrder() {
        for (_, character) in characters.sorted(by: { $0.key < $1.key }) {
            character.setStayOnTop(stayOnTop)
        }
    }

    public func unlockRepaint() {
        for character in characters.values {
            character.setRepaintLocked(false)
        }
    }

    public func changeSurface(scope: Int = 0, to surfaceID: Int) throws {
        let resolvedSurfaceID = shell?.resolveSurface(String(surfaceID), scope: scope) ?? surfaceID
        let previousSurfaceID = characters[scope]?.currentSurfaceID
        if let character = characters[scope] {
            try character.changeSurface(to: resolvedSurfaceID)
            if previousSurfaceID != resolvedSurfaceID {
                onSurfaceChange?(scope, previousSurfaceID, resolvedSurfaceID)
            }
            return
        }

        guard resolvedSurfaceID >= 0, let shell else { return }
        let character = characterController(for: scope)
        try character.show(shell: shell, surfaceID: resolvedSurfaceID)
        placeInitialWindow(for: scope)
        onSurfaceChange?(scope, previousSurfaceID, resolvedSurfaceID)
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

    public func resetContent() {
        hideAll()
        characters.removeAll()
        shell = nil
        defaultSurfaceIDs.removeAll()
        enabledBindGroups.removeAll()
        stickyGroups.removeAll()
    }

    public func resetToDefaultSurfaces() {
        for (scope, surfaceID) in defaultSurfaceIDs {
            try? characters[scope]?.changeSurface(to: surfaceID)
        }
    }

    public func restoreSurfaces() {
        for character in characters.values {
            character.restore()
            character.setPresentationHidden(presentationHidden || startupPresentationHidden)
        }
    }

    public func resetWindowPositions() {
        for scope in characters.keys.sorted() {
            positionStore.remove(for: .surface, scope: scope)
            placeInitialWindow(for: scope)
            positionStore.remove(for: .surface, scope: scope)
        }
    }

    @discardableResult
    public func changeBind(scope: Int, category: String, part: String, enabled: Bool?) -> [DressupChange] {
        guard let shell, let groups = shell.bindGroups[scope] else { return [] }
        let targets = groups.values.filter {
            $0.category == category && (part.isEmpty || $0.part == part)
        }.sorted { $0.id < $1.id }
        guard !targets.isEmpty else { return [] }

        let options = shell.bindOptions[scope]?[category] ?? ShellBindOptions()
        let categoryIDs = Set(groups.values.filter { $0.category == category }.map(\.id))
        var selected = enabledBindGroups[scope] ?? []
        let before = selected
        for target in targets {
            let shouldEnable = enabled ?? !selected.contains(target.id)
            if shouldEnable {
                if !options.multiple {
                    selected.subtract(categoryIDs)
                }
                selected.insert(target.id)
            } else {
                let remaining = selected.intersection(categoryIDs).subtracting([target.id])
                if !options.mustSelect || !remaining.isEmpty {
                    selected.remove(target.id)
                }
            }
        }

        enabledBindGroups[scope] = selected
        characters[scope]?.setBindGroups(selected, redraw: true)
        return categoryIDs.sorted().compactMap { id in
            guard before.contains(id) != selected.contains(id), let group = groups[id] else { return nil }
            return DressupChange(scope: scope, group: group, enabled: selected.contains(id))
        }
    }

    public func dressupInfo() -> [DressupInfo] {
        guard let shell else { return [] }
        return shell.bindGroups.flatMap { scope, groups in
            groups.values.map { group in
                DressupInfo(
                    scope: scope,
                    group: group,
                    enabled: enabledBindGroups[scope]?.contains(group.id) == true,
                    options: shell.bindOptions[scope]?[group.category] ?? ShellBindOptions()
                )
            }
        }.sorted { ($0.scope, $0.group.id) < ($1.scope, $1.group.id) }
    }

    private func characterController(for scope: Int) -> CharacterSurfaceController {
        if let character = characters[scope] {
            return character
        }

        let character = CharacterSurfaceController(
            scope: scope,
            positionStore: positionStore,
            displayScale: displayScale,
            automaticallyFitsLargeSurfaces: automaticallyFitsLargeSurfaces,
            locksToDesktopBottom: locksToDesktopBottom,
            keepsOnScreen: keepsOnScreen
        )
        character.setPresentationHidden(presentationHidden || startupPresentationHidden)
        character.onMouseClick = { [weak self] region in
            self?.onMouseClick?(scope, region)
        }
        character.onMouseEvent = { [weak self] event in
            self?.onMouseEvent?(event)
        }
        character.onNarDrop = { [weak self] urls in
            self?.onNarDrop?(scope, urls)
        }
        character.onFileDropping = { [weak self] urls in
            self?.onFileDropping?(scope, urls)
        }
        character.onFileDrop = { [weak self] urls in
            self?.onFileDrop?(scope, urls)
        }
        character.onURLDropping = { [weak self] url in self?.onURLDropping?(scope, url) }
        character.onURLDrop = { [weak self] url in self?.onURLDrop?(scope, url) }
        character.onTextDrop = { [weak self] value in self?.onTextDrop?(scope, value) }
        character.onWindowDragDelta = { [weak self] delta in
            self?.handleWindowDragDelta(scope: scope, delta: delta)
        }
        character.onWindowMove = { [weak self] delta in
            self?.onWindowMove?(scope, delta)
        }
        character.contextMenuItems = { [weak self] in
            self?.contextMenuItems?() ?? []
        }
        character.setStayOnTop(stayOnTop)
        character.setCollisionMode(collisionMode.enabled, showsNames: collisionMode.showsNames)
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
    private var surfaceBaseImage: NSImage?
    private var baseImage: NSImage?
    private var persistentAnimationLayers: [Int: PersistentAnimationLayer] = [:]
    private var enabledBindGroups: Set<Int> = []
    private var animationTask: Task<Void, Never>?
    private var currentAnimationID: Int?
    private var pausedAnimationIDs: Set<Int> = []
    private var animationOffsets: [Int: SurfacePoint] = [:]
    private var isRepaintLocked = false
    private var pendingAnimationImage: NSImage?
    private var schedulerTask: Task<Void, Never>?
    private var talkCharacterCount = 0
    private var isAnimating = false
    private var displayScale: CGFloat
    private var automaticallyFitsLargeSurfaces: Bool
    private var automaticFitScale: CGFloat = 1
    private(set) var surfaceAlpha: CGFloat = 1
    private(set) var runtimeScaleX: CGFloat = 1
    private(set) var runtimeScaleY: CGFloat = 1
    private var locksToDesktopBottom: Bool
    private var keepsOnScreen: Bool
    private var stayOnTop = true
    private var desktopAlignment: SurfaceDesktopAlignment = .defaultValue
    let dragFeedback = SurfaceDragFeedback()
    private var isDragging = false
    private(set) var isMovementLocked = false
    private var collisionMode = (enabled: false, showsNames: true)

    func setStayOnTop(_ stayOnTop: Bool) {
        self.stayOnTop = stayOnTop
        window?.level = stayOnTop ? .floating : .normal
    }

    func setCollisionMode(_ enabled: Bool, showsNames: Bool) {
        collisionMode = (enabled, showsNames)
        imageView?.setCollisionMode(enabled, showsNames: showsNames)
    }

    var onMouseClick: (@MainActor (String?) -> Void)?
    var onMouseEvent: (@MainActor (GhostMouseEvent) -> Void)?
    var onNarDrop: (@MainActor ([URL]) -> Void)?
    var onFileDropping: (@MainActor ([URL]) -> Void)?
    var onFileDrop: (@MainActor ([URL]) -> Void)?
    var onURLDropping: (@MainActor (URL) -> Void)?
    var onURLDrop: (@MainActor (URL) -> Void)?
    var onTextDrop: (@MainActor (String) -> Void)?
    var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?

    init(
        scope: Int,
        positionStore: WindowPositionStore,
        displayScale: CGFloat,
        automaticallyFitsLargeSurfaces: Bool,
        locksToDesktopBottom: Bool,
        keepsOnScreen: Bool
    ) {
        self.scope = scope
        self.positionStore = positionStore
        self.displayScale = displayScale
        self.automaticallyFitsLargeSurfaces = automaticallyFitsLargeSurfaces
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

    var renderedImage: NSImage? {
        imageView?.image
    }

    var serikoInspectorSnapshot: SERIKOInspectorSnapshot? {
        guard let baseSurfaceID else { return nil }
        return SERIKOInspectorSnapshot(
            scope: scope,
            surfaceID: baseSurfaceID,
            currentAnimationID: currentAnimationID,
            persistentAnimationIDs: persistentAnimationLayers.keys.sorted(),
            pausedAnimationIDs: pausedAnimationIDs.sorted(),
            animationOffsets: animationOffsets,
            isAnimating: isAnimating,
            isRepaintLocked: isRepaintLocked,
            isMovementLocked: isMovementLocked,
            alpha: Double(surfaceAlpha),
            scaleX: Double(runtimeScaleX),
            scaleY: Double(runtimeScaleY)
        )
    }

    func setMovementLocked(_ locked: Bool) {
        isMovementLocked = locked
        imageView?.isMovementLocked = locked
        (window as? FloatingContentWindow)?.setPlacementPolicy(.init(
            edge: locked ? nil : effectiveDesktopEdge,
            keepsOnScreen: keepsOnScreen
        ))
    }

    func show(shell: ShellDefinition, surfaceID: Int) throws {
        animationTask?.cancel()
        schedulerTask?.cancel()
        pausedAnimationIDs.removeAll()
        animationOffsets.removeAll()
        isRepaintLocked = false
        pendingAnimationImage = nil

        let rendered = try render(surfaceID: surfaceID, shell: shell)
        automaticFitScale = automaticallyFitsLargeSurfaces
            ? automaticSurfaceFitScale(imageSize: rendered.image.size, visibleSize: NSScreen.main?.visibleFrame.size)
            : 1
        imageView = rendered.view
        updateImageViewCoordinateScale()
        let window = window ?? makeWindow()
        window.contentView = rendered.view
        window.setContentSize(displaySize(for: rendered.image))
        window.alphaValue = presentationAlpha
        window.makeKeyAndOrderFront(nil)
        self.window = window
        imageView = rendered.view
        self.shell = shell
        baseSurfaceID = surfaceID
        surfaceBaseImage = rendered.image
        baseImage = rendered.image
        persistentAnimationLayers.removeAll()
        scheduleAutomaticAnimations()
    }

    func setBindGroups(_ groups: Set<Int>, redraw: Bool) {
        enabledBindGroups = groups
        schedulerTask?.cancel()
        guard redraw, let shell, let baseSurfaceID, let window,
              let rendered = try? render(surfaceID: baseSurfaceID, shell: shell)
        else { return }
        let origin = window.frame.origin
        window.contentView = rendered.view
        window.setContentSize(displaySize(for: rendered.image))
        window.setFrameOrigin(origin)
        imageView = rendered.view
        baseImage = rendered.image
        scheduleAutomaticAnimations()
    }

    func playAnimation(id: Int, minimumFrameDurationMilliseconds: Int = 0) {
        if applyInstantPersistentAnimation(id: id) {
            return
        }
        _ = startAnimation(
            id: id,
            minimumFrameDurationMilliseconds: minimumFrameDurationMilliseconds
        )
    }

    func playAnimation(identifier: String) {
        guard let id = animationID(for: identifier) else { return }
        playAnimation(id: id)
    }

    @discardableResult
    func playTalkAnimation() -> Bool {
        talkCharacterCount += 1
        guard animationTask == nil, !isAnimating else { return false }
        let enabled = shell.map { $0.effectiveBindGroups(scope: scope, enabled: enabledBindGroups) } ?? []
        let animations = currentSurfaceDefinition?.animations.filter { animation in
            let components = Set((animation.interval ?? "").lowercased().split(separator: "+").map(String.init))
            guard components.contains("talk") else { return false }
            guard talkCharacterCount.isMultiple(of: max(animation.intervalParameter ?? 1, 1)) else { return false }
            guard components.contains("bind") else { return true }
            return enabled.contains(animation.id) || enabled.contains(animation.id - 1)
        } ?? []
        guard let animation = animations.randomElement() else { return false }
        return startAnimation(id: animation.id, minimumFrameDurationMilliseconds: 0) != nil
    }

    @discardableResult
    func playIntervalAnimation(_ trigger: String) -> Bool {
        if trigger == "starttalk" {
            talkCharacterCount = 0
        }
        guard animationTask == nil, !isAnimating,
              let animation = animations(forInterval: trigger).randomElement()
        else { return false }
        return startAnimation(id: animation.id, minimumFrameDurationMilliseconds: 0) != nil
    }

    func playIntervalAnimationAndWait(_ trigger: String) async {
        guard let animation = animations(forInterval: trigger).randomElement() else { return }
        await playAnimationAndWait(id: animation.id)
    }

    private func animations(forInterval trigger: String) -> [SurfaceAnimation] {
        let enabled = shell.map { $0.effectiveBindGroups(scope: scope, enabled: enabledBindGroups) } ?? []
        return currentSurfaceDefinition?.animations.filter { animation in
            let components = Set((animation.interval ?? "").lowercased().split(separator: "+").map(String.init))
            guard components.contains(trigger) else { return false }
            guard components.contains("bind") else { return true }
            return enabled.contains(animation.id) || enabled.contains(animation.id - 1)
        } ?? []
    }

    func playAnimationAndWait(identifier: String) async {
        guard let id = animationID(for: identifier) else { return }
        await playAnimationAndWait(id: id)
    }

    func playAnimationAndWait(id: Int, minimumFrameDurationMilliseconds: Int = 0) async {
        animationTask?.cancel()
        await animationTask?.value
        let task = startAnimation(
            id: id,
            minimumFrameDurationMilliseconds: minimumFrameDurationMilliseconds
        )
        await task?.value
    }

    func stopAnimation(id: Int) {
        guard currentAnimationID == id else { return }
        animationTask?.cancel()
    }

    func pauseAnimation(id: Int) {
        guard currentAnimationID == id else { return }
        pausedAnimationIDs.insert(id)
    }

    func resumeAnimation(id: Int) {
        pausedAnimationIDs.remove(id)
    }

    func waitForAnimation(id: Int) async {
        guard currentAnimationID == id else { return }
        let task = animationTask
        await task?.value
    }

    func stopAnimation(identifier: String) {
        guard let id = animationID(for: identifier) else { return }
        stopAnimation(id: id)
    }

    func pauseAnimation(identifier: String) {
        guard let id = animationID(for: identifier) else { return }
        pauseAnimation(id: id)
    }

    func resumeAnimation(identifier: String) {
        guard let id = animationID(for: identifier) else { return }
        resumeAnimation(id: id)
    }

    func waitForAnimation(identifier: String) async {
        guard let id = animationID(for: identifier) else { return }
        await waitForAnimation(id: id)
    }

    func setAnimationOffset(identifier: String, x: Int, y: Int) {
        guard let id = animationID(for: identifier) else { return }
        animationOffsets[id] = SurfacePoint(x: x, y: y)
    }

    func setRepaintLocked(_ locked: Bool) {
        isRepaintLocked = locked
        guard !locked, let pendingAnimationImage else { return }
        imageView?.image = pendingAnimationImage
        self.pendingAnimationImage = nil
    }

    private func animationID(for identifier: String) -> Int? {
        if let id = Int(identifier) {
            return id
        }
        return currentSurfaceDefinition?.animations.first {
            $0.name?.caseInsensitiveCompare(identifier) == .orderedSame
        }?.id
    }

    private func startAnimation(
        id: Int,
        minimumFrameDurationMilliseconds: Int
    ) -> Task<Void, Never>? {
        guard let animation = currentSurfaceDefinition?.animations.first(where: { $0.id == id }) else {
            return nil
        }
        animationTask?.cancel()
        currentAnimationID = id
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await run(
                animation,
                minimumFrameDurationMilliseconds: minimumFrameDurationMilliseconds
            )
            if currentAnimationID == id {
                currentAnimationID = nil
                animationTask = nil
            }
        }
        animationTask = task
        return task
    }

    func changeSurface(to surfaceID: Int) throws {
        guard let shell, let window else { return }
        animationTask?.cancel()
        schedulerTask?.cancel()
        pausedAnimationIDs.removeAll()
        animationOffsets.removeAll()
        isRepaintLocked = false
        pendingAnimationImage = nil

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
        surfaceBaseImage = rendered.image
        baseImage = rendered.image
        persistentAnimationLayers.removeAll()
        scheduleAutomaticAnimations()
    }

    private func applyInstantPersistentAnimation(id: Int) -> Bool {
        guard let shell,
              let surfaceBaseImage,
              let animation = currentSurfaceDefinition?.animations.first(where: { $0.id == id }),
              animation.patterns.count == 1,
              let pattern = animation.patterns.first,
              pattern.waitMilliseconds == 0,
              pattern.surfaceID >= 0,
              let operation = surfaceCompositingOperation(for: pattern.method),
              let overlay = try? renderLayer(surfaceID: pattern.surfaceID, shell: shell, visited: [])
        else { return false }
        let offset = animationOffsets[id] ?? SurfacePoint(x: 0, y: 0)
        persistentAnimationLayers[id] = PersistentAnimationLayer(
            image: overlay,
            x: pattern.x + offset.x,
            y: pattern.y + offset.y,
            operation: operation,
            clipsToBaseAlpha: surfaceCompositingClipsToBaseAlpha(pattern.method)
        )
        let order = currentSurfaceDefinition?.animations.map(\.id) ?? []
        let result = order.reversed().reduce(surfaceBaseImage) { image, animationID in
            guard let layer = persistentAnimationLayers[animationID] else { return image }
            return imageLoader.composite(
                base: image,
                overlay: layer.image,
                x: layer.x,
                y: layer.y,
                operation: layer.operation,
                clipsToBaseAlpha: layer.clipsToBaseAlpha
            )
        }
        baseImage = result
        setAnimationImage(result)
        return true
    }

    private struct PersistentAnimationLayer {
        let image: NSImage
        let x: Int
        let y: Int
        let operation: NSCompositingOperation
        let clipsToBaseAlpha: Bool
    }

    func hide() {
        imageView?.cancelDrag()
        dragFeedback.hide()
        animationTask?.cancel()
        schedulerTask?.cancel()
        window?.orderOut(nil)
    }

    func restore() {
        window?.orderFront(nil)
        setPresentationHidden(false)
    }

    func setPresentationHidden(_ hidden: Bool) {
        presentationHidden = hidden
        if hidden {
            imageView?.cancelDrag()
        }
        window?.alphaValue = presentationAlpha
    }

    func setAlpha(_ alpha: CGFloat?, durationMilliseconds: Int) async {
        if let alpha {
            surfaceAlpha = min(max(alpha, 0), 1)
        }
        guard let window else { return }
        let target = presentationAlpha
        guard durationMilliseconds > 0 else {
            window.alphaValue = target
            return
        }
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Double(durationMilliseconds) / 1000
                context.timingFunction = CAMediaTimingFunction(name: .linear)
                window.animator().alphaValue = target
            } completionHandler: {
                continuation.resume()
            }
        }
        // Dragging or hiding may have changed while the animation was running.
        window.alphaValue = presentationAlpha
    }

    private var presentationHidden = false

    private var presentationAlpha: CGFloat {
        presentationHidden ? 0 : surfaceAlpha * (isDragging ? 0.5 : 1)
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

    func setAutomaticallyFitsLargeSurfaces(_ enabled: Bool) {
        automaticallyFitsLargeSurfaces = enabled
        guard let baseImage else { return }
        automaticFitScale = enabled
            ? automaticSurfaceFitScale(imageSize: baseImage.size, visibleSize: NSScreen.main?.visibleFrame.size)
            : 1
        guard let window else { return }
        window.setContentSize(displaySize(for: baseImage))
        updateImageViewCoordinateScale()
    }

    func setRuntimeScale(
        horizontal: CGFloat,
        vertical: CGFloat,
        durationMilliseconds: Int
    ) async {
        runtimeScaleX = horizontal
        runtimeScaleY = vertical
        guard let shell, let baseSurfaceID, let window,
              let rendered = try? render(surfaceID: baseSurfaceID, shell: shell)
        else { return }
        let oldContentSize = window.contentView?.frame.size
            ?? window.contentRect(forFrameRect: window.frame).size
        rendered.view.frame = NSRect(origin: .zero, size: oldContentSize)
        rendered.view.autoresizingMask = [.width, .height]
        window.contentView = rendered.view
        imageView = rendered.view
        baseImage = rendered.image
        let targetSize = displaySize(for: rendered.image)
        guard durationMilliseconds > 0 else {
            window.setContentSize(targetSize)
            scheduleAutomaticAnimations()
            return
        }
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Double(durationMilliseconds) / 1000
                context.timingFunction = CAMediaTimingFunction(name: .linear)
                window.animator().setContentSize(targetSize)
            } completionHandler: {
                continuation.resume()
            }
        }
        scheduleAutomaticAnimations()
    }

    func setPlacement(locksToDesktopBottom: Bool, keepsOnScreen: Bool) {
        self.locksToDesktopBottom = locksToDesktopBottom
        self.keepsOnScreen = keepsOnScreen
        imageView?.locksVerticalMovement = locksToDesktopBottom
        (window as? FloatingContentWindow)?.setPlacementPolicy(.init(
            edge: effectiveDesktopEdge,
            keepsOnScreen: keepsOnScreen
        ))
    }

    func setDesktopAlignment(_ alignment: SurfaceDesktopAlignment) {
        desktopAlignment = alignment
        imageView?.locksHorizontalMovement = [.left, .right].contains(alignment)
        imageView?.locksVerticalMovement = [.top, .bottom].contains(alignment)
            || (alignment == .defaultValue && locksToDesktopBottom)
        (window as? FloatingContentWindow)?.setPlacementPolicy(.init(
            edge: effectiveDesktopEdge,
            keepsOnScreen: keepsOnScreen
        ))
    }

    private var effectiveDesktopEdge: FloatingWindowPlacementPolicy.Edge? {
        switch desktopAlignment {
        case .top: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        case .free: nil
        case .defaultValue: locksToDesktopBottom ? .bottom : nil
        }
    }

    private func displaySize(for image: NSImage) -> NSSize {
        NSSize(
            width: max(1, image.size.width * effectiveDisplayScale * abs(runtimeScaleX)),
            height: max(1, image.size.height * effectiveDisplayScale * abs(runtimeScaleY))
        )
    }

    private var effectiveDisplayScale: CGFloat {
        automaticFitScale < 1 ? min(displayScale, automaticFitScale) : displayScale
    }

    private func updateImageViewCoordinateScale() {
        imageView?.coordinateScaleX = max(.leastNonzeroMagnitude, effectiveDisplayScale * abs(runtimeScaleX))
        imageView?.coordinateScaleY = max(.leastNonzeroMagnitude, effectiveDisplayScale * abs(runtimeScaleY))
    }

    var onWindowDragDelta: ((_ delta: NSPoint) -> Void)?
    var onWindowMove: ((NSPoint) -> Void)?

    var windowNumber: Int? {
        window?.windowNumber
    }

    func orderAbove(relativeTo otherWindowNumber: Int) {
        window?.order(.above, relativeTo: otherWindowNumber)
    }

    func moveBy(delta: NSPoint) {
        guard let window else { return }
        let currentOrigin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: currentOrigin.x + delta.x, y: currentOrigin.y + delta.y))
    }

    func center() {
        window?.center()
    }

    func setOrigin(_ origin: NSPoint) {
        window?.setFrameOrigin(origin)
    }

    func moveOrigin(to targetOrigin: NSPoint, durationMilliseconds: Int) async {
        guard let window else { return }
        guard durationMilliseconds > 0 else {
            window.setFrameOrigin(targetOrigin)
            return
        }
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Double(durationMilliseconds) / 1000
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrameOrigin(targetOrigin)
            } completionHandler: {
                continuation.resume()
            }
        }
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
        let scaledSize = displaySize(for: boundImage)
        let imageView = SurfaceImageView(frame: NSRect(origin: .zero, size: scaledSize))
        imageView.image = boundImage
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.coordinateScaleX = max(.leastNonzeroMagnitude, effectiveDisplayScale * abs(runtimeScaleX))
        imageView.coordinateScaleY = max(.leastNonzeroMagnitude, effectiveDisplayScale * abs(runtimeScaleY))
        imageView.flipsHorizontally = runtimeScaleX < 0
        imageView.flipsVertically = runtimeScaleY < 0
        imageView.locksHorizontalMovement = [.left, .right].contains(desktopAlignment)
        imageView.locksVerticalMovement = [.top, .bottom].contains(desktopAlignment)
            || (desktopAlignment == .defaultValue && locksToDesktopBottom)
        imageView.isMovementLocked = isMovementLocked
        imageView.collisions = effectiveCollisions(for: definition, shell: shell)
        imageView.cursorDefinitions = shell.cursorDefinitions[scope] ?? []
        imageView.tooltipDefinitions = shell.tooltips[scope] ?? [:]
        imageView.shellDirectory = shell.directory
        imageView.setCollisionMode(collisionMode.enabled, showsNames: collisionMode.showsNames)
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
        imageView.onFileDropping = { [weak self] urls in
            self?.onFileDropping?(urls)
        }
        imageView.onFileDrop = { [weak self] urls in
            self?.onFileDrop?(urls)
        }
        imageView.onURLDropping = { [weak self] url in self?.onURLDropping?(url) }
        imageView.onURLDrop = { [weak self] url in self?.onURLDrop?(url) }
        imageView.onTextDrop = { [weak self] value in self?.onTextDrop?(value) }
        imageView.onWindowDragDelta = { [weak self] delta in
            self?.onWindowDragDelta?(delta)
        }
        imageView.onDragUpdate = { [weak self] startOrigin, pointer in
            guard let self else { return }
            isDragging = startOrigin != nil
            window?.alphaValue = presentationAlpha
            if let startOrigin, let pointer, let frame = window?.frame, !presentationHidden {
                dragFeedback.show(SurfaceDragPosition(
                    frame: frame, startOrigin: startOrigin,
                    desktopTop: NSScreen.screens.first?.frame.maxY ?? 0
                ), near: pointer)
            } else {
                dragFeedback.hide()
            }
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
        for element in elements.dropFirst() {
            guard let operation = surfaceCompositingOperation(for: element.method) else { continue }
            let overlay = try imageLoader.load(
                shellLoader.loadElement(filename: element.filename, from: shell.directory),
                usesSelfAlpha: shell.usesSelfAlpha
            )
            result = imageLoader.composite(
                base: result,
                overlay: overlay,
                x: element.x,
                y: element.y,
                operation: operation,
                clipsToBaseAlpha: surfaceCompositingClipsToBaseAlpha(element.method)
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
        let enabled = shell.effectiveBindGroups(scope: scope, enabled: enabledBindGroups)
        var result = base
        // `definition.animations` is ordered from front to back according to
        // animation-sort. Compositing must paint the backmost layer first.
        for animation in definition.animations.reversed() {
            guard !excludedAnimationIDs.contains(animation.id) else { continue }
            let interval = animation.interval?.lowercased() ?? ""
            let isBound = interval.contains("bind")
            let isInitial = interval.contains("runonce") && !isBound
            guard isInitial || (isBound && enabled.contains(animation.id)) else { continue }
            for pattern in animation.patterns.sorted(by: { $0.order < $1.order }) {
                guard pattern.waitMilliseconds == 0,
                      pattern.surfaceID >= 0,
                      let operation = surfaceCompositingOperation(for: pattern.method)
                else { continue }
                let overlay = try renderLayer(
                    surfaceID: pattern.surfaceID,
                    shell: shell,
                    visited: visited
                )
                result = imageLoader.composite(
                    base: result,
                    overlay: overlay,
                    x: pattern.x,
                    y: pattern.y,
                    operation: operation,
                    clipsToBaseAlpha: surfaceCompositingClipsToBaseAlpha(pattern.method)
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
        var previousOrigin: NSPoint?
        let window = FloatingContentWindow(
            title: "Ghost Surface \(scope)",
            placementPolicy: .init(
                edge: effectiveDesktopEdge,
                keepsOnScreen: keepsOnScreen
            )
        ) { [weak self, positionStore, scope] origin in
            positionStore.save(origin, for: .surface, scope: scope)
            let oldOrigin = previousOrigin
            previousOrigin = origin
            if let oldOrigin, oldOrigin != origin {
                self?.onWindowMove?(NSPoint(x: origin.x - oldOrigin.x, y: origin.y - oldOrigin.y))
            }
        }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.onCancel = { [weak self] in self?.imageView?.cancelDrag() }
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = stayOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private var currentSurfaceDefinition: SurfaceDefinition? {
        guard let baseSurfaceID else { return nil }
        return shell?.surfaces[baseSurfaceID]
    }

    var balloonOffset: NSPoint {
        guard let definition = currentSurfaceDefinition else { return .zero }
        let offset = definition.scopeBalloonOffsets[scope] ?? definition.balloonOffset ?? SurfacePoint(x: 0, y: 0)
        return NSPoint(
            x: Double(offset.x) * effectiveDisplayScale * abs(runtimeScaleX),
            y: Double(offset.y) * effectiveDisplayScale * abs(runtimeScaleY)
        )
    }

    private func scheduleAutomaticAnimations() {
        let enabled = shell.map { $0.effectiveBindGroups(scope: scope, enabled: enabledBindGroups) } ?? []
        let animations = currentSurfaceDefinition?.animations.filter { animation in
            let interval = animation.interval?.lowercased() ?? ""
            let components = Set(interval.split(separator: "+").map(String.init))
            guard !components.isDisjoint(with: ["sometimes", "rarely", "random", "periodic", "always"]) else {
                return false
            }
            guard components.contains("bind") else { return true }
            // SERIKO shells commonly pair a default static group (100) with
            // its automatic blink group (101).
            return enabled.contains(animation.id) || enabled.contains(animation.id - 1)
        } ?? []
        guard !animations.isEmpty else { return }

        schedulerTask = Task { [weak self] in
            var elapsedSeconds: [Int: Int] = [:]
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                let ready = animations.filter { animation in
                    let components = Set((animation.interval ?? "").lowercased().split(separator: "+").map(String.init))
                    elapsedSeconds[animation.id, default: 0] += 1
                    if components.contains("always") {
                        return true
                    }
                    if let denominator = automaticAnimationRandomDenominator(
                        components: components,
                        parameter: animation.intervalParameter
                    ) {
                        return Int.random(in: 0 ..< denominator) == 0
                    }
                    if components.contains("periodic"),
                       elapsedSeconds[animation.id, default: 0] >= max(animation.intervalParameter ?? 1, 1)
                    {
                        elapsedSeconds[animation.id] = 0
                        return true
                    }
                    return false
                }
                if let animation = ready.randomElement() {
                    await run(animation)
                }
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
              imageView != nil
        else { return }
        isAnimating = true
        imageView?.collisions = effectiveCollisions(for: currentSurfaceDefinition, shell: shell) + animation.collisions
        defer {
            setAnimationImage(baseImage)
            imageView?.collisions = effectiveCollisions(for: currentSurfaceDefinition, shell: shell)
            isAnimating = false
        }

        let stoppedAnimationIDs = Set(animation.patterns.compactMap { pattern in
            pattern.method.lowercased() == "stop" && pattern.surfaceID >= 0
                ? pattern.surfaceID
                : nil
        })
        let isInitiallyComposited = (animation.interval ?? "").lowercased().split(separator: "+").contains("bind")
        let excludedAnimationIDs = stoppedAnimationIDs.union([animation.id])
        let animationBase = if stoppedAnimationIDs.isEmpty, !isInitiallyComposited {
            baseImage
        } else {
            (try? render(
                surfaceID: baseSurfaceID,
                shell: shell,
                excludingInitialAnimations: excludedAnimationIDs
            ).image) ?? baseImage
        }
        var frameBase = animationBase

        for pattern in animation.patterns {
            guard !Task.isCancelled else { return }
            let offset = animationOffsets[animation.id] ?? SurfacePoint(x: 0, y: 0)

            if pattern.method.lowercased() == "move" {
                frameBase = imageLoader.translated(animationBase, x: pattern.x + offset.x, y: pattern.y + offset.y)
                setAnimationImage(frameBase)
            } else if pattern.surfaceID < 0 {
                frameBase = animationBase
                setAnimationImage(animationBase)
            } else if pattern.method.lowercased() == "base" {
                do {
                    frameBase = try render(
                        surfaceID: pattern.surfaceID,
                        shell: shell,
                        excludingInitialAnimations: excludedAnimationIDs
                    ).image
                    setAnimationImage(frameBase)
                } catch {
                    continue
                }
            } else if let operation = surfaceCompositingOperation(for: pattern.method) {
                do {
                    let overlay = try renderLayer(
                        surfaceID: pattern.surfaceID,
                        shell: shell,
                        visited: []
                    )
                    setAnimationImage(imageLoader.composite(
                        base: frameBase,
                        overlay: overlay,
                        x: pattern.x + offset.x,
                        y: pattern.y + offset.y,
                        operation: operation,
                        clipsToBaseAlpha: surfaceCompositingClipsToBaseAlpha(pattern.method)
                    ))
                } catch {
                    continue
                }
            }

            var remainingMilliseconds = max(
                pattern.waitMilliseconds,
                minimumFrameDurationMilliseconds
            )
            while remainingMilliseconds > 0 {
                guard !Task.isCancelled else { return }
                if pausedAnimationIDs.contains(animation.id) {
                    do {
                        try await Task.sleep(for: .milliseconds(20))
                    } catch {
                        return
                    }
                    continue
                }
                let interval = min(remainingMilliseconds, 20)
                do {
                    try await Task.sleep(for: .milliseconds(interval))
                } catch {
                    return
                }
                remainingMilliseconds -= interval
            }
        }
    }

    private func effectiveCollisions(for definition: SurfaceDefinition?, shell: ShellDefinition) -> [SurfaceCollision] {
        guard let definition else { return [] }
        let enabled = shell.effectiveBindGroups(scope: scope, enabled: enabledBindGroups)
        let bound = definition.animations.filter {
            ($0.interval ?? "").lowercased().split(separator: "+").contains("bind")
                && (enabled.contains($0.id) || enabled.contains($0.id - 1))
        }.flatMap(\.collisions)
        return bound + definition.collisions
    }

    private func setAnimationImage(_ image: NSImage) {
        if isRepaintLocked {
            pendingAnimationImage = image
        } else {
            imageView?.image = image
        }
    }
}

func surfaceCompositingOperation(for method: String) -> NSCompositingOperation? {
    let method = method.lowercased()
    if method == "overlay-fast" || method == "overlayfast" {
        // SERIKO overlay-fast clips the new layer to the base layer's alpha.
        return .sourceAtop
    }
    let baseMethod = method.hasSuffix("-fast") ? String(method.dropLast("-fast".count)) : method
    return switch baseMethod {
    case "overlay", "auto", "bind", "add":
        .sourceOver
    case "blend-multiply", "overlaymultiply":
        .multiply
    case "blend-screen", "overlayscreen":
        .screen
    case "blend-overlay":
        .overlay
    case "blend-add", "blend-add-glow":
        .plusLighter
    case "blend-soft-light":
        .softLight
    case "blend-hard-light", "blend-vivid-light", "blend-linear-light", "blend-pin-light", "blend-hard-mix":
        .hardLight
    case "blend-color-dodge", "blend-color-dodge-glow":
        .colorDodge
    case "blend-color":
        .color
    case "blend-luminosity":
        .luminosity
    case "blend-hue":
        .hue
    case "blend-saturation":
        .saturation
    case "blend-darken", "blend-darker-color", "blend-linear-burn", "blend-subtract":
        .darken
    case "blend-lighten", "blend-lighter-color", "blend-divide":
        .lighten
    case "blend-color-burn":
        .colorBurn
    case "blend-difference":
        .difference
    case "blend-exclusion":
        .exclusion
    case "replace":
        .copy
    case "interpolate":
        .destinationOver
    case "reduce":
        .destinationIn
    default:
        nil
    }
}

func surfaceCompositingClipsToBaseAlpha(_ method: String) -> Bool {
    let method = method.lowercased()
    return method == "overlaymultiply" || method == "blend-multiply-fast"
}

private final class SurfaceImageView: NSImageView {
    var collisions: [SurfaceCollision] = []
    var cursorDefinitions: [SurfaceCursorDefinition] = []
    var tooltipDefinitions: [String: String] = [:]
    var shellDirectory: URL?
    var coordinateScaleX: CGFloat = 1
    var coordinateScaleY: CGFloat = 1
    var flipsHorizontally = false
    var flipsVertically = false
    var onMouseClick: ((String?) -> Void)?
    var onMouseEvent: ((GhostMouseEvent.Kind, String?, Int, Int, Int) -> Void)?
    var contextMenuItems: (@MainActor () -> [SurfaceContextMenuItem])?
    var onNarDrop: (([URL]) -> Void)?
    var onFileDropping: (([URL]) -> Void)?
    var onFileDrop: (([URL]) -> Void)?
    var onURLDropping: ((URL) -> Void)?
    var onURLDrop: ((URL) -> Void)?
    var onTextDrop: ((String) -> Void)?
    var onWindowDragDelta: ((NSPoint) -> Void)?
    var onDragUpdate: ((NSPoint?, NSPoint?) -> Void)?
    var locksVerticalMovement = true
    var locksHorizontalMovement = false
    var isMovementLocked = false {
        didSet {
            if isMovementLocked {
                cancelDrag()
            }
        }
    }

    private var collisionMode = (enabled: false, showsNames: true)
    private var hoveredRegion: String?
    private var lastStrokePoint: NSPoint?
    private var lastStrokeRegion: String?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var lastDragEvent: NSEvent?
    private var didDrag = false
    private var suppressDragClick = false
    private var hoverWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .URL, .string])
        NotificationCenter.default.addObserver(
            self, selector: #selector(cancelDrag), name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            cancelDrag()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc func cancelDrag() {
        let endingEvent = didDrag ? lastDragEvent : nil
        suppressDragClick = suppressDragClick || didDrag
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        lastDragEvent = nil
        onDragUpdate?(nil, nil)
        if let endingEvent {
            sendMouseEvent(.dragEnd, event: endingEvent)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelDrag()
    }

    override func layout() {
        super.layout()
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer?.setAffineTransform(CGAffineTransform(
            scaleX: flipsHorizontally ? -1 : 1,
            y: flipsVertically ? -1 : 1
        ))
    }

    func setCollisionMode(_ enabled: Bool, showsNames: Bool) {
        collisionMode = (enabled, showsNames)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard collisionMode.enabled else { return }
        for collision in collisions {
            NSGraphicsContext.saveGraphicsState()
            NSColor.systemRed.withAlphaComponent(0.85).setStroke()
            NSColor.systemRed.withAlphaComponent(0.14).setFill()
            let path = collisionPath(collision)
            path.lineWidth = 1
            path.fill()
            path.stroke()
            if collisionMode.showsNames {
                let origin = path.bounds.origin
                collision.name.draw(
                    at: NSPoint(x: origin.x + 2, y: origin.y + 1),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 10),
                        .foregroundColor: NSColor.white,
                        .backgroundColor: NSColor.systemRed.withAlphaComponent(0.8)
                    ]
                )
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func collisionPath(_ collision: SurfaceCollision) -> NSBezierPath {
        if collision.polygon.count >= 3 {
            let path = NSBezierPath()
            for (index, point) in collision.polygon.enumerated() {
                let mapped = collisionPoint(x: point.x, y: point.y)
                index == 0 ? path.move(to: mapped) : path.line(to: mapped)
            }
            path.close()
            return path
        }
        let first = collisionPoint(x: collision.left, y: collision.top)
        let second = collisionPoint(x: collision.right, y: collision.bottom)
        return NSBezierPath(rect: NSRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        ))
    }

    private func collisionPoint(x: Int, y: Int) -> NSPoint {
        NSPoint(
            x: CGFloat(x) * coordinateScaleX,
            y: bounds.height - CGFloat(y) * coordinateScaleY
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        cancelDrag()
        suppressDragClick = false
        sendMouseEvent(.down, event: event)
        cancelHoverEvent()
        setCursor(.mouseDown, for: hitTest(event).region)
        guard event.buttonNumber == 0, let window else {
            super.mouseDown(with: event)
            return
        }
        dragStartMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        dragStartWindowOrigin = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isMovementLocked, !suppressDragClick else { return }
        guard let window,
              let startMouseLocation = dragStartMouseLocation,
              let startWindowOrigin = dragStartWindowOrigin
        else {
            super.mouseDragged(with: event)
            return
        }
        let currentMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = currentMouseLocation.x - startMouseLocation.x
        let deltaY = currentMouseLocation.y - startMouseLocation.y
        lastDragEvent = event
        if !didDrag, hypot(deltaX, deltaY) >= 2 {
            didDrag = true
            sendMouseEvent(.dragStart, event: event)
        }
        guard didDrag else { return }
        let currentOrigin = window.frame.origin
        let newX = locksHorizontalMovement ? startWindowOrigin.x : startWindowOrigin.x + deltaX
        let newY = locksVerticalMovement ? startWindowOrigin.y : startWindowOrigin.y + deltaY
        window.setFrameOrigin(NSPoint(x: newX, y: newY))
        let moveDelta = NSPoint(x: window.frame.minX - currentOrigin.x, y: window.frame.minY - currentOrigin.y)
        onDragUpdate?(startWindowOrigin, currentMouseLocation)
        if moveDelta.x != 0 || moveDelta.y != 0 {
            onWindowDragDelta?(moveDelta)
        }
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
        let hit = hitTest(event)
        onMouseEvent?(.enterAll, hit.region, hit.x, hit.y, buttonNumber(event))
        updateHoveredRegion(with: hit, event: event)
        scheduleHoverEvent(for: hit, event: event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        cancelHoverEvent()
        let hit = hitTest(event)
        if let hoveredRegion {
            onMouseEvent?(.leave, hoveredRegion, hit.x, hit.y, buttonNumber(event))
        }
        onMouseEvent?(.leaveAll, hoveredRegion, hit.x, hit.y, buttonNumber(event))
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
        let hit = hitTest(event)
        updateHoveredRegion(with: hit, event: event)
        scheduleHoverEvent(for: hit, event: event)
        sendStrokeEventIfNeeded(event)
        super.mouseMoved(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragStartMouseLocation != nil && didDrag
        sendMouseEvent(.up, event: event)
        if wasDragging {
            lastDragEvent = event
        }
        cancelDrag()
        let suppressClick = suppressDragClick
        suppressDragClick = false
        setCursor(.mouseUp, for: hitTest(event).region)
        if wasDragging {
            scheduleHoverEvent(for: hitTest(event), event: event)
            return
        }
        guard !suppressClick else { return }
        let hit = hitTest(event)
        if event.clickCount >= 3 {
            onMouseEvent?(.multipleClick(count: event.clickCount), hit.region, hit.x, hit.y, buttonNumber(event))
        } else if event.clickCount == 2 {
            onMouseEvent?(.doubleClick, hit.region, hit.x, hit.y, buttonNumber(event))
        } else {
            onMouseClick?(hit.region)
            onMouseEvent?(.click, hit.region, hit.x, hit.y, buttonNumber(event))
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        sendMouseEvent(.down, event: event)
        cancelHoverEvent()
        setCursor(.mouseRightDown, for: hitTest(event).region)
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseEvent(.up, event: event)
        setCursor(.mouseUp, for: hitTest(event).region)
        sendClickEvent(event)
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        sendMouseEvent(.down, event: event)
        cancelHoverEvent()
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMouseEvent(.up, event: event)
        sendClickEvent(event)
        super.otherMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Int(event.scrollingDeltaY.rounded())
        guard delta != 0 else { return }
        setCursor(.mouseWheel, for: hitTest(event).region)
        sendMouseEvent(.wheel(delta: delta), event: event)
        super.scrollWheel(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        if !urls.isEmpty {
            onFileDropping?(urls)
        } else if let url = webURL(from: sender) {
            onURLDropping?(url)
        } else if droppedText(from: sender) == nil {
            return []
        }
        return .copy
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty || webURL(from: sender) != nil || droppedText(from: sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        if !urls.isEmpty {
            onFileDrop?(urls)
            let nars = SurfaceDropPayload.narURLs(from: urls)
            if !nars.isEmpty {
                onNarDrop?(nars)
            }
        } else if let url = webURL(from: sender) {
            onURLDrop?(url)
        } else if let text = droppedText(from: sender) {
            onTextDrop?(text)
        } else {
            return false
        }
        return true
    }

    private func fileURLs(from draggingInfo: any NSDraggingInfo) -> [URL] {
        guard let items = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        else { return [] }
        return items
    }

    private func webURL(from draggingInfo: any NSDraggingInfo) -> URL? {
        guard let value = draggingInfo.draggingPasteboard.string(forType: .URL),
              let url = URL(string: value), !url.isFileURL
        else { return nil }
        return url
    }

    private func droppedText(from draggingInfo: any NSDraggingInfo) -> String? {
        draggingInfo.draggingPasteboard.string(forType: .string)
    }

    private func sendMouseEvent(_ kind: GhostMouseEvent.Kind, event: NSEvent) {
        let hit = hitTest(event)
        onMouseEvent?(kind, hit.region, hit.x, hit.y, buttonNumber(event))
    }

    private func sendClickEvent(_ event: NSEvent) {
        let hit = hitTest(event)
        let kind: GhostMouseEvent.Kind = if event.clickCount >= 3 {
            .multipleClick(count: event.clickCount)
        } else if event.clickCount == 2 {
            .doubleClick
        } else {
            .click
        }
        onMouseEvent?(kind, hit.region, hit.x, hit.y, buttonNumber(event))
        scheduleHoverEvent(for: hit, event: event)
    }

    private func scheduleHoverEvent(
        for hit: (region: String?, x: Int, y: Int),
        event: NSEvent
    ) {
        cancelHoverEvent()
        let button = buttonNumber(event)
        let workItem = DispatchWorkItem { [weak self] in
            self?.onMouseEvent?(.hover, hit.region, hit.x, hit.y, button)
            self?.setCursor(.mouseHover, for: hit.region)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func cancelHoverEvent() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
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
        guard distance >= SurfaceStrokeEventPolicy.minimumDistance(for: region) else { return }
        lastStrokePoint = point
        onMouseEvent?(.move, region, hit.x, hit.y, buttonNumber(event))
    }

    private func updateCursor(for event: NSEvent) {
        let hit = hitTest(event)
        updateHoveredRegion(with: hit, event: event)
    }

    private func updateHoveredRegion(
        with hit: (region: String?, x: Int, y: Int),
        event: NSEvent
    ) {
        if hoveredRegion != hit.region {
            if let hoveredRegion {
                onMouseEvent?(.leave, hoveredRegion, hit.x, hit.y, buttonNumber(event))
            }
            if let region = hit.region {
                onMouseEvent?(.enter, region, hit.x, hit.y, buttonNumber(event))
            }
            hoveredRegion = hit.region
        }
        toolTip = tooltip(for: hit.region)
        setCursor(.mouseUp, for: hit.region)
    }

    private func tooltip(for region: String?) -> String? {
        guard let region else { return nil }
        return tooltipDefinitions.first {
            $0.key.caseInsensitiveCompare(region) == .orderedSame
        }?.value
    }

    private func setCursor(_ trigger: SurfaceCursorTrigger, for region: String?) {
        guard let region,
              let name = cursorDefinitions.last(where: {
                  $0.trigger == trigger && $0.region.caseInsensitiveCompare(region) == .orderedSame
              })?.cursor,
              let cursor = configuredCursor(named: name)
        else {
            SurfaceCursorStyle(region: region).cursor.set()
            return
        }
        cursor.set()
    }

    private func configuredCursor(named name: String) -> NSCursor? {
        switch name.lowercased() {
        case "system:arrow": return .arrow
        case "system:cross": return .crosshair
        case "system:no": return .operationNotAllowed
        case "system:hand": return .openHand
        case "system:grip": return .closedHand
        case "system:finger": return .pointingHand
        case "system:text": return .iBeam
        case "system:move": return .openHand
        case "system:help": return .contextualMenu
        case "system:wait": return .arrow
        default:
            guard let shellDirectory else { return nil }
            let fileURL = shellDirectory.appending(path: name, directoryHint: .notDirectory).standardizedFileURL
            let root = shellDirectory.standardizedFileURL.path(percentEncoded: false) + "/"
            guard fileURL.path(percentEncoded: false).hasPrefix(root), let image = NSImage(contentsOf: fileURL) else {
                return nil
            }
            return NSCursor(image: image, hotSpot: .zero)
        }
    }

    private func hitTest(_ event: NSEvent) -> (region: String?, x: Int, y: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let logicalX = flipsHorizontally ? bounds.width - point.x : point.x
        let logicalY = flipsVertically ? point.y : bounds.height - point.y
        let surfaceX = Int(logicalX / coordinateScaleX)
        let surfaceY = Int(logicalY / coordinateScaleY)
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

enum SurfaceStrokeEventPolicy {
    static func minimumDistance(for region: String) -> CGFloat {
        region.caseInsensitiveCompare("Head") == .orderedSame ? 2 : 4
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

import AppKit

@MainActor
protocol PresentationHosting: AnyObject {
    var geometryProvider: any PresentationGeometryProviding { get }

    func makeItem(
        kind: PresentationItemKind,
        title: String,
        onMove: @escaping (NSPoint) -> Void,
        onCancel: (() -> Void)?
    ) -> any PresentationItem

    func setTitle(_ title: String)
}

extension PresentationHosting {
    func setTitle(_ title: String) {}
}

enum PresentationItemKind {
    case surface
    case balloon
}

/// The presentation operations shared by independent desktop windows and
/// items embedded in a future window-mode stage.
@MainActor
protocol PresentationItem: AnyObject {
    var frame: NSRect { get }
    var isVisible: Bool { get }
    var contentView: NSView? { get set }
    var contentSize: NSSize { get }
    var alphaValue: CGFloat { get set }
    var captureWindowNumber: Int? { get }

    func setContentSize(_ size: NSSize)
    func setFrameOrigin(_ origin: NSPoint)
    func center()
    func show(activating: Bool)
    func hide()
    func setStaysOnTop(_ staysOnTop: Bool)
    func setPlacementPolicy(_ policy: FloatingWindowPlacementPolicy)
    func orderAbove(_ other: any PresentationItem)
    func animateFrameOrigin(_ origin: NSPoint, duration: TimeInterval) async
    func animateContentSize(_ size: NSSize, duration: TimeInterval) async
    func animateAlphaValue(_ alpha: CGFloat, duration: TimeInterval) async
    func discard()
}

@MainActor
final class DesktopPresentationItem: PresentationItem {
    let window: FloatingContentWindow

    init(window: FloatingContentWindow) {
        self.window = window
    }

    var frame: NSRect {
        window.frame
    }

    var isVisible: Bool {
        window.isVisible
    }

    var contentView: NSView? {
        get { window.contentView }
        set { window.contentView = newValue }
    }

    var alphaValue: CGFloat {
        get { window.alphaValue }
        set { window.alphaValue = newValue }
    }

    var contentSize: NSSize {
        window.contentRect(forFrameRect: window.frame).size
    }

    var captureWindowNumber: Int? {
        window.windowNumber
    }

    func setContentSize(_ size: NSSize) {
        window.setContentSize(size)
    }

    func setFrameOrigin(_ origin: NSPoint) {
        window.setFrameOrigin(origin)
    }

    func center() {
        window.center()
    }

    func show(activating: Bool) {
        if activating {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func setStaysOnTop(_ staysOnTop: Bool) {
        window.level = staysOnTop ? .floating : .normal
    }

    func setPlacementPolicy(_ policy: FloatingWindowPlacementPolicy) {
        window.setPlacementPolicy(policy)
    }

    func orderAbove(_ other: any PresentationItem) {
        guard let other = other as? DesktopPresentationItem else { return }
        window.order(.above, relativeTo: other.window.windowNumber)
    }

    func animateFrameOrigin(_ origin: NSPoint, duration: TimeInterval) async {
        await animate(duration: duration) {
            self.window.animator().setFrameOrigin(origin)
        }
    }

    func animateContentSize(_ size: NSSize, duration: TimeInterval) async {
        await animate(duration: duration) {
            self.window.animator().setContentSize(size)
        }
    }

    func animateAlphaValue(_ alpha: CGFloat, duration: TimeInterval) async {
        await animate(duration: duration, timingFunction: CAMediaTimingFunction(name: .linear)) {
            self.window.animator().alphaValue = alpha
        }
    }

    func discard() {
        window.orderOut(nil)
        window.contentView = nil
    }

    private func animate(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        changes: @escaping @MainActor () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = timingFunction
                changes()
            } completionHandler: {
                continuation.resume()
            }
        }
    }
}

@MainActor
final class DesktopPresentationHost: PresentationHosting {
    let geometryProvider: any PresentationGeometryProviding

    init(geometryProvider: any PresentationGeometryProviding) {
        self.geometryProvider = geometryProvider
    }

    func makeItem(
        kind: PresentationItemKind,
        title: String,
        onMove: @escaping (NSPoint) -> Void,
        onCancel: (() -> Void)?
    ) -> any PresentationItem {
        let window = FloatingContentWindow(
            title: title,
            visibleFrames: { [geometryProvider] in geometryProvider.visibleFrames },
            onMove: onMove
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = kind == .balloon
        window.onCancel = onCancel
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = kind == .balloon
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return DesktopPresentationItem(window: window)
    }
}

public enum WindowModeStageBackground: String, CaseIterable, Sendable {
    case white
    case gray
    case black
}

struct WindowModeStageState {
    let contentSize: NSSize
    let origin: NSPoint?
    let background: WindowModeStageBackground
    let showsWindowFrame: Bool
}

final class WindowModeStageStateStore {
    private let defaults: UserDefaults
    private let namespace: String

    init(
        defaults: UserDefaults = .standard,
        namespace: String = "dev.utatane.window-mode-stage"
    ) {
        self.defaults = defaults
        self.namespace = namespace
    }

    func load(identifier: String) -> WindowModeStageState? {
        guard let value = defaults.dictionary(forKey: key(identifier: identifier)),
              let width = value["width"] as? Double,
              let height = value["height"] as? Double,
              let backgroundValue = value["background"] as? String,
              let background = WindowModeStageBackground(rawValue: backgroundValue),
              let showsWindowFrame = value["showsWindowFrame"] as? Bool
        else { return nil }
        let origin: NSPoint? = if let x = value["x"] as? Double, let y = value["y"] as? Double {
            NSPoint(x: x, y: y)
        } else {
            nil
        }
        return WindowModeStageState(
            contentSize: NSSize(width: width, height: height),
            origin: origin,
            background: background,
            showsWindowFrame: showsWindowFrame
        )
    }

    func save(_ state: WindowModeStageState, identifier: String) {
        var value: [String: Any] = [
            "width": Double(state.contentSize.width),
            "height": Double(state.contentSize.height),
            "background": state.background.rawValue,
            "showsWindowFrame": state.showsWindowFrame
        ]
        if let origin = state.origin {
            value["x"] = Double(origin.x)
            value["y"] = Double(origin.y)
        }
        defaults.set(value, forKey: key(identifier: identifier))
    }

    private func key(identifier: String) -> String {
        let encoded = Data(identifier.utf8).base64EncodedString()
        return "\(namespace).\(encoded)"
    }
}

@MainActor
final class WindowModePresentationHost: NSObject, PresentationHosting, NSWindowDelegate {
    let window: NSWindow
    let rootView: WindowModeStageRootView
    let geometryProvider: any PresentationGeometryProviding
    let mode: GhostWindowMode
    private var items: [WindowModePresentationItem] = []
    private let onModeRequest: (GhostWindowMode) -> Void
    private let stateStore: WindowModeStageStateStore?
    private let stateIdentifier: String
    private(set) var background: WindowModeStageBackground = .gray
    private(set) var showsWindowFrame = true

    init(
        contentSize: NSSize = NSSize(width: 960, height: 540),
        title: String = "Utatane",
        mode: GhostWindowMode = .perGhost,
        onModeRequest: @escaping (GhostWindowMode) -> Void = { _ in },
        stateStore: WindowModeStageStateStore? = nil,
        stateIdentifier: String = ""
    ) {
        let restoredState = stateStore?.load(identifier: stateIdentifier)
        let contentSize = restoredState?.contentSize ?? contentSize
        let window = WindowModeStageWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let rootView = WindowModeStageRootView(frame: NSRect(origin: .zero, size: contentSize))
        rootView.wantsLayer = true
        window.title = title
        window.contentView = rootView
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        self.rootView = rootView
        self.mode = mode
        self.onModeRequest = onModeRequest
        self.stateStore = stateStore
        self.stateIdentifier = stateIdentifier
        geometryProvider = WindowModePresentationGeometryProvider(
            window: window,
            rootView: rootView,
            coordinateSpace: mode == .shared ? .sharedWindowMode : .perGhostWindowMode
        )
        super.init()
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isEnabled = false
        rootView.host = self
        window.host = self
        if let origin = restoredState?.origin {
            window.setFrameOrigin(origin)
        }
        setBackground(restoredState?.background ?? .gray)
        setShowsWindowFrame(restoredState?.showsWindowFrame ?? true)
    }

    var itemCount: Int {
        items.count
    }

    func setTitle(_ title: String) {
        window.title = title
    }

    func setBackground(_ background: WindowModeStageBackground) {
        self.background = background
        rootView.layer?.backgroundColor = switch background {
        case .white: NSColor.white.cgColor
        case .gray: NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
        case .black: NSColor.black.cgColor
        }
        persistState()
    }

    func setShowsWindowFrame(_ showsWindowFrame: Bool) {
        guard self.showsWindowFrame != showsWindowFrame else { return }
        self.showsWindowFrame = showsWindowFrame
        if showsWindowFrame {
            window.styleMask.formUnion([.titled, .closable, .miniaturizable])
        } else {
            window.styleMask.subtract([.titled, .closable, .miniaturizable])
        }
        window.isMovableByWindowBackground = !showsWindowFrame
        persistState()
    }

    func toggleFullScreen() {
        window.toggleFullScreen(nil)
    }

    func makeOperationMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "操作"))
        let modeItem = NSMenuItem(
            title: String(localized: "ウィンドウモード"),
            action: nil,
            keyEquivalent: ""
        )
        let modeMenu = NSMenu(title: String(localized: "ウィンドウモード"))
        addModeItem(String(localized: "切"), mode: .off, to: modeMenu)
        addModeItem(String(localized: "全ゴーストをまとめて1枚"), mode: .shared, to: modeMenu)
        addModeItem(String(localized: "ゴーストごとに1枚"), mode: .perGhost, to: modeMenu)
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())

        let fullscreen = NSMenuItem(
            title: String(localized: "全画面表示"),
            action: #selector(toggleFullScreenFromMenu),
            keyEquivalent: ""
        )
        fullscreen.target = self
        fullscreen.state = window.styleMask.contains(.fullScreen) ? .on : .off
        menu.addItem(fullscreen)

        let frame = NSMenuItem(
            title: String(localized: "ウィンドウ枠を表示する"),
            action: #selector(toggleWindowFrameFromMenu),
            keyEquivalent: ""
        )
        frame.target = self
        frame.state = showsWindowFrame ? .on : .off
        menu.addItem(frame)

        let backgroundItem = NSMenuItem(title: String(localized: "背景"), action: nil, keyEquivalent: "")
        let backgroundMenu = NSMenu(title: String(localized: "背景"))
        addBackgroundItem(String(localized: "白"), background: .white, to: backgroundMenu)
        addBackgroundItem(String(localized: "灰"), background: .gray, to: backgroundMenu)
        addBackgroundItem(String(localized: "黒"), background: .black, to: backgroundMenu)
        backgroundItem.submenu = backgroundMenu
        menu.addItem(backgroundItem)
        return menu
    }

    private func addModeItem(_ title: String, mode: GhostWindowMode, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectModeFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        item.state = self.mode == mode ? .on : .off
        menu.addItem(item)
    }

    private func addBackgroundItem(
        _ title: String,
        background: WindowModeStageBackground,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(selectBackgroundFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = background.rawValue
        item.state = self.background == background ? .on : .off
        menu.addItem(item)
    }

    @objc private func selectModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = GhostWindowMode(rawValue: rawValue)
        else { return }
        onModeRequest(mode)
    }

    @objc private func toggleFullScreenFromMenu() {
        toggleFullScreen()
    }

    @objc private func toggleWindowFrameFromMenu() {
        setShowsWindowFrame(!showsWindowFrame)
    }

    @objc private func selectBackgroundFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let background = WindowModeStageBackground(rawValue: rawValue)
        else { return }
        setBackground(background)
    }

    func windowDidMove(_ notification: Notification) {
        persistState()
    }

    func windowDidResize(_ notification: Notification) {
        persistState()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        false
    }

    private func persistState() {
        stateStore?.save(
            WindowModeStageState(
                contentSize: window.contentView?.bounds.size ?? window.frame.size,
                origin: window.frame.origin,
                background: background,
                showsWindowFrame: showsWindowFrame
            ),
            identifier: stateIdentifier
        )
    }

    func makeItem(
        kind: PresentationItemKind,
        title: String,
        onMove: @escaping (NSPoint) -> Void,
        onCancel: (() -> Void)?
    ) -> any PresentationItem {
        let item = WindowModePresentationItem(
            host: self,
            hasShadow: kind == .balloon,
            onMove: onMove
        )
        if let onCancel {
            (window as? WindowModeStageWindow)?.cancelHandlers.append(onCancel)
        }
        item.containerView.setAccessibilityLabel(title)
        items.append(item)
        return item
    }

    fileprivate func present(_ item: WindowModePresentationItem, activating: Bool) {
        if item.containerView.superview !== rootView {
            rootView.addSubview(item.containerView)
        }
        item.containerView.isHidden = false
        if activating {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    fileprivate func discard(_ item: WindowModePresentationItem) {
        item.containerView.removeFromSuperview()
        items.removeAll { $0 === item }
        if items.isEmpty {
            window.orderOut(nil)
        }
    }
}

@MainActor
final class WindowModeStageRootView: NSView {
    weak var host: WindowModePresentationHost?

    override func menu(for event: NSEvent) -> NSMenu? {
        host?.makeOperationMenu()
    }
}

@MainActor
private final class WindowModeStageWindow: NSWindow {
    weak var host: WindowModePresentationHost?
    var cancelHandlers: [() -> Void] = []

    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            toggleFullScreen(sender)
        } else if cancelHandlers.isEmpty {
            super.cancelOperation(sender)
        } else {
            cancelHandlers.forEach { $0() }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .f11 {
            host?.toggleFullScreen()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class WindowModePresentationGeometryProvider: PresentationGeometryProviding {
    private weak var window: NSWindow?
    private weak var rootView: NSView?
    let coordinateSpace: PresentationCoordinateSpace

    init(
        window: NSWindow,
        rootView: NSView,
        coordinateSpace: PresentationCoordinateSpace
    ) {
        self.window = window
        self.rootView = rootView
        self.coordinateSpace = coordinateSpace
    }

    var screens: [PresentationScreenGeometry] {
        guard let rootView else { return [] }
        return [PresentationScreenGeometry(
            frame: rootView.bounds,
            visibleFrame: rootView.bounds,
            bitsPerPixel: 32,
            scale: window?.backingScaleFactor ?? 1,
            isPrimary: true
        )]
    }

    var pointerPosition: CGPoint {
        guard let window, let rootView else { return .zero }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return rootView.convert(windowPoint, from: nil)
    }
}

@MainActor
private final class WindowModePresentationItem: PresentationItem {
    weak var host: WindowModePresentationHost?
    let containerView = NSView(frame: .zero)
    private let onMove: (NSPoint) -> Void
    private var placementPolicy = FloatingWindowPlacementPolicy.free

    init(
        host: WindowModePresentationHost,
        hasShadow: Bool,
        onMove: @escaping (NSPoint) -> Void
    ) {
        self.host = host
        self.onMove = onMove
        containerView.wantsLayer = true
        containerView.layer?.shadowOpacity = hasShadow ? 0.28 : 0
        containerView.layer?.shadowRadius = hasShadow ? 8 : 0
        containerView.layer?.shadowOffset = NSSize(width: 0, height: -2)
        containerView.isHidden = true
    }

    var frame: NSRect {
        containerView.frame
    }

    var isVisible: Bool {
        containerView.superview != nil && !containerView.isHidden
    }

    var contentView: NSView? {
        get { containerView.subviews.first }
        set {
            containerView.subviews.forEach { $0.removeFromSuperview() }
            guard let newValue else { return }
            newValue.frame = containerView.bounds
            newValue.autoresizingMask = [.width, .height]
            containerView.addSubview(newValue)
        }
    }

    var contentSize: NSSize {
        containerView.bounds.size
    }

    var alphaValue: CGFloat {
        get { containerView.alphaValue }
        set { containerView.alphaValue = newValue }
    }

    var captureWindowNumber: Int? {
        host?.window.windowNumber
    }

    func setContentSize(_ size: NSSize) {
        containerView.setFrameSize(size)
    }

    func setFrameOrigin(_ origin: NSPoint) {
        let oldOrigin = containerView.frame.origin
        containerView.setFrameOrigin(origin)
        applyPlacementConstraint()
        let appliedOrigin = containerView.frame.origin
        if appliedOrigin != oldOrigin {
            onMove(appliedOrigin)
        }
    }

    func center() {
        guard let frame = host?.geometryProvider.mainScreen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(
            x: frame.midX - containerView.frame.width / 2,
            y: frame.midY - containerView.frame.height / 2
        ))
    }

    func show(activating: Bool) {
        host?.present(self, activating: activating)
    }

    func hide() {
        containerView.isHidden = true
    }

    func setStaysOnTop(_ staysOnTop: Bool) {
        host?.window.level = staysOnTop ? .floating : .normal
    }

    func setPlacementPolicy(_ policy: FloatingWindowPlacementPolicy) {
        placementPolicy = policy
        applyPlacementConstraint()
    }

    func orderAbove(_ other: any PresentationItem) {
        guard let other = other as? WindowModePresentationItem,
              other.containerView.superview === containerView.superview,
              let superview = containerView.superview
        else { return }
        superview.addSubview(containerView, positioned: .above, relativeTo: other.containerView)
    }

    func animateFrameOrigin(_ origin: NSPoint, duration: TimeInterval) async {
        await animate(duration: duration) {
            self.containerView.animator().setFrameOrigin(origin)
        }
        applyPlacementConstraint()
        onMove(containerView.frame.origin)
    }

    func animateContentSize(_ size: NSSize, duration: TimeInterval) async {
        await animate(duration: duration) {
            self.containerView.animator().setFrameSize(size)
        }
    }

    func animateAlphaValue(_ alpha: CGFloat, duration: TimeInterval) async {
        await animate(duration: duration, timingFunction: CAMediaTimingFunction(name: .linear)) {
            self.containerView.animator().alphaValue = alpha
        }
    }

    func discard() {
        contentView = nil
        host?.discard(self)
    }

    private func applyPlacementConstraint() {
        guard let host,
              let origin = placementPolicy.constrainedOrigin(
                  for: containerView.frame,
                  visibleFrames: host.geometryProvider.visibleFrames
              )
        else { return }
        containerView.setFrameOrigin(origin)
    }

    private func animate(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        changes: @escaping @MainActor () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = timingFunction
                changes()
            } completionHandler: {
                continuation.resume()
            }
        }
    }
}

@MainActor
final class PresentationHostCoordinator: PresentationHosting, PresentationGeometryProviding {
    private struct WeakHandle {
        weak var value: PresentationItemHandle?
    }

    private struct ItemDescriptor {
        let kind: PresentationItemKind
        let title: String
        let onMove: (NSPoint) -> Void
        let onCancel: (() -> Void)?
    }

    private var activeHost: any PresentationHosting
    private var handles: [WeakHandle] = []

    init(initialHost: any PresentationHosting) {
        activeHost = initialHost
    }

    var geometryProvider: any PresentationGeometryProviding {
        self
    }

    var screens: [PresentationScreenGeometry] {
        activeHost.geometryProvider.screens
    }

    var pointerPosition: CGPoint {
        activeHost.geometryProvider.pointerPosition
    }

    var coordinateSpace: PresentationCoordinateSpace {
        activeHost.geometryProvider.coordinateSpace
    }

    func makeItem(
        kind: PresentationItemKind,
        title: String,
        onMove: @escaping (NSPoint) -> Void,
        onCancel: (() -> Void)?
    ) -> any PresentationItem {
        let handle = PresentationItemHandle(descriptor: ItemDescriptor(
            kind: kind,
            title: title,
            onMove: onMove,
            onCancel: onCancel
        ))
        handle.attach(to: activeHost)
        handles.append(WeakHandle(value: handle))
        return handle
    }

    func switchHost(to newHost: any PresentationHosting) {
        let oldHost = activeHost
        let oldFrame = oldHost.geometryProvider.mainScreen?.visibleFrame
        let oldCoordinateSpace = oldHost.geometryProvider.coordinateSpace
        let newFrame = newHost.geometryProvider.mainScreen?.visibleFrame
        let newCoordinateSpace = newHost.geometryProvider.coordinateSpace
        activeHost = newHost
        handles = handles.filter { $0.value != nil }
        for handle in handles.compactMap(\.value) {
            handle.rehost(
                to: newHost,
                from: oldFrame,
                oldCoordinateSpace: oldCoordinateSpace,
                to: newFrame,
                newCoordinateSpace: newCoordinateSpace
            )
        }
        withExtendedLifetime(oldHost) {}
    }

    func setTitle(_ title: String) {
        activeHost.setTitle(title)
    }

    private final class PresentationItemHandle: PresentationItem {
        private let descriptor: ItemDescriptor
        private var backing: (any PresentationItem)?
        private var isRehosting = false
        private var placementPolicy = FloatingWindowPlacementPolicy.free
        private var staysOnTop = true
        private var originsByCoordinateSpace: [PresentationCoordinateSpace: NSPoint] = [:]

        init(descriptor: ItemDescriptor) {
            self.descriptor = descriptor
        }

        var frame: NSRect {
            backing?.frame ?? .zero
        }

        var isVisible: Bool {
            backing?.isVisible ?? false
        }

        var contentView: NSView? {
            get { backing?.contentView }
            set { backing?.contentView = newValue }
        }

        var contentSize: NSSize {
            backing?.contentSize ?? .zero
        }

        var alphaValue: CGFloat {
            get { backing?.alphaValue ?? 0 }
            set { backing?.alphaValue = newValue }
        }

        var captureWindowNumber: Int? {
            backing?.captureWindowNumber
        }

        func attach(to host: any PresentationHosting) {
            backing = makeBacking(host: host)
        }

        func rehost(
            to host: any PresentationHosting,
            from oldVisibleFrame: NSRect?,
            oldCoordinateSpace: PresentationCoordinateSpace,
            to newVisibleFrame: NSRect?,
            newCoordinateSpace: PresentationCoordinateSpace
        ) {
            guard let oldBacking = backing else {
                attach(to: host)
                return
            }
            isRehosting = true

            let oldFrame = oldBacking.frame
            originsByCoordinateSpace[oldCoordinateSpace] = oldFrame.origin
            let wasVisible = oldBacking.isVisible
            let contentView = oldBacking.contentView
            let alpha = oldBacking.alphaValue
            oldBacking.contentView = nil
            oldBacking.discard()

            let newBacking = makeBacking(host: host)
            backing = newBacking
            newBacking.contentView = contentView
            newBacking.setContentSize(oldFrame.size)
            newBacking.setPlacementPolicy(placementPolicy)
            newBacking.setStaysOnTop(staysOnTop)
            newBacking.alphaValue = alpha
            let destinationOrigin = originsByCoordinateSpace[newCoordinateSpace] ?? mappedOrigin(
                for: oldFrame,
                from: oldVisibleFrame,
                to: newVisibleFrame
            )
            newBacking.setFrameOrigin(destinationOrigin)
            let appliedOrigin = newBacking.frame.origin
            originsByCoordinateSpace[newCoordinateSpace] = appliedOrigin
            if wasVisible {
                newBacking.show(activating: false)
            }
            isRehosting = false
            descriptor.onMove(appliedOrigin)
        }

        func setContentSize(_ size: NSSize) {
            backing?.setContentSize(size)
        }

        func setFrameOrigin(_ origin: NSPoint) {
            backing?.setFrameOrigin(origin)
        }

        func center() {
            backing?.center()
        }

        func show(activating: Bool) {
            backing?.show(activating: activating)
        }

        func hide() {
            backing?.hide()
        }

        func setStaysOnTop(_ staysOnTop: Bool) {
            self.staysOnTop = staysOnTop
            backing?.setStaysOnTop(staysOnTop)
        }

        func setPlacementPolicy(_ policy: FloatingWindowPlacementPolicy) {
            placementPolicy = policy
            backing?.setPlacementPolicy(policy)
        }

        func orderAbove(_ other: any PresentationItem) {
            guard let other = other as? PresentationItemHandle,
                  let otherBacking = other.backing
            else { return }
            backing?.orderAbove(otherBacking)
        }

        func animateFrameOrigin(_ origin: NSPoint, duration: TimeInterval) async {
            await backing?.animateFrameOrigin(origin, duration: duration)
        }

        func animateContentSize(_ size: NSSize, duration: TimeInterval) async {
            await backing?.animateContentSize(size, duration: duration)
        }

        func animateAlphaValue(_ alpha: CGFloat, duration: TimeInterval) async {
            await backing?.animateAlphaValue(alpha, duration: duration)
        }

        func discard() {
            backing?.discard()
            backing = nil
        }

        private func makeBacking(host: any PresentationHosting) -> any PresentationItem {
            let coordinateSpace = host.geometryProvider.coordinateSpace
            return host.makeItem(
                kind: descriptor.kind,
                title: descriptor.title,
                onMove: { [weak self] origin in
                    guard let self, !isRehosting else { return }
                    originsByCoordinateSpace[coordinateSpace] = origin
                    descriptor.onMove(origin)
                },
                onCancel: descriptor.onCancel
            )
        }

        private func mappedOrigin(
            for itemFrame: NSRect,
            from oldVisibleFrame: NSRect?,
            to newVisibleFrame: NSRect?
        ) -> NSPoint {
            guard let oldVisibleFrame, let newVisibleFrame else { return itemFrame.origin }
            let normalizedX = oldVisibleFrame.width > 0
                ? (itemFrame.midX - oldVisibleFrame.minX) / oldVisibleFrame.width
                : 0.5
            let normalizedY = oldVisibleFrame.height > 0
                ? (itemFrame.midY - oldVisibleFrame.minY) / oldVisibleFrame.height
                : 0.5
            return NSPoint(
                x: newVisibleFrame.minX + min(max(normalizedX, 0), 1) * newVisibleFrame.width
                    - itemFrame.width / 2,
                y: newVisibleFrame.minY + min(max(normalizedY, 0), 1) * newVisibleFrame.height
                    - itemFrame.height / 2
            )
        }
    }
}

public enum GhostWindowMode: String, CaseIterable, Sendable {
    case off
    case shared
    case perGhost

    public static func launchOverride(
        in arguments: [String],
        previousLayout: GhostWindowMode = .shared
    ) -> GhostWindowMode? {
        for argument in arguments {
            if argument == "--windowmode" {
                return previousLayout == .off ? .shared : previousLayout
            }
            guard argument.hasPrefix("--windowmode=") else { continue }
            switch argument.dropFirst("--windowmode=".count).lowercased() {
            case "shared":
                return .shared
            case "perghost":
                return .perGhost
            default:
                return nil
            }
        }
        return nil
    }
}

@MainActor
public final class GhostPresentationSession {
    public private(set) var title: String
    public private(set) var identifier: String
    let presentationHost: PresentationHostCoordinator
    private weak var coordinator: PresentationCoordinator?

    public var geometryProvider: any PresentationGeometryProviding {
        presentationHost
    }

    fileprivate init(
        title: String,
        identifier: String,
        presentationHost: PresentationHostCoordinator,
        coordinator: PresentationCoordinator
    ) {
        self.title = title
        self.identifier = identifier
        self.presentationHost = presentationHost
        self.coordinator = coordinator
    }

    public func setTitle(_ title: String) {
        self.title = title
        coordinator?.sessionTitleDidChange(self)
    }

    public func setIdentifier(_ identifier: String) {
        guard self.identifier != identifier else { return }
        self.identifier = identifier
        coordinator?.sessionIdentifierDidChange(self)
    }
}

@MainActor
public final class PresentationCoordinator {
    private struct WeakSession {
        weak var value: GhostPresentationSession?
    }

    public private(set) var mode: GhostWindowMode
    public var onModeRequest: (@MainActor (GhostWindowMode) -> Void)?
    private let systemGeometry: any PresentationGeometryProviding
    private let stageStateStore: WindowModeStageStateStore
    private var sharedHost: WindowModePresentationHost?
    private var sessions: [WeakSession] = []

    public init(
        mode: GhostWindowMode = .off,
        systemGeometry: any PresentationGeometryProviding = SystemPresentationGeometryProvider(),
        defaults: UserDefaults = .standard
    ) {
        self.mode = mode
        self.systemGeometry = systemGeometry
        stageStateStore = WindowModeStageStateStore(defaults: defaults)
    }

    public func makeSession(title: String, identifier: String? = nil) -> GhostPresentationSession {
        let identifier = identifier ?? title
        let session = GhostPresentationSession(
            title: title,
            identifier: identifier,
            presentationHost: PresentationHostCoordinator(initialHost: host(
                for: title,
                identifier: identifier
            )),
            coordinator: self
        )
        sessions.append(WeakSession(value: session))
        return session
    }

    public func setMode(_ mode: GhostWindowMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        if mode != .shared {
            sharedHost = nil
        }
        sessions = sessions.filter { $0.value != nil }
        for session in sessions.compactMap(\.value) {
            session.presentationHost.switchHost(to: host(
                for: session.title,
                identifier: session.identifier
            ))
        }
    }

    fileprivate func sessionTitleDidChange(_ session: GhostPresentationSession) {
        guard mode == .perGhost else { return }
        session.presentationHost.setTitle(session.title)
    }

    fileprivate func sessionIdentifierDidChange(_ session: GhostPresentationSession) {
        guard mode == .perGhost else { return }
        session.presentationHost.switchHost(to: host(
            for: session.title,
            identifier: session.identifier
        ))
    }

    private func host(for title: String, identifier: String) -> any PresentationHosting {
        switch mode {
        case .off:
            DesktopPresentationHost(geometryProvider: systemGeometry)
        case .shared:
            sharedWindowModeHost()
        case .perGhost:
            WindowModePresentationHost(
                title: title,
                mode: .perGhost,
                onModeRequest: { [weak self] mode in self?.requestMode(mode) },
                stateStore: stageStateStore,
                stateIdentifier: "per-ghost:\(identifier)"
            )
        }
    }

    private func sharedWindowModeHost() -> WindowModePresentationHost {
        if let sharedHost {
            return sharedHost
        }
        let host = WindowModePresentationHost(
            title: "Utatane",
            mode: .shared,
            onModeRequest: { [weak self] mode in self?.requestMode(mode) },
            stateStore: stageStateStore,
            stateIdentifier: "shared"
        )
        sharedHost = host
        return host
    }

    private func requestMode(_ mode: GhostWindowMode) {
        if let onModeRequest {
            onModeRequest(mode)
        } else {
            setMode(mode)
        }
    }
}

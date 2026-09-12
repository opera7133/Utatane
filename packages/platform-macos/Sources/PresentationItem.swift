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

@MainActor
final class WindowModePresentationHost: PresentationHosting {
    let window: NSWindow
    let rootView: NSView
    let geometryProvider: any PresentationGeometryProviding
    private var items: [WindowModePresentationItem] = []

    init(contentSize: NSSize = NSSize(width: 960, height: 540), title: String = "Utatane") {
        let window = WindowModeStageWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.title = title
        window.contentView = rootView
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        self.rootView = rootView
        geometryProvider = WindowModePresentationGeometryProvider(window: window, rootView: rootView)
    }

    var itemCount: Int {
        items.count
    }

    func setTitle(_ title: String) {
        window.title = title
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
private final class WindowModeStageWindow: NSWindow {
    var cancelHandlers: [() -> Void] = []

    override func cancelOperation(_ sender: Any?) {
        if cancelHandlers.isEmpty {
            super.cancelOperation(sender)
        } else {
            cancelHandlers.forEach { $0() }
        }
    }
}

@MainActor
private final class WindowModePresentationGeometryProvider: PresentationGeometryProviding {
    private weak var window: NSWindow?
    private weak var rootView: NSView?

    init(window: NSWindow, rootView: NSView) {
        self.window = window
        self.rootView = rootView
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

    var coordinateSpace: PresentationCoordinateSpace {
        .windowMode
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
        let oldFrame = activeHost.geometryProvider.mainScreen?.visibleFrame
        let newFrame = newHost.geometryProvider.mainScreen?.visibleFrame
        activeHost = newHost
        handles = handles.filter { $0.value != nil }
        for handle in handles.compactMap(\.value) {
            handle.rehost(to: newHost, from: oldFrame, to: newFrame)
        }
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
            to newVisibleFrame: NSRect?
        ) {
            guard let oldBacking = backing else {
                attach(to: host)
                return
            }
            isRehosting = true
            defer { isRehosting = false }

            let oldFrame = oldBacking.frame
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
            newBacking.setFrameOrigin(mappedOrigin(
                for: oldFrame,
                from: oldVisibleFrame,
                to: newVisibleFrame
            ))
            if wasVisible {
                newBacking.show(activating: false)
            }
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
            host.makeItem(
                kind: descriptor.kind,
                title: descriptor.title,
                onMove: { [weak self] origin in
                    guard let self, !isRehosting else { return }
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
            let oldTravelX = max(0, oldVisibleFrame.width - itemFrame.width)
            let oldTravelY = max(0, oldVisibleFrame.height - itemFrame.height)
            let normalizedX = oldTravelX > 0 ? (itemFrame.minX - oldVisibleFrame.minX) / oldTravelX : 0.5
            let normalizedY = oldTravelY > 0 ? (itemFrame.minY - oldVisibleFrame.minY) / oldTravelY : 0.5
            let newTravelX = max(0, newVisibleFrame.width - itemFrame.width)
            let newTravelY = max(0, newVisibleFrame.height - itemFrame.height)
            return NSPoint(
                x: newVisibleFrame.minX + min(max(normalizedX, 0), 1) * newTravelX,
                y: newVisibleFrame.minY + min(max(normalizedY, 0), 1) * newTravelY
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
    let presentationHost: PresentationHostCoordinator
    private weak var coordinator: PresentationCoordinator?

    public var geometryProvider: any PresentationGeometryProviding {
        presentationHost
    }

    fileprivate init(
        title: String,
        presentationHost: PresentationHostCoordinator,
        coordinator: PresentationCoordinator
    ) {
        self.title = title
        self.presentationHost = presentationHost
        self.coordinator = coordinator
    }

    public func setTitle(_ title: String) {
        self.title = title
        coordinator?.sessionTitleDidChange(self)
    }
}

@MainActor
public final class PresentationCoordinator {
    private struct WeakSession {
        weak var value: GhostPresentationSession?
    }

    public private(set) var mode: GhostWindowMode
    private let systemGeometry: any PresentationGeometryProviding
    private var sharedHost: WindowModePresentationHost?
    private var sessions: [WeakSession] = []

    public init(
        mode: GhostWindowMode = .off,
        systemGeometry: any PresentationGeometryProviding = SystemPresentationGeometryProvider()
    ) {
        self.mode = mode
        self.systemGeometry = systemGeometry
    }

    public func makeSession(title: String) -> GhostPresentationSession {
        let session = GhostPresentationSession(
            title: title,
            presentationHost: PresentationHostCoordinator(initialHost: host(for: title)),
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
            session.presentationHost.switchHost(to: host(for: session.title))
        }
    }

    fileprivate func sessionTitleDidChange(_ session: GhostPresentationSession) {
        guard mode == .perGhost else { return }
        session.presentationHost.setTitle(session.title)
    }

    private func host(for title: String) -> any PresentationHosting {
        switch mode {
        case .off:
            DesktopPresentationHost(geometryProvider: systemGeometry)
        case .shared:
            sharedWindowModeHost()
        case .perGhost:
            WindowModePresentationHost(title: title)
        }
    }

    private func sharedWindowModeHost() -> WindowModePresentationHost {
        if let sharedHost {
            return sharedHost
        }
        let host = WindowModePresentationHost(title: "Utatane")
        sharedHost = host
        return host
    }
}

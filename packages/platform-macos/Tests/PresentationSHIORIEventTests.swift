import AppKit
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@Test(arguments: [GhostWindowMode.shared, .perGhost]) @MainActor
func `container resize notifies only sessions on that stage`(mode: GhostWindowMode) async throws {
    let (defaults, _) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let geometry = MutablePresentationGeometryProvider(screens: [
        .init(frame: frame, visibleFrame: frame, bitsPerPixel: 32, scale: 1, isPrimary: true)
    ])
    let coordinator = PresentationCoordinator(mode: mode, systemGeometry: geometry, defaults: defaults)
    let main = coordinator.makeSession(title: "main")
    let called = coordinator.makeSession(title: "called")
    let item = main.presentationHost.makeItem(kind: .surface, title: "surface", onMove: { _, _ in }, onCancel: nil)
    defer { item.discard() }
    let window = try #require(item.captureWindowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
    let root = try #require(window.contentView as? WindowModeStageRootView)
    var mainEvents: [[GhostEvent]] = []
    var calledEvents: [[GhostEvent]] = []
    main.onDisplayChange = { mainEvents.append($0) }
    called.onDisplayChange = { calledEvents.append($0) }

    // Exercise layout without depending on native window size constraints in CI.
    for size in [NSSize(width: 800, height: 600), NSSize(width: 900, height: 700)] {
        root.setFrameSize(size)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
    }
    try await requireEventually { !mainEvents.isEmpty }
    let expected: [GhostEvent] = [
        .shiori(id: "OnDisplayChange", references: [0: "32", 1: "900", 2: "700"]),
        .shiori(id: "OnDisplayChangeEx", references: [0: "update", 1: "0,0,900,700,32,1,unknown,0"])
    ]
    #expect(mainEvents == [expected])
    #expect(calledEvents == (mode == .shared ? [expected] : []))

    root.setSpeechHistoryHeight(180)
    try await requireEventually { mainEvents.count == 2 }
    let withHistory: [GhostEvent] = [
        .shiori(id: "OnDisplayChange", references: [0: "32", 1: "900", 2: "520"]),
        .shiori(id: "OnDisplayChangeEx", references: [0: "update", 1: "0,0,900,520,32,1,unknown,0"])
    ]
    let updates = [expected, withHistory]
    #expect(mainEvents == updates)
    #expect(calledEvents == (mode == .shared ? updates : []))

    let resized = CGRect(x: 0, y: 0, width: 1600, height: 900)
    geometry.update(screens: [.init(frame: resized, visibleFrame: resized, bitsPerPixel: 32, scale: 1, isPrimary: true)])
    coordinator.screenParametersDidChange()
    #expect(mainEvents == updates) // Real monitors do not change virtual screens.

    root.setFrameSize(NSSize(width: 1000, height: 750))
    root.needsLayout = true
    root.layoutSubtreeIfNeeded()
    coordinator.setMode(.off) // A pending callback from the old host must be ignored.
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
    #expect(mainEvents == updates)
    #expect(calledEvents == (mode == .shared ? updates : []))

    geometry.update(screens: [.init(frame: frame, visibleFrame: frame, bitsPerPixel: 32, scale: 1, isPrimary: true)])
    coordinator.screenParametersDidChange()
    coordinator.screenParametersDidChange() // Repeated notifications with unchanged geometry are suppressed.
    #expect(mainEvents.count == 3)
    #expect(calledEvents.last == geometry.displayChangeEvents())
    #expect(calledEvents.count == (mode == .shared ? 3 : 1))
}

@Test @MainActor
func `discarding stage items releases their cancellation handlers`() {
    let stage = WindowModePresentationHost(mode: .shared)
    var currentCancelCount = 0
    let current = stage.makeItem(kind: .surface, title: "current", onMove: { _, _ in }, onCancel: {
        currentCancelCount += 1
    })
    defer { current.discard() }
    for _ in 0 ..< 20 {
        var owner: NSObject? = NSObject()
        weak let weakOwner = owner
        let item = stage.makeItem(kind: .balloon, title: "retired", onMove: { _, _ in }, onCancel: { [owner] in
            _ = owner
            Issue.record("A discarded item received Escape")
        })
        owner = nil
        #expect(weakOwner != nil)
        item.discard()
        #expect(weakOwner == nil)
    }
    stage.window.cancelOperation(nil)
    #expect(currentCancelCount == 1)
}

@Test @MainActor
func `display events distinguish startup and updates in primary screen coordinates`() {
    let main = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let secondary = CGRect(x: -600, y: 800, width: 600, height: 400)
    let geometry = MutablePresentationGeometryProvider(screens: [
        .init(frame: main, visibleFrame: main, bitsPerPixel: 32, scale: 2, isPrimary: true),
        .init(frame: secondary, visibleFrame: secondary, bitsPerPixel: 24, scale: 1, isPrimary: false)
    ])
    #expect(geometry.displayChangeEvents(isInitial: true) == [
        .notification(id: "OnDisplayChange", references: [0: "32", 1: "1200", 2: "800"]),
        .notification(id: "OnDisplayChangeEx", references: [0: "init",
                                                            1: "0,0,1200,800,32,1,unknown,0", 2: "-600,-400,0,0,24,0,unknown,0"])
    ])
    let resized = CGRect(x: 0, y: 0, width: 900, height: 700)
    geometry.update(screens: [.init(frame: resized, visibleFrame: resized, bitsPerPixel: 32, scale: 1, isPrimary: true)])
    #expect(geometry.displayChangeEvents() == [
        .shiori(id: "OnDisplayChange", references: [0: "32", 1: "900", 2: "700"]),
        .shiori(id: "OnDisplayChangeEx", references: [0: "update", 1: "0,0,900,700,32,1,unknown,0"])
    ])
}

@Test @MainActor
func `surface notifications include changed extra scope and unscaled dimensions`() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0.png"))
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let controller = SurfaceWindowController(positionStore: positions)
    defer { controller.resetContent() }
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:]), scope: 2, surfaceID: 0)
    await controller.setRuntimeScale(horizontal: 2, vertical: 2, scope: 2, durationMilliseconds: 0)
    #expect(controller.surfaceChangeEvent(scope: 2, surfaceID: 0) == .notification(id: "OnSurfaceChange", references: [
        0: "-1", 1: "-1", 2: "2,0,40,80"
    ]))
}

@Test @MainActor
func `position reset uses ghost reply and falls back only for empty replies`() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0.png"))
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let geometry = MutablePresentationGeometryProvider(screens: [
        .init(frame: frame, visibleFrame: frame, bitsPerPixel: 32, scale: 1, isPrimary: true)
    ])
    let controller = SurfaceWindowController(positionStore: positions, geometryProvider: geometry)
    defer { controller.resetContent() }
    controller.setPlacement(locksToDesktopBottom: false, keepsOnScreen: true)
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:], surfaceTable: nil, maximumSurfaceWidth: nil, desktopAlignment: .free), surfaceID: 0)
    let original = try #require(controller.windowFrame(for: 0)?.origin)
    let balloons = BalloonWindowController(positionStore: positions, geometryProvider: geometry)
    let player = SakuraScriptPlayer(surfaceWindowController: controller, balloonWindowController: balloons)
    defer { player.cancel() }
    let balloon = makeBalloon(directory: directory)
    for reply in [nil, "", #"\e"#] as [String?] {
        controller.restoreLayoutPresetPositions([0: CGPoint(x: 200, y: 300)])
        let moved = controller.windowFrame(for: 0)?.origin
        #expect(moved != original)
        var received = false
        player.onEmbeddedEvent = { id, arguments in
            #expect(id == "OnResetWindowPos")
            #expect(arguments.isEmpty)
            #expect(controller.windowFrame(for: 0)?.origin == moved)
            received = true
            return reply.map(SakuraScript.init(rawValue:))
        }
        await player.resetWindowPositionsFromMenu(balloon: balloon)
        #expect(received)
        #expect(controller.windowFrame(for: 0)?.origin == (reply == #"\e"# ? moved : original))
    }
    controller.restoreLayoutPresetPositions([0: CGPoint(x: 200, y: 300)])
    let moved = controller.windowFrame(for: 0)?.origin
    player.onEmbeddedEvent = { _, _ in
        player.cancel() // A ghost switch or newer speech invalidates the pending action.
        return nil
    }
    await player.resetWindowPositionsFromMenu(balloon: balloon)
    #expect(controller.windowFrame(for: 0)?.origin == moved)
}

import AppKit
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

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

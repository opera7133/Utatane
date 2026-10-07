import AppKit
import Testing
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@Test @MainActor
func `status tracks locked input and owned SSTP admission`() async throws {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaces = SurfaceWindowController(positionStore: positions)
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    defer { player.cancel(); balloons.resetContent(); surfaces.resetContent() }
    #expect(player.executionStatus.isEmpty)
    var input: CheckedContinuation<SakuraScript?, Never>?
    player.onInputBox = { _ in await withCheckedContinuation { input = $0 } }
    let playback = Task {
        await player.playAndWait(SakuraScript(rawValue: #"\t\![open,inputbox,probe]\e"#), balloon: makeBalloon(directory: FileManager.default.temporaryDirectory))
    }
    try await requireEventually { input != nil }
    #expect(player.executionStatus.contains("talking"))
    #expect(player.executionStatus.contains("timecritical"))
    #expect(player.executionStatus.contains("opening(input)"))
    #expect(!player.acceptsSSTP(owned: false, queues: false))
    #expect(player.acceptsSSTP(owned: true, queues: false))
    #expect(player.acceptsSSTP(owned: false, queues: true))
    input?.resume(returning: nil)
    await playback.value
    #expect(!player.executionStatus.contains("opening"))
    #expect(!player.executionStatus.contains("talking"))
    player.cancel()
    #expect(!player.executionStatus.contains("timecritical"))
}

@Test @MainActor
func `bottom balloon offsets fall back independently through center then generic`() {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let balloons = BalloonWindowController(positionStore: positions)
    balloons.configure(shell: ShellDefinition(directory: FileManager.default.temporaryDirectory, surfaces: [:], surfaceTable: nil, maximumSurfaceWidth: nil, presentationSettings: [
        0: .init(balloonOffsets: .init(x: 1, y: 2, centerX: 30, centerY: 40, bottomY: 50), balloonAlignment: .bottom)
    ]))
    #expect(balloons.effectiveShellOffset(scope: 0, alignment: .bottom) == NSPoint(x: 30, y: 50))
    #expect(balloons.effectiveShellOffset(scope: 0, alignment: .center) == NSPoint(x: 30, y: 40))
    #expect(balloons.effectiveShellOffset(scope: 0, alignment: .left) == NSPoint(x: 1, y: 2))
    #expect(balloons.effectiveShellOffset(scope: 0, alignment: .right) == NSPoint(x: -1, y: 2))
}

@Test @MainActor
func `standard property writes change requested scope and replace sticky groups`() async throws {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for id in [0, 1, 2] {
        try makePNG(width: 4, height: 4).write(to: root.appending(path: "surface\(id).png"))
    }
    let surfaces = SurfaceWindowController(positionStore: positions)
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    defer { player.cancel(); balloons.resetContent(); surfaces.resetContent() }
    try surfaces.show(shell: ShellDefinition(directory: root, surfaces: [:]), defaultSurfaceIDs: [0: 0, 1: 1])
    await player.playAndWait(SakuraScript(rawValue: #"\![set,property,currentghost.scope(1).surface.num,2]\e"#), balloon: makeBalloon(directory: root))
    #expect(surfaces.surfaceID(for: 0) == 0)
    #expect(player.runtimePropertyValue(for: "currentghost.scope(1).surface.num") == "2")
    try player.setRuntimeProperty("2", for: "currentghost.scope(1).seriko.defaultsurface")
    surfaces.resetToDefaultSurfaces()
    #expect(surfaces.surfaceID(for: 1) == 2)
    try player.setRuntimeProperty("0,1;1,2;3,4;5;bad", for: "currentghost.seriko.sticky-window")
    #expect(player.runtimePropertyValue(for: "currentghost.seriko.sticky-window") == "0,1;3,4")
    try player.setRuntimeProperty("6,7", for: "currentghost.seriko.sticky-window")
    #expect(surfaces.stickyWindowGroups == [[6, 7]])
    try player.setRuntimeProperty("", for: "currentghost.seriko.sticky-window")
    #expect(surfaces.stickyWindowGroups.isEmpty)
    #expect(throws: (any Error).self) { try player.setRuntimeProperty("invalid", for: "currentghost.scope(0).surface.num") }
    #expect(try player.setRuntimeProperty("fake", for: "system.os") == false)
}

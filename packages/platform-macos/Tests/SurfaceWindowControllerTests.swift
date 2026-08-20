import AppKit
import Testing
import UtataneBalloon
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@Test func `chooses interaction cursors from collision regions`() {
    #expect(SurfaceCursorStyle(region: nil) == .arrow)
    #expect(SurfaceCursorStyle(region: "Head") == .openHand)
    #expect(SurfaceCursorStyle(region: "Ear1") == .openHand)
    #expect(SurfaceCursorStyle(region: "hair") == .openHand)
    #expect(SurfaceCursorStyle(region: "Mouth") == .pointingHand)
    #expect(SurfaceCursorStyle(region: "MenuButton") == .pointingHand)
}

@Test func `accepts only NAR files dropped on a surface`() {
    let urls = [
        URL(filePath: "/tmp/ghost.nar"),
        URL(filePath: "/tmp/SHELL.NAR"),
        URL(filePath: "/tmp/readme.txt"),
        URL(filePath: "/tmp/not-a-nar")
    ]

    #expect(SurfaceDropPayload.narURLs(from: urls).map(\.lastPathComponent) == [
        "ghost.nar", "SHELL.NAR"
    ])
}

@Test
@MainActor
func `shows scopes in separate side by side windows`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 40, height: 80).write(
        to: directory.appending(path: "surface0000.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 20, height: 30).write(
        to: directory.appending(path: "surface0010.png", directoryHint: .notDirectory)
    )

    let controller = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    try controller.show(shell: shell, scope: 1, surfaceID: 10)
    defer { controller.hideAll() }

    let sakuraFrame = try #require(controller.windowFrame(for: 0))
    let keroFrame = try #require(controller.windowFrame(for: 1))
    #expect(controller.visibleScopes == [0, 1])
    #expect(keroFrame.maxX < sakuraFrame.minX)
    #expect(keroFrame.minY == sakuraFrame.minY)
}

@Test(arguments: ["master", "master2nd"])
func `loads the installed twin shell surfaces`(shellDirectoryName: String) throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let shellDirectory = repositoryRoot.appending(
        path: "Content/Local/Ghosts/twin/shell/\(shellDirectoryName)",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: shellDirectory.path) else { return }
    let loader = ShellLoader()
    let shell = try loader.load(from: shellDirectory)
    #expect(shell.usesSelfAlpha)
    for surfaceID in [0, 10] {
        let hasImage = (try? loader.loadSurface(id: surfaceID, from: shellDirectory)) != nil
        let hasComposite = shell.surfaces[surfaceID]?.elements.isEmpty == false
        #expect(hasImage || hasComposite)
    }
}

@Test
@MainActor
func `renders both installed twin characters with default bindings`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let shellDirectory = repositoryRoot.appending(
        path: "Content/Local/Ghosts/twin/shell/master",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: shellDirectory.path) else { return }
    let shell = try ShellLoader().load(from: shellDirectory)
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let controller = SurfaceWindowController(positionStore: positionStore)
    defer { controller.hideAll() }

    try controller.show(shell: shell, defaultSurfaceIDs: [0: 5, 1: 10000])

    #expect(controller.visibleScopes == [0, 1])
    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 244, height: 450))
    #expect(controller.windowFrame(for: 1)?.size == NSSize(width: 244, height: 450))
}

@Test
@MainActor
func `renders a virtual surface from ordered elements`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 40, height: 80).write(
        to: directory.appending(path: "surface0000.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 10, height: 12).write(
        to: directory.appending(path: "element0005.png", directoryHint: .notDirectory)
    )
    let definition = SurfaceDefinition(
        id: 5,
        elements: [
            SurfaceElement(id: 0, method: "overlay", filename: "surface0000.png", x: 0, y: 0),
            SurfaceElement(id: 1, method: "overlay", filename: "element0005.png", x: 8, y: 10)
        ],
        collisions: [],
        animations: []
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [5: definition])

    try controller.show(shell: shell, scope: 0, surfaceID: 5)
    defer { controller.hideAll() }

    #expect(controller.surfaceID(for: 0) == 5)
    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 40, height: 80))
}

@Test
@MainActor
func `resizes an active surface using its display scale`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0.png"))

    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { controller.hideAll() }

    controller.setDisplayScale(1.5)

    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 60, height: 120))
}

@Test
@MainActor
func `embedded event can restore a hidden surface`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for surfaceID in [0, 5] {
        try makePNG(width: 40, height: 80).write(
            to: directory.appending(path: "surface\(surfaceID).png")
        )
    }
    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: BalloonWindowController(positionStore: positionStore)
    )
    player.onEmbeddedEvent = { id, arguments in
        #expect(id == "OnCallSurface")
        #expect(arguments == ["5"])
        return SakuraScript(rawValue: "\\s[5]")
    }
    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 0,
        originY: 0,
        wordWrapPointX: 0,
        wordWrapPointY: 0,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    await player.playAndWait(
        SakuraScript(rawValue: "\\s[-1]\\![embed,OnCallSurface,5]\\e"),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(surfaceController.visibleScopes == [0])
    #expect(surfaceController.surfaceID(for: 0) == 5)
}

@Test
@MainActor
func `restores a saved floating window position`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let expected = NSPoint(x: 123, y: 456)

    positionStore.save(expected, for: .balloon, scope: 1)

    let restored = positionStore.restoredOrigin(
        for: .balloon,
        scope: 1,
        windowSize: NSSize(width: 100, height: 50),
        screens: []
    )
    #expect(restored == expected)
}

@Test
@MainActor
func `keeps floating window positions separate for each ghost`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let ghostA = URL(filePath: "/ghosts/a", directoryHint: .isDirectory)
    let ghostB = URL(filePath: "/ghosts/b", directoryHint: .isDirectory)

    positionStore.setContentID(ghostA)
    positionStore.save(NSPoint(x: 100, y: 200), for: .surface, scope: 0)
    positionStore.setContentID(ghostB)
    positionStore.save(NSPoint(x: 300, y: 400), for: .surface, scope: 0)

    positionStore.setContentID(ghostA)
    let ghostAOrigin = positionStore.restoredOrigin(
        for: .surface,
        scope: 0,
        windowSize: NSSize(width: 50, height: 50),
        screens: []
    )
    positionStore.setContentID(ghostB)
    let ghostBOrigin = positionStore.restoredOrigin(
        for: .surface,
        scope: 0,
        windowSize: NSSize(width: 50, height: 50),
        screens: []
    )

    #expect(ghostAOrigin == NSPoint(x: 100, y: 200))
    #expect(ghostBOrigin == NSPoint(x: 300, y: 400))
}

@Test
func `surface placement stays on the desktop bottom and inside its screen`() {
    let screen = NSRect(x: 100, y: 40, width: 800, height: 600)
    let frame = NSRect(x: 850, y: 400, width: 200, height: 300)

    let origin = FloatingWindowPlacementPolicy.desktopBottom.constrainedOrigin(
        for: frame,
        visibleFrames: [screen]
    )

    #expect(origin == NSPoint(x: 700, y: 40))
}

@Test
func `surface placement chooses the screen with the largest overlap`() {
    let left = NSRect(x: 0, y: 0, width: 500, height: 500)
    let right = NSRect(x: 500, y: 30, width: 700, height: 600)
    let frame = NSRect(x: 600, y: 200, width: 200, height: 300)

    let origin = FloatingWindowPlacementPolicy.desktopBottom.constrainedOrigin(
        for: frame,
        visibleFrames: [left, right]
    )

    #expect(origin == NSPoint(x: 600, y: 30))
}

@Test
@MainActor
func `keeps every speaker balloon until a completed dialogue is clicked`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 40, height: 80).write(
        to: directory.appending(path: "surface0000.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 20, height: 30).write(
        to: directory.appending(path: "surface0010.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 25, height: 35).write(
        to: directory.appending(path: "surface0200.png", directoryHint: .notDirectory)
    )
    let balloonImage = try makePNG(width: 120, height: 80)
    try balloonImage.write(to: directory.appending(path: "balloons0.png", directoryHint: .notDirectory))
    try balloonImage.write(to: directory.appending(path: "balloonk0.png", directoryHint: .notDirectory))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 10)
    try surfaceController.show(shell: shell, scope: 2, surfaceID: 200)
    defer { surfaceController.hideAll() }

    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 4,
        originY: 4,
        wordWrapPointX: -4,
        wordWrapPointY: -4,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    await player.playAndWait(
        SakuraScript(rawValue: "\\0Sakura\\1Kero\\p[2]Charlie\\e"),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )
    #expect(balloonController.visibleScopes == [0, 1, 2])

    player.advance()
    #expect(balloonController.visibleScopes.isEmpty)
}

@Test
@MainActor
func `does not show a balloon until its scope has text`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for surfaceID in [0, 5, 10] {
        try makePNG(width: 30, height: 40).write(
            to: directory.appending(
                path: String(format: "surface%04d.png", surfaceID),
                directoryHint: .notDirectory
            )
        )
    }
    let balloonImage = try makePNG(width: 120, height: 80)
    try balloonImage.write(to: directory.appending(path: "balloons0.png"))
    try balloonImage.write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        defaultSurfaceIDs: [0: 0, 1: 10]
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let balloon = makeBalloon(directory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: "\\u\\s[10]\\h\\s[5]hello\\e"),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.visibleScopes == [0])
}

@Test
@MainActor
func `long balloon text scrolls and follows its bottom`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(
        to: directory.appending(path: "balloons0.png", directoryHint: .notDirectory)
    )

    let controller = BalloonWindowController(positionStore: positionStore)
    try controller.show(
        balloon: makeBalloon(directory: directory),
        text: (0 ..< 20).map { "line \($0)" }.joined(separator: "\n"),
        near: NSRect(x: 500, y: 100, width: 40, height: 80)
    )
    defer { controller.hideAll() }

    #expect(controller.isTextScrollable(scope: 0))
    #expect(controller.isTextAtBottom(scope: 0))
}

@Test
@MainActor
func `dismisses balloons without discarding dialogue surfaces`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for surfaceID in [0, 1, 10, 11] {
        try makePNG(width: 30, height: 40).write(
            to: directory.appending(
                path: String(format: "surface%04d.png", surfaceID),
                directoryHint: .notDirectory
            )
        )
    }
    let balloonImage = try makePNG(width: 120, height: 80)
    try balloonImage.write(to: directory.appending(path: "balloons0.png", directoryHint: .notDirectory))
    try balloonImage.write(to: directory.appending(path: "balloonk0.png", directoryHint: .notDirectory))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 10)
    defer { surfaceController.hideAll() }

    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController,
        postDialogueDismissalMilliseconds: 20
    )
    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 4,
        originY: 4,
        wordWrapPointX: -4,
        wordWrapPointY: -4,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    player.play(
        SakuraScript(rawValue: "\\0\\s[1]Sakura\\1\\s[11]Kero\\e"),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )
    for _ in 0 ..< 100 where surfaceController.surfaceID(for: 0) != 1 {
        try await Task.sleep(for: .milliseconds(10))
    }
    for _ in 0 ..< 100 where !balloonController.visibleScopes.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(balloonController.visibleScopes.isEmpty)
    #expect(surfaceController.surfaceID(for: 0) == 1)
    #expect(surfaceController.surfaceID(for: 1) == 11)
}

private func makePNG(width: Int, height: Int) throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ))
    let color = NSColor(deviceRed: 0.25, green: 0.25, blue: 0.25, alpha: 1)
    for y in 0 ..< height {
        for x in 0 ..< width {
            bitmap.setColor(color, atX: x, y: y)
        }
    }
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private func makeBalloon(directory: URL) -> BalloonDefinition {
    BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 4,
        originY: 4,
        wordWrapPointX: -4,
        wordWrapPointY: -4,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )
}

@MainActor
private func makePositionStore() -> (UserDefaults, WindowPositionStore) {
    let suiteName = "dev.utatane.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(suiteName, forKey: "test-suite-name")
    return (defaults, WindowPositionStore(defaults: defaults, namespace: "positions"))
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "test-suite-name")!
}

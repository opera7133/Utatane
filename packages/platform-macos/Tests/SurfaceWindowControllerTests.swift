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

@Test func `head strokes emit at a finer movement interval`() {
    #expect(SurfaceStrokeEventPolicy.minimumDistance(for: "Head") == 2)
    #expect(SurfaceStrokeEventPolicy.minimumDistance(for: "head") == 2)
    #expect(SurfaceStrokeEventPolicy.minimumDistance(for: "Hair") == 4)
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
func `base animation pattern temporarily replaces the whole surface`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 2, height: 2, color: .red).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 2, height: 2, color: .green).write(to: directory.appending(path: "surface6.png"))
    let animation = SurfaceAnimation(
        id: 0,
        name: "blink",
        interval: "sometimes",
        patterns: [SurfaceAnimationPattern(
            order: 0,
            method: "base",
            surfaceID: 6,
            waitMilliseconds: 200,
            x: 0,
            y: 0
        )]
    )
    let talkAnimation = SurfaceAnimation(
        id: 1,
        name: "mouth",
        interval: "talk",
        patterns: [SurfaceAnimationPattern(
            order: 0,
            method: "base",
            surfaceID: 6,
            waitMilliseconds: 100,
            x: 0,
            y: 0
        )]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [animation, talkAnimation]
        )],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }
    let initialImage = try #require(controller.renderedImage(for: 0))

    controller.setRepaintLocked(true, scope: 0)
    controller.playAnimation(identifier: "blink", scope: 0)
    try await Task.sleep(for: .milliseconds(50))
    #expect(controller.renderedImage(for: 0) === initialImage)
    controller.setRepaintLocked(false, scope: 0)

    let image = try #require(controller.renderedImage(for: 0))
    #expect(image !== initialImage)

    let startedAt = ProcessInfo.processInfo.systemUptime
    await controller.playAnimationAndWait(identifier: "blink", scope: 0)
    #expect(ProcessInfo.processInfo.systemUptime - startedAt >= 0.18)
    #expect(controller.renderedImage(for: 0) === initialImage)

    controller.playAnimation(id: 0, minimumFrameDurationMilliseconds: 1000)
    try await Task.sleep(for: .milliseconds(50))
    let waitStartedAt = ProcessInfo.processInfo.systemUptime
    let waitTask = Task { @MainActor in
        await controller.waitForAnimation(id: 0)
    }
    controller.stopAnimation(id: 0)
    await waitTask.value
    #expect(ProcessInfo.processInfo.systemUptime - waitStartedAt < 0.5)
    #expect(controller.renderedImage(for: 0) === initialImage)

    controller.playAnimation(id: 0)
    try await Task.sleep(for: .milliseconds(50))
    controller.pauseAnimation(id: 0)
    let pausedImage = try #require(controller.renderedImage(for: 0))
    try await Task.sleep(for: .milliseconds(250))
    #expect(controller.renderedImage(for: 0) === pausedImage)
    controller.resumeAnimation(id: 0)
    await controller.waitForAnimation(id: 0)
    #expect(controller.renderedImage(for: 0) === initialImage)

    #expect(controller.playTalkAnimation(scope: 0))
    #expect(!controller.playTalkAnimation(scope: 0))
    await controller.waitForAnimation(id: 1, scope: 0)
    #expect(controller.renderedImage(for: 0) === initialImage)
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
func `changes a surface alpha immediately and over time`() async throws {
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

    await controller.setAlpha(0.5, scope: 0)
    #expect(controller.alpha(for: 0) == 0.5)
    await controller.setAlpha(0.75, scope: 0, durationMilliseconds: 20)
    #expect(controller.alpha(for: 0) == 0.75)
    await controller.setAlpha(nil, scope: 0)
    #expect(controller.alpha(for: 0) == 0.75)
}

@Test
@MainActor
func `scales and flips a surface independently on each axis`() async throws {
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

    await controller.setRuntimeScale(horizontal: -0.5, vertical: 1.5, scope: 0)
    #expect(controller.runtimeScale(for: 0) == NSSize(width: -0.5, height: 1.5))
    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 20, height: 120))

    await controller.setRuntimeScale(
        horizontal: 1,
        vertical: 1,
        scope: 0,
        durationMilliseconds: 20
    )
    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 40, height: 80))
}

@Test
@MainActor
func `renders synchronized text and line breaks in both scopes`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0001.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 1)
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\0前\_s同期\n\_s後\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "前同期\n後")
    #expect(balloonController.textAndLinks(for: 1)?.0 == "同期\n")
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
func `runs input box and asynchronous HTTP commands`() async {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let player = SakuraScriptPlayer(
        surfaceWindowController: SurfaceWindowController(positionStore: positionStore),
        balloonWindowController: BalloonWindowController(positionStore: positionStore)
    )
    var calls: [String] = []
    player.onInputBox = { id, timeout, initialValue in
        calls.append("input:\(id):\(timeout ?? -1):\(initialValue)")
        return nil
    }
    player.onHTTP = { request in
        calls.append("http:\(request.method):\(request.url):\(request.eventID ?? "")")
        return nil
    }
    let balloon = BalloonDefinition(
        directory: FileManager.default.temporaryDirectory,
        name: "test",
        originX: 0,
        originY: 0,
        wordWrapPointX: 0,
        wordWrapPointY: 0,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\![open,inputbox,OnInput,0,初期値]\![execute,http-get,https://example.com/data,--async=OnLoaded]\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(calls == [
        "input:OnInput:0:初期値",
        "http:GET:https://example.com/data:OnLoaded"
    ])
}

@Test
@MainActor
func `bind command switches exclusive dressup parts and sends events`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))

    let coat = ShellBindGroup(id: 10, category: "服", part: "コート")
    let hoodie = ShellBindGroup(id: 11, category: "服", part: "パーカー")
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [:],
        defaultBindGroups: [0: [10]],
        bindGroups: [0: [10: coat, 11: hoodie]],
        bindOptions: [0: ["服": ShellBindOptions(mustSelect: true)]]
    )
    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    defer { surfaceController.hideAll() }
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: BalloonWindowController(positionStore: positionStore)
    )
    var events: [(String, [String])] = []
    player.onEmbeddedEvent = { id, arguments in
        events.append((id, arguments))
        return nil
    }
    let balloon = makeBalloon(directory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"\![bind,服,パーカー,1]\![bind-noevent,服,コート,1]\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    let info = surfaceController.dressupInfo()
    #expect(info.first(where: { $0.group.id == 10 })?.enabled == true)
    #expect(info.first(where: { $0.group.id == 11 })?.enabled == false)
    #expect(events.map(\.0) == ["OnDressupChanged", "OnDressupChanged", "OnNotifyDressupInfo"])
    #expect(events[0].1 == ["0", "コート", "0", "服", "script"])
    #expect(events[1].1 == ["0", "パーカー", "1", "服", "script"])
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
@MainActor
func `removes a saved floating window position`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    positionStore.save(NSPoint(x: 100, y: 200), for: .surface, scope: 3)

    positionStore.remove(for: .surface, scope: 3)

    #expect(positionStore.restoredOrigin(
        for: .surface,
        scope: 3,
        windowSize: NSSize(width: 50, height: 50),
        screens: []
    ) == nil)
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
func `surface placement supports every desktop edge`() {
    let screen = NSRect(x: 100, y: 40, width: 800, height: 600)
    let frame = NSRect(x: 300, y: 200, width: 200, height: 300)

    #expect(FloatingWindowPlacementPolicy(edge: .top, keepsOnScreen: true)
        .constrainedOrigin(for: frame, visibleFrames: [screen]) == NSPoint(x: 300, y: 340))
    #expect(FloatingWindowPlacementPolicy(edge: .bottom, keepsOnScreen: true)
        .constrainedOrigin(for: frame, visibleFrames: [screen]) == NSPoint(x: 300, y: 40))
    #expect(FloatingWindowPlacementPolicy(edge: .left, keepsOnScreen: true)
        .constrainedOrigin(for: frame, visibleFrames: [screen]) == NSPoint(x: 100, y: 200))
    #expect(FloatingWindowPlacementPolicy(edge: .right, keepsOnScreen: true)
        .constrainedOrigin(for: frame, visibleFrames: [screen]) == NSPoint(x: 700, y: 200))
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
func `changes balloon surface before and during dialogue`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons2.png"))
    try makePNG(width: 140, height: 90).write(to: directory.appending(path: "balloons3.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\b2hello\b[3]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.style(for: 0) == 3)
    #expect(balloonController.windowFrame(for: 0)?.size == NSSize(width: 140, height: 90))
}

@Test
@MainActor
func `clears dialogue text in every active scope`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0001.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 1)
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\0さくら\1うにゅう\C\0後\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "後")
    #expect(balloonController.textAndLinks(for: 1)?.0 == "")
}

@Test
@MainActor
func `partially clears characters and lines`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"abcdef\c[char,2]X\none\ntwo\nthree\c[line,1]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "abcdX\none\ntwo\n")
}

@Test
@MainActor
func `waits until elapsed playback time and resets the precise wait clock`() async {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let player = SakuraScriptPlayer(
        surfaceWindowController: SurfaceWindowController(positionStore: positionStore),
        balloonWindowController: BalloonWindowController(positionStore: positionStore)
    )
    let startedAt = Date()

    await player.playAndWait(
        SakuraScript(rawValue: #"\__w[80]\__w[clear]\__w[80]\e"#),
        balloon: makeBalloon(directory: FileManager.default.temporaryDirectory),
        characterDelayMilliseconds: 0
    )

    #expect(Date().timeIntervalSince(startedAt) >= 0.14)
}

@Test
@MainActor
func `renders SakuraScript font styles by text range`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try FileManager.default.copyItem(
        at: URL(fileURLWithPath: "/System/Library/Fonts/Menlo.ttc"),
        to: directory.appending(path: "custom.ttc")
    )

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\f[valign,bottom]A\f[color,#ff0000]B\f[bold,1]C\f[underline,true]D\f[sub,1]E\f[sup,1]F\f[sup,0]G\f[default]H\f[shadowcolor,#ffff00]I\f[shadowstyle,outline]J\f[shadowcolor,none]K\f[outline,true]L\f[outline,false]MN\f[align,right]O\n[half]P\f[name,custom.ttc]\f[height,large]Q\f[height,smaller]R\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let red = try #require(balloonController.textAttributes(at: 1, scope: 0)?[.foregroundColor] as? NSColor)
    #expect(red.redComponent > 0.9)
    let boldFont = try #require(balloonController.textAttributes(at: 2, scope: 0)?[.font] as? NSFont)
    #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
    #expect(balloonController.textAttributes(at: 3, scope: 0)?[.underlineStyle] as? Int == 1)
    let subOffset = try #require(balloonController.textAttributes(at: 4, scope: 0)?[.baselineOffset] as? CGFloat)
    let supOffset = try #require(balloonController.textAttributes(at: 5, scope: 0)?[.baselineOffset] as? CGFloat)
    #expect(subOffset < 0)
    #expect(supOffset > 0)
    #expect(balloonController.textAttributes(at: 6, scope: 0)?[.baselineOffset] == nil)
    #expect(balloonController.textAttributes(at: 7, scope: 0)?[.underlineStyle] == nil)
    let shadow = try #require(balloonController.textAttributes(at: 8, scope: 0)?[.shadow] as? NSShadow)
    #expect(shadow.shadowColor != nil)
    #expect(balloonController.textAttributes(at: 9, scope: 0)?[.strokeWidth] as? Int == -3)
    #expect(balloonController.textAttributes(at: 10, scope: 0)?[.shadow] == nil)
    #expect(balloonController.textAttributes(at: 11, scope: 0)?[.strokeWidth] as? Int == 3)
    #expect(balloonController.textAttributes(at: 12, scope: 0)?[.strokeWidth] == nil)
    let aligned = try #require(
        balloonController.textAttributes(at: 13, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(aligned.alignment == .right)
    let halfLine = try #require(
        balloonController.textAttributes(at: 14, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(abs(halfLine.minimumLineHeight - 7) < 0.1)
    #expect(balloonController.textAttributes(at: 16, scope: 0)?[.paragraphStyle] == nil)
    let largeFont = try #require(balloonController.textAttributes(at: 17, scope: 0)?[.font] as? NSFont)
    let smallerFont = try #require(balloonController.textAttributes(at: 18, scope: 0)?[.font] as? NSFont)
    #expect(largeFont.fontName.contains("Menlo"))
    #expect(abs(largeFont.pointSize - 16.8) < 0.1)
    #expect(abs(smallerFont.pointSize - 14) < 0.1)
}

@Test
@MainActor
func `renders an extended choice and appends its automatic newline`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\__q[OnSelect,arg]選択肢\__q次\f[anchor.font.color,#00ff00]\_a[OnAnchor]錨\_a\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let content = try #require(balloonController.textAndLinks(for: 0))
    #expect(content.0 == "選択肢\n次錨")
    #expect(content.1 == [
        BalloonTextLink(
            range: NSRange(location: 0, length: 3),
            id: "OnSelect",
            arguments: ["arg"]
        ),
        BalloonTextLink(
            range: NSRange(location: 5, length: 1),
            id: "OnAnchor",
            arguments: [],
            kind: .anchor,
            fontColor: BalloonColor(red: 0, green: 255, blue: 0)
        )
    ])
    let anchorColor = try #require(
        balloonController.textAttributes(at: 5, scope: 0)?[.foregroundColor] as? NSColor
    )
    #expect(anchorColor.greenComponent > 0.9)
}

@Test
@MainActor
func `runs a script choice directly without dispatching a SHIORI choice`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var dispatchedChoice = false
    player.onChoice = { _, _ in dispatchedChoice = true }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[実行,script:\0直接実行\e]"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    let initial = try #require(balloonController.textAndLinks(for: 0))
    #expect(initial.1.first?.id == #"script:\0直接実行\e"#)

    balloonController.onLinkClick?(initial.1[0].id, initial.1[0].arguments)
    for _ in 0 ..< 100 where balloonController.textAndLinks(for: 0)?.0 != "直接実行" {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(balloonController.textAndLinks(for: 0)?.0 == "直接実行")
    #expect(!dispatchedChoice)
}

@Test
@MainActor
func `expands environment names and replaces the script after raise`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    player.configure(environmentVariables: ["selfname": "さくら"])
    player.onEmbeddedEvent = { id, arguments in
        #expect(id == "OnRaised")
        #expect(arguments == ["arg"])
        return SakuraScript(rawValue: "応答\\e")
    }

    await player.playAndWait(
        SakuraScript(rawValue: #"%selfnameと%meから\![raise,OnRaised,arg]捨てる\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let content = try #require(balloonController.textAndLinks(for: 0))
    #expect(content.0.hasPrefix("さくらと"))
    #expect(content.0.hasSuffix("から応答"))
    #expect(!content.0.contains("%me"))
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

@Test
@MainActor
func `times out choices after playback and dispatches the timeout event`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var timeoutCount = 0
    player.onChoiceTimeout = { timeoutCount += 1 }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[選択,OnSelect]\![set,choicetimeout,20]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    for _ in 0 ..< 100 where timeoutCount == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(timeoutCount == 1)
    #expect(balloonController.visibleScopes.isEmpty)
}

@Test
@MainActor
func `exposes time critical state only until playback ends`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

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

    player.play(
        SakuraScript(rawValue: #"\t\_w[100]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    for _ in 0 ..< 100 where !player.isTimeCritical {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(player.isTimeCritical)
    for _ in 0 ..< 100 where player.isTimeCritical {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!player.isTimeCritical)
}

@Test
@MainActor
func `balloon repaint lock defers content and movement lock tracks state`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let controller = BalloonWindowController(positionStore: positionStore)
    try controller.show(
        balloon: makeBalloon(directory: directory),
        text: "old",
        near: NSRect(x: 500, y: 100, width: 40, height: 80)
    )
    defer { controller.hideAll() }

    controller.setVerticalAlignment(.bottom, scope: 0)
    #expect(try #require(controller.verticalContentInset(scope: 0)) > 0)
    controller.setVerticalAlignment(.top, scope: 0)
    #expect(controller.verticalContentInset(scope: 0) == 0)
    controller.setMarkerText("更新中", scope: 0)
    #expect(controller.markerText(scope: 0) == "更新中")
    #expect(controller.displayedMarkerText(scope: 0) == "更新中")
    controller.setMarkerText("", scope: 0)
    #expect(controller.markerText(scope: 0) == nil)
    #expect(controller.displayedMarkerText(scope: 0) == "")
    controller.setNumber(file: "download.zip", current: "2", maximum: "5", scope: 0)
    #expect(controller.numberText(scope: 0) == "download.zip 2/5")
    controller.setNumber(file: "", current: "", maximum: "", scope: 0)
    #expect(controller.numberText(scope: 0) == nil)
    controller.setOffset(x: 25, y: -10, scope: 0)
    #expect(controller.offset(scope: 0) == NSPoint(x: 25, y: -10))
    controller.resetOffset(scope: 0)
    #expect(controller.offset(scope: 0) == nil)
    controller.setAlignment(.bottom, scope: 0)
    #expect(controller.alignment(scope: 0) == .bottom)

    controller.setRepaintLocked(true, scope: 0)
    controller.updateContent(text: "new", links: [], scope: 0)
    #expect(controller.isRepaintLocked(scope: 0))
    #expect(controller.textAndLinks(for: 0)?.0 == "new")
    #expect(controller.displayedText(for: 0) == "old")

    controller.setRepaintLocked(false, scope: 0)
    #expect(!controller.isRepaintLocked(scope: 0))
    #expect(controller.displayedText(for: 0) == "new")

    controller.setMovementLocked(true, scope: 0)
    #expect(controller.isMovementLocked(scope: 0))
    controller.setMovementLocked(false, scope: 0)
    #expect(!controller.isMovementLocked(scope: 0))
}

private func makePNG(
    width: Int,
    height: Int,
    color: NSColor = NSColor(deviceRed: 0.25, green: 0.25, blue: 0.25, alpha: 1)
) throws -> Data {
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

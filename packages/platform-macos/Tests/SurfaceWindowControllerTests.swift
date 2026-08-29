import AppKit
import CoreText
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@Test func `default ghost dialogue font prefers Japanese glyphs`() {
    let font = ghostDialogueFont(named: nil, size: 14)
    let resolved = CTFontCreateForString(
        font as CTFont,
        "漢" as CFString,
        CFRange(location: 0, length: 1)
    )
    #expect((CTFontCopyPostScriptName(resolved) as String).contains("Hiragino"))

    let explicit = ghostDialogueFont(named: "Menlo", size: 14)
    #expect(explicit.fontName.contains("Menlo"))
}

@Test func `automatic animation probabilities match SERIKO intervals`() {
    #expect(automaticAnimationRandomDenominator(components: ["sometimes"], parameter: nil) == 2)
    #expect(automaticAnimationRandomDenominator(components: ["rarely"], parameter: nil) == 4)
    #expect(automaticAnimationRandomDenominator(components: ["random"], parameter: 7) == 7)
    #expect(automaticAnimationRandomDenominator(components: ["periodic"], parameter: 7) == nil)
}

@Test func `automatic surface fit only shrinks oversized images`() {
    #expect(automaticSurfaceFitScale(
        imageSize: NSSize(width: 400, height: 600),
        visibleSize: NSSize(width: 1440, height: 900)
    ) == 1)
    #expect(abs(automaticSurfaceFitScale(
        imageSize: NSSize(width: 676, height: 1000),
        visibleSize: NSSize(width: 1440, height: 900)
    ) - 0.675) < 0.0001)
    #expect(automaticSurfaceFitScale(imageSize: NSSize(width: 676, height: 1000), visibleSize: nil) == 1)
}

@Test func `chooses interaction cursors from collision regions`() {
    #expect(SurfaceCursorStyle(region: nil) == .arrow)
    #expect(SurfaceCursorStyle(region: "Head") == .openHand)
    #expect(SurfaceCursorStyle(region: "Ear1") == .openHand)
    #expect(SurfaceCursorStyle(region: "hair") == .openHand)
    #expect(SurfaceCursorStyle(region: "Mouth") == .pointingHand)
    #expect(SurfaceCursorStyle(region: "MenuButton") == .pointingHand)
}

@MainActor
@Test func `renders all Emily Phase4 default characters`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(path: "Content/Local/Ghosts/emily4/shell/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    let shell = try ShellLoader().load(from: root)
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10, 2: 200])
    #expect(controller.visibleScopes == [0, 1, 2])
    #expect(controller.renderedImage(for: 2) != nil)
    controller.hideAll()
}

@MainActor
@Test func `renders Juda System default characters`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(path: "Content/Local/Ghosts/Juda-System/shell/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    let shell = try ShellLoader().load(from: root)
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10])
    #expect(controller.visibleScopes == [0, 1])
    #expect(try #require(controller.renderedImage(for: 0)).hasVisiblePixels)
    #expect(controller.renderedImage(for: 1) != nil)
    try controller.changeSurface(scope: 0, to: 1)
    for animationID in [6, 29, 7, 4, 5, 40] {
        controller.playAnimation(id: animationID, scope: 0)
        #expect(
            try #require(controller.renderedImage(for: 0)).hasVisiblePixels,
            "animation \(animationID) must contribute visible pixels"
        )
    }
    #expect(try #require(controller.renderedImage(for: 0)).hasVisiblePixels)
    controller.hideAll()
}

@MainActor
@Test func `renders a surface stored with the APNG extension`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0.apng"))

    let controller = SurfaceWindowController()
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:]), surfaceID: 0)
    defer { controller.hideAll() }

    #expect(controller.renderedImage() != nil)
}

@MainActor
@Test func `renders the installed Umaumauma default APNG surfaces`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(
        path: "Content/Local/Ghosts/umaumauma/shell/master",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: root.path) else { return }

    let shell = try ShellLoader().load(from: root)
    #expect(shell.surfaces[2004]?.elements.map(\.filename) == ["tb1020.png", "tb1204.png"])
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10])
    defer { controller.hideAll() }

    let renderedHorse = try #require(controller.renderedImage(for: 0))
    #expect(controller.renderedImage(for: 1) != nil)
    #expect(renderedHorse.transparentPixelRatio > 0.5)
    try controller.changeSurface(scope: 2, to: 999)
    #expect(try #require(controller.renderedImage(for: 2)).transparentPixelRatio == 1)
}

private extension NSImage {
    var transparentPixelRatio: Double {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else { return 0 }
        var transparentPixels = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1 < 0.01 {
                transparentPixels += 1
            }
        }
        return Double(transparentPixels) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
    }

    var hasVisiblePixels: Bool {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else { return false }
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.01 {
                return true
            }
        }
        return false
    }

    func colorAtCenter() -> NSColor? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else { return nil }
        return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
    }
}

@MainActor
@Test func `persistent animation layers follow SERIKO animation ID order`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))

    func animation(_ id: Int) -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: "never",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: id,
                waitMilliseconds: 0, x: 0, y: 0
            )]
        )
    }
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [animation(2), animation(1)]
        )],
        usesSelfAlpha: true
    )
    #expect(shell.surfaces[0]?.animations.map(\.id) == [2, 1])
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 2, scope: 0)
    controller.playAnimation(id: 1, scope: 0)
    let color = try #require(controller.renderedImage(for: 0)?.colorAtCenter())
    #expect(color.blueComponent > 0.9)
    #expect(color.redComponent < 0.1)
}

@MainActor
@Test func `runonce animation layers follow SERIKO animation ID order`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))

    func runonce(_ id: Int) -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: "runonce",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: id,
                waitMilliseconds: 0, x: 0, y: 0
            )]
        )
    }
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [runonce(2), runonce(1)]
        )],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    let color = try #require(controller.renderedImage(for: 0)?.colorAtCenter())
    #expect(color.blueComponent > 0.9)
    #expect(color.redComponent < 0.1)
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

    let presentation = controller.captureReloadPresentation()
    controller.resetContent()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10], restoring: presentation)
    #expect(controller.surfaceID(for: 0) == 5)
    #expect(controller.surfaceID(for: 1) == 10000)

    // A different ghost must not inherit a reload snapshot implicitly.
    controller.resetContent()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10])
    #expect(controller.surfaceID(for: 0) == 0)
    #expect(controller.surfaceID(for: 1) == 10)
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
func `bound blink replaces its initial eye layer instead of overlaying it`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)).write(to: directory.appending(path: "surface1.png"))
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)).write(to: directory.appending(path: "surface2.png"))
    let shell = ShellDefinition(directory: directory, surfaces: [0: SurfaceDefinition(
        id: 0, collisions: [], animations: [SurfaceAnimation(
            id: 101, interval: "bind", patterns: [
                SurfaceAnimationPattern(order: 0, method: "stop", surfaceID: 100, waitMilliseconds: 0, x: 0, y: 0),
                SurfaceAnimationPattern(order: 1, method: "overlay", surfaceID: 1, waitMilliseconds: 0, x: 0, y: 0),
                SurfaceAnimationPattern(order: 2, method: "overlay", surfaceID: 2, waitMilliseconds: 2000, x: 0, y: 0)
            ]
        )]
    )], usesSelfAlpha: true, defaultBindGroups: [0: [101]])
    let controller = SurfaceWindowController(positionStore: positionStore)
    defer { controller.resetContent() }
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0])
    #expect(try #require(controller.renderedImage()?.colorAtCenter()).redComponent > 0.9)
    controller.playAnimation(id: 101)
    for _ in 0 ..< 100 {
        if controller.renderedImage()?.colorAtCenter()?.blueComponent ?? 0 > 0.9 {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try #require(controller.renderedImage()?.colorAtCenter()).blueComponent > 0.9)
    controller.stopAnimation(id: 101)
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
        interval: nil,
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
        intervalParameter: 2,
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

    #expect(!controller.playIntervalAnimation("starttalk", scope: 0))
    #expect(!controller.playTalkAnimation(scope: 0))
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
        #expect(surfaceController.visibleScopes.isEmpty)
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

    var presentationReadyCount = 0
    await player.playAndWait(
        SakuraScript(rawValue: "\\s[-1]\\![embed,OnCallSurface,5]\\e"),
        balloon: balloon,
        characterDelayMilliseconds: 0,
        onPresentationReady: {
            presentationReadyCount += 1
            #expect(surfaceController.surfaceID(for: 0) == 5)
        }
    )

    #expect(presentationReadyCount == 1)

    #expect(surfaceController.visibleScopes == [0])
    #expect(surfaceController.surfaceID(for: 0) == 5)
}

@Test
@MainActor
func `startup visibility gate survives restore and animations do not reveal hidden surfaces`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0.png"))
    let shell = ShellDefinition(directory: directory, surfaces: [0: SurfaceDefinition(
        id: 0, collisions: [], animations: [SurfaceAnimation(
            id: 1, interval: "never", patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: 0, waitMilliseconds: 20, x: 0, y: 0
            )]
        )]
    )])
    let controller = SurfaceWindowController(positionStore: positionStore)
    defer { controller.resetContent() }
    controller.setStartupPresentationHidden(true)
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0])
    let number = try #require(controller.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: number))
    controller.setPresentationHidden(false)
    controller.restoreSurfaces()
    #expect(window.alphaValue == 0)
    controller.setStartupPresentationHidden(false)
    #expect(window.alphaValue == 1)
    try controller.changeSurface(to: -1)
    controller.playAnimation(id: 1)
    #expect(controller.visibleScopes.isEmpty)
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
func `dressup context menu can remove an optional default part`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    let mask = ShellBindGroup(id: 1000, category: "顔", part: "マスク")
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(
            directory: directory,
            surfaces: [:],
            defaultBindGroups: [0: [1000]],
            bindGroups: [0: [1000: mask]]
        ),
        scope: 0,
        surfaceID: 0
    )
    defer { controller.hideAll() }

    let root = try #require(controller.dressupContextMenuItem(title: "着せ替え"))
    guard case let .submenu(title, categoryItems) = root,
          case let .submenu(category, partItems) = try #require(categoryItems.first),
          case let .action(part, selected, enabled, handler) = try #require(partItems.first)
    else {
        Issue.record("expected dressup/category/part menu hierarchy")
        return
    }
    #expect(title == "着せ替え")
    #expect(category == "顔")
    #expect(part == "マスク")
    #expect(selected)
    #expect(enabled)
    handler()
    #expect(controller.dressupInfo().first?.enabled == false)
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MOMOCHI_SHELL"] != nil))
@MainActor
struct MomochiCompatibilityTests {
    @Test func `real shell fits the screen and its mask can be removed`() throws {
        let directory = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_MOMOCHI_SHELL"]))
        let shell = try ShellLoader().load(from: directory)
        #expect(shell.usesSelfAlpha)
        #expect(shell.defaultBindGroups[0]?.contains(1000) == true)
        #expect(shell.bindGroups[0]?[1000]?.part == "マスク")
        let (defaults, positionStore) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let controller = SurfaceWindowController(positionStore: positionStore)
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        defer { controller.hideAll() }
        let frame = try #require(controller.windowFrame(for: 0))
        let expectedScale = automaticSurfaceFitScale(
            imageSize: NSSize(width: 676, height: 1000),
            visibleSize: NSScreen.main?.visibleFrame.size
        )
        #expect(abs(frame.height - 1000 * expectedScale) < 1)

        let root = try #require(controller.dressupContextMenuItem(title: "着せ替え"))
        guard case let .submenu(_, categories) = root
        else {
            Issue.record("expected the real mask dressup item")
            return
        }
        let maskItem: SurfaceContextMenuItem? = categories.lazy.compactMap { item in
            guard case let .submenu(_, parts) = item else { return nil }
            return parts.first(where: { part in
                guard case let .action(title, _, _, _) = part else { return false }
                return title == "マスク"
            })
        }.first
        guard case let .action(_, _, _, handler) = try #require(maskItem) else {
            Issue.record("expected the real mask dressup item")
            return
        }
        handler()
        #expect(controller.dressupInfo().first(where: { $0.group.id == 1000 })?.enabled == false)
    }
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
func `negative balloon surface keeps a not yet shown scope hidden`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0010.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloonk0.png"))

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

    await player.playAndWait(
        SakuraScript(rawValue: #"\1\b[-1]非表示\0表示\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.visibleScopes == [0])
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
func `leading capital C continues the previous dialogue without hiding other scopes`() async throws {
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
        balloonWindowController: balloonController,
        postDialogueDismissalMilliseconds: 60000
    )
    let balloon = makeBalloon(directory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"\0元のセリフ\1元の相方\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )
    await player.playAndWait(
        SakuraScript(rawValue: #"\C\1\cリンクの結果\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.visibleScopes == [0, 1])
    #expect(balloonController.textAndLinks(for: 0)?.0 == "元のセリフ")
    #expect(balloonController.textAndLinks(for: 1)?.0 == "リンクの結果")
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
    #expect(halfLine.minimumLineHeight == 0)
    #expect(halfLine.maximumLineHeight == 0)
    #expect(balloonController.textAttributes(at: 16, scope: 0)?[.paragraphStyle] == nil)
    let largeFont = try #require(balloonController.textAttributes(at: 17, scope: 0)?[.font] as? NSFont)
    let smallerFont = try #require(balloonController.textAttributes(at: 18, scope: 0)?[.font] as? NSFont)
    #expect(largeFont.fontName.contains("Menlo"))
    #expect(abs(largeFont.pointSize - 16.8) < 0.1)
    #expect(abs(smallerFont.pointSize - 14) < 0.1)
}

@Test
@MainActor
func `plain choice dispatches only the ordinary choice event`() async throws {
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
    var ordinaryChoice: String?
    var extendedChoice: String?
    player.onChoice = { id, _ in ordinaryChoice = id }
    player.onChoiceSelectEx = { _, id, _ in extendedChoice = id }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[話す頻度はこれでいいの？,talkinterval]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    let link = try #require(balloonController.textAndLinks(for: 0)?.1.first)
    balloonController.onLinkActivate?(link, "話す頻度はこれでいいの？")
    balloonController.onLinkClick?(link.id, link.arguments)

    #expect(ordinaryChoice == "talkinterval")
    #expect(extendedChoice == nil)
    #expect(balloonController.visibleScopes == [0])
}

@Test
@MainActor
func `anchor response interrupts and then resumes the script that contains it`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 200, height: 120).write(to: directory.appending(path: "balloons0.png"))

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
    let balloon = makeBalloon(directory: directory)
    player.onAnchorSelectEx = { _, _, _ in
        player.interrupt(
            with: SakuraScript(rawValue: #"\C\1アンカー応答\e"#),
            balloon: balloon,
            characterDelayMilliseconds: 0
        )
    }

    player.play(
        SakuraScript(rawValue: #"\0\_a[keyword,keyword,KW]語\_a後続のセリフが最後まで流れる\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 20
    )
    for _ in 0 ..< 100 where balloonController.textAndLinks(for: 0)?.1.isEmpty != false {
        try await Task.sleep(for: .milliseconds(10))
    }
    let link = try #require(balloonController.textAndLinks(for: 0)?.1.first)
    balloonController.onLinkActivate?(link, "語")
    balloonController.onLinkClick?(link.id, link.arguments)
    let expected = "語後続のセリフが最後まで流れる"
    for _ in 0 ..< 100 where balloonController.textAndLinks(for: 0)?.0 != expected
        || balloonController.textAndLinks(for: 1)?.0 != "アンカー応答"
    {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(balloonController.textAndLinks(for: 0)?.0 == expected)
    #expect(balloonController.textAndLinks(for: 1)?.0 == "アンカー応答")
}

@Test
@MainActor
func `numeric cursor moves separate compact ghost menu rows`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 240, height: 160).write(to: directory.appending(path: "balloons0.png"))

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
        SakuraScript(rawValue: #"お気に入り\_l[0,0]\f[align,right]閉じる\_l[0,@12]罫線\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "お気に入り\t閉じる\n罫線")
    let rightAligned = try #require(
        balloonController.textAttributes(at: 5, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(rightAligned.tabStops.count == 1)
    #expect(rightAligned.tabStops[0].alignment == .right)
    #expect(rightAligned.firstLineHeadIndent == 0)
    let relativeRow = try #require(
        balloonController.textAttributes(at: 10, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(relativeRow.firstLineHeadIndent == 0)
    #expect(abs(relativeRow.paragraphSpacingBefore + 5) < 1)
}

@Test
@MainActor
func `cursor moves resolve em and percent units into balloon coordinates`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 300, height: 240).write(to: directory.appending(path: "balloons0.png"))

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
        SakuraScript(rawValue: #"先頭\_l[1em,2em]A\_l[12em,]B\_l[,@+70%]C\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let first = try #require(
        balloonController.textAttributes(at: 3, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    let second = try #require(
        balloonController.textAttributes(at: 5, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    let third = try #require(
        balloonController.textAttributes(at: 7, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(abs(first.firstLineHeadIndent - 14) < 0.5)
    #expect(abs(second.firstLineHeadIndent - 168) < 0.5)
    #expect(third.firstLineHeadIndent > second.firstLineHeadIndent)
    #expect(third.paragraphSpacingBefore > 0)
}

@Test
@MainActor
func `clicking a terminal wait clears and closes the balloon`() async throws {
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

    player.play(
        SakuraScript(rawValue: #"クリックして閉じる\x\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    for _ in 0 ..< 100 where balloonController.visibleScopes.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(balloonController.visibleScopes == [0])

    player.advance()
    for _ in 0 ..< 100 where !balloonController.visibleScopes.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(balloonController.visibleScopes.isEmpty)
}

@Test
@MainActor
func `renders adjacent extended choices without inserting a newline`() async throws {
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
    #expect(content.0 == "選択肢次錨")
    #expect(content.1 == [
        BalloonTextLink(
            range: NSRange(location: 0, length: 3),
            id: "OnSelect",
            arguments: ["arg"]
        ),
        BalloonTextLink(
            range: NSRange(location: 4, length: 1),
            id: "OnAnchor",
            arguments: [],
            kind: .anchor,
            fontColor: BalloonColor(red: 0, green: 255, blue: 0)
        )
    ])
    let anchorColor = try #require(
        balloonController.textAttributes(at: 4, scope: 0)?[.foregroundColor] as? NSColor
    )
    #expect(anchorColor.greenComponent > 0.9)
}

@Test
@MainActor
func `applies balloon default font decoration`() async throws {
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
    let balloon = BalloonDefinition(
        directory: directory,
        name: "decorated",
        originX: 10,
        originY: 10,
        wordWrapPointX: -10,
        wordWrapPointY: -10,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        fontShadowColor: BalloonColor(red: 10, green: 20, blue: 30),
        fontShadowStyle: "outline",
        fontBold: true,
        fontItalic: true,
        fontUnderline: true,
        fontStrike: true
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"装飾\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    let attributes = try #require(balloonController.textAttributes(at: 0, scope: 0))
    let font = try #require(attributes[.font] as? NSFont)
    let traits = NSFontManager.shared.traits(of: font)
    #expect(traits.contains(.boldFontMask))
    #expect(attributes[.obliqueness] as? Double == 0.2)
    #expect(attributes[.underlineStyle] as? Int == 1)
    #expect(attributes[.strikethroughStyle] as? Int == 1)
    #expect(attributes[.strokeWidth] as? Int == -3)
}

@Test
@MainActor
func `lays out vertical balloon text with vertical glyphs`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 300, height: 200).write(to: directory.appending(path: "balloons0.png"))

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
    let balloon = BalloonDefinition(
        directory: directory,
        name: "vertical",
        originX: 280,
        originY: 20,
        wordWrapPointX: 0,
        wordWrapPointY: 180,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        validRectLeft: 20,
        validRectTop: 20,
        validRectRight: 280,
        validRectBottom: 180,
        isVertical: true
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"縦書き\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textLayoutOrientation(scope: 0) == .vertical)
    #expect(balloonController.textAttributes(at: 0, scope: 0)?[.verticalGlyphForm] as? Int == 1)
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
func `dismisses balloons before requesting surface restore`() async throws {
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
        postDialogueDismissalMilliseconds: 20,
        surfaceRestoreDelayMilliseconds: 40
    )
    var didRequestSurfaceRestore = false
    player.onSurfaceRestore = { didRequestSurfaceRestore = true }
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
    #expect(surfaceController.surfaceID(for: 0) == 1)
    #expect(surfaceController.surfaceID(for: 1) == 11)
    for _ in 0 ..< 100 where !balloonController.visibleScopes.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(balloonController.visibleScopes.isEmpty)
    #expect(!didRequestSurfaceRestore)
    for _ in 0 ..< 100 where !didRequestSurfaceRestore {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(didRequestSurfaceRestore)
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
    var timedOutScript: String?
    player.onChoiceTimeout = { timedOutScript = $0 }

    let source = #"\q[選択,OnSelect]\![set,choicetimeout,20]\e"#
    await player.playAndWait(
        SakuraScript(rawValue: source),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    for _ in 0 ..< 100 where timedOutScript == nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(timedOutScript == source)
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

@Test
@MainActor
func `updates window level with stayOnTop`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let balloonController = BalloonWindowController(positionStore: positionStore)

    surfaceController.setStayOnTop(false)
    balloonController.setStayOnTop(false)
    surfaceController.setStayOnTop(true)
    balloonController.setStayOnTop(true)
}

@Test
@MainActor
func `handles zorder and sticky window configuration`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaceController = SurfaceWindowController(positionStore: positionStore)

    surfaceController.setStickyWindows(scopes: [0, 1])
    surfaceController.resetStickyWindows()
    surfaceController.setZOrder(["1", "0"])
    surfaceController.resetZOrder()
}

@Test
@MainActor
func `sets and resets a fixed surface position`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))

    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { controller.hideAll() }

    await controller.setFixedPosition(x: 120, y: 200, scope: 0)

    #expect(controller.windowFrame(for: 0)?.origin == NSPoint(x: 120, y: 200))
    #expect(controller.isMovementLocked(scope: 0))

    controller.resetFixedPositions()
    #expect(!controller.isMovementLocked(scope: 0))
}

@Test
@MainActor
func `renders inline balloon images`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 100).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makeTopLeftKeyedPNG(width: 16, height: 16).write(to: directory.appending(path: "icon.png"))

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
    player.configure(resourceBaseDirectory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"画像\_b[icon.png,inline]表示\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let attachment = try #require(balloonController.textAttributes(at: 2, scope: 0)?[.attachment] as? NSTextAttachment)
    let font = try #require(balloonController.textAttributes(at: 2, scope: 0)?[.font] as? NSFont)
    #expect(attachment.bounds.height == 16)
    #expect(attachment.bounds.origin.y == (font.capHeight - 16) / 2)
    let image = try #require(attachment.image)
    let representation = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    #expect((representation.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
    #expect((representation.colorAt(x: 1, y: 0)?.alphaComponent ?? 0) > 0.9)
}

@Test
@MainActor
func `renders choice marker aligned with text cap height`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 100).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "marker.png"))

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
    player.configure(resourceBaseDirectory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"\_q\![*]\q[選択肢,choice_id]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let attachment = try #require(balloonController.textAttributes(at: 0, scope: 0)?[.attachment] as? NSTextAttachment)
    let font = try #require(balloonController.textAttributes(at: 0, scope: 0)?[.font] as? NSFont)
    #expect(attachment.bounds.height == 8)
    #expect(attachment.bounds.origin.y == (font.capHeight - 8) / 2)
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

private func makeTopLeftKeyedPNG(width: Int, height: Int) throws -> Data {
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
    let key = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
    let content = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    for y in 0 ..< height {
        for x in 0 ..< width {
            bitmap.setColor(x == 0 && y == 0 ? key : content, atX: x, y: y)
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

@Test @MainActor
func `balloons follow their surface while preserving independent balloon movement`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 60).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloonk0.png"))
    let surfaces = SurfaceWindowController(positionStore: positionStore)
    surfaces.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)
    try surfaces.show(shell: ShellDefinition(directory: directory, surfaces: [:]), defaultSurfaceIDs: [0: 0, 1: 0])
    let balloons = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    defer { player.cancel(); surfaces.hideAll(); balloons.hideAll() }
    await player.playAndWait(SakuraScript(rawValue: #"\0hello\1world\e"#), balloon: makeBalloon(directory: directory), characterDelayMilliseconds: 0)
    let surface = try #require(surfaces.windowFrame(for: 0))
    let balloon = try #require(balloons.windowFrame(for: 0))
    let otherBalloon = balloons.windowFrame(for: 1)
    await surfaces.moveSurface(scope: 0, x: Int(surface.minX + 37), y: Int(surface.minY + 19), time: 0, isAsync: false)
    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: balloon.minX + 37, y: balloon.minY + 19))
    #expect(balloons.windowFrame(for: 1) == otherBalloon)
    let balloonNumber = try #require(balloons.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: balloonNumber))
    let movedSurface = surfaces.windowFrame(for: 0)
    window.setFrameOrigin(NSPoint(x: balloon.minX + 50, y: balloon.minY + 40))
    #expect(surfaces.windowFrame(for: 0) == movedSurface)
    balloons.hide(scope: 0)
    await surfaces.moveSurface(scope: 0, x: Int(surface.minX + 47), y: Int(surface.minY + 29), time: 0, isAsync: false)
    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: balloon.minX + 60, y: balloon.minY + 50))
    #expect(!balloons.visibleScopes.contains(0))
    try balloons.show(balloon: makeBalloon(directory: directory), text: "again", near: #require(surfaces.windowFrame(for: 0)))
    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: balloon.minX + 60, y: balloon.minY + 50))
}

@Suite(.serialized)
struct SurfaceDragTests {
    @Test @MainActor
    func `surface drag dims only while dragging and reports actual desktop coordinates`() async throws {
        let fixture = try makeSurfaceDragFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let window = fixture.window
        let view = try #require(window.contentView)
        let start = window.frame
        let pointer = NSPoint(x: start.midX, y: start.midY)
        var events: [GhostMouseEvent.Kind] = []
        controller.onMouseEvent = { events.append($0.kind) }
        await controller.setAlpha(0.8, scope: 0)
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: pointer, window: window))
        #expect(window.alphaValue == 0.8)
        try view.mouseDragged(with: surfaceDragEvent(.leftMouseDragged, pointer: NSPoint(x: pointer.x + 1, y: pointer.y), window: window))
        #expect(window.frame == start)
        #expect(controller.dragPosition(for: 0) == nil)
        try view.mouseDragged(with: surfaceDragEvent(.leftMouseDragged, pointer: NSPoint(x: pointer.x + 40, y: pointer.y + 25), window: window))
        #expect(abs(window.alphaValue - 0.4) < 0.001)
        #expect(controller.alpha(for: 0) == 0.8)
        #expect(controller.dragPosition(for: 0) == SurfaceDragPosition(
            frame: window.frame, startOrigin: start.origin, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0
        ))
        #expect(controller.dragPosition(for: 0)?.delta == NSPoint(x: 40, y: -25))
        await controller.setAlpha(0.6, scope: 0)
        #expect(abs(window.alphaValue - 0.3) < 0.001)
        try view.mouseUp(with: surfaceDragEvent(.leftMouseUp, pointer: NSPoint(x: pointer.x + 40, y: pointer.y + 25), window: window))
        #expect(abs(window.alphaValue - 0.6) < 0.001)
        #expect(controller.dragPosition(for: 0) == nil)
        #expect(events.filter { $0 == .dragStart }.count == 1)
        #expect(events.filter { $0 == .dragEnd }.count == 1)
        #expect(!events.contains(.click))
    }

    @Test @MainActor
    func `surface drag feedback respects desktop locks`() async throws {
        let fixture = try makeSurfaceDragFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let window = fixture.window
        controller.setPlacement(locksToDesktopBottom: true, keepsOnScreen: true)
        let view = try #require(window.contentView)
        let start = window.frame
        let pointer = NSPoint(x: start.midX, y: start.midY)
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: pointer, window: window))
        try view.mouseDragged(with: surfaceDragEvent(.leftMouseDragged, pointer: NSPoint(x: pointer.x + 30, y: pointer.y + 80), window: window))
        #expect(controller.dragPosition(for: 0)?.delta == NSPoint(x: 30, y: 0))
        try view.mouseUp(with: surfaceDragEvent(.leftMouseUp, pointer: pointer, window: window))
        await controller.setFixedPosition(x: Int(window.frame.minX), y: Int(window.frame.minY), scope: 0)
        let locked = window.frame
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: pointer, window: window))
        try view.mouseDragged(with: surfaceDragEvent(.leftMouseDragged, pointer: NSPoint(x: pointer.x + 60, y: pointer.y + 80), window: window))
        #expect(window.frame == locked)
        #expect(window.alphaValue == 1)
        #expect(controller.dragPosition(for: 0) == nil)
    }

    @Test(arguments: ["escape", "hide", "lock", "replace", "deactivate"])
    @MainActor
    func `surface drag feedback clears when interrupted`(reason: String) async throws {
        let fixture = try makeSurfaceDragFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let window = fixture.window
        let view = try #require(window.contentView)
        let pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        var clicks = 0
        var dragEnds = 0
        controller.onMouseClick = { _, _ in clicks += 1 }
        controller.onMouseEvent = {
            if $0.kind == .dragEnd {
                dragEnds += 1
            }
        }
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: pointer, window: window))
        try view.mouseDragged(with: surfaceDragEvent(.leftMouseDragged, pointer: NSPoint(x: pointer.x + 20, y: pointer.y + 20), window: window))
        #expect(controller.dragPosition(for: 0) != nil)
        switch reason {
        case "escape": window.cancelOperation(nil)
        case "hide": controller.setPresentationHidden(true)
        case "lock": await controller.setFixedPosition(x: Int(window.frame.minX), y: Int(window.frame.minY), scope: 0)
        case "replace": try controller.changeSurface(scope: 0, to: 1)
        default: NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        }
        #expect(controller.dragPosition(for: 0) == nil)
        #expect(window.alphaValue == (reason == "hide" ? 0 : 1))
        let stoppedFrame = window.frame
        try view.mouseDragged(with: surfaceDragEvent(.leftMouseDragged, pointer: NSPoint(x: pointer.x + 80, y: pointer.y + 80), window: window))
        #expect(window.frame == stoppedFrame)
        try view.mouseUp(with: surfaceDragEvent(.leftMouseUp, pointer: pointer, window: window))
        #expect(clicks == 0)
        #expect(dragEnds == 1)
        if reason == "hide" {
            controller.setPresentationHidden(false)
            #expect(window.alphaValue == 1)
        }
    }

    @Test func `surface drag coordinates support negative displays and signed movement`() {
        let position = SurfaceDragPosition(
            frame: NSRect(x: -200, y: 1100, width: 80, height: 120),
            startOrigin: NSPoint(x: -150, y: 1060), desktopTop: 1080
        )
        #expect(position.text == "X: -200  Y: -140\nΔX: -50  ΔY: -40")
    }
}

@MainActor
private struct SurfaceDragFixture {
    let directory: URL
    let defaults: UserDefaults
    let controller: SurfaceWindowController
    let window: NSWindow

    func cleanUp() {
        controller.hideAll()
        defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func makeSurfaceDragFixture() throws -> SurfaceDragFixture {
    let (defaults, positionStore) = makePositionStore()
    let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-drag-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 80, height: 120).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 80, height: 120).write(to: directory.appending(path: "surface1.png"))
    let controller = SurfaceWindowController(positionStore: positionStore)
    controller.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:]), scope: 0, surfaceID: 0)
    let number = try #require(controller.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: number))
    window.setFrameOrigin(NSPoint(x: 200, y: 200))
    return SurfaceDragFixture(directory: directory, defaults: defaults, controller: controller, window: window)
}

@MainActor
private func surfaceDragEvent(_ type: NSEvent.EventType, pointer: NSPoint, window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
        with: type, location: window.convertPoint(fromScreen: pointer), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    ))
}

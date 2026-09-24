import AppKit
import Combine
import CoreText
import SwiftUI
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS

@Test func `SakuraScript colors include CSS extended keywords`() {
    #expect(cssNamedBalloonColors.count >= 147)
    #expect(cssNamedBalloonColors["aliceblue"] == BalloonColor(red: 240, green: 248, blue: 255))
    #expect(cssNamedBalloonColors["darkslategrey"] == BalloonColor(red: 47, green: 79, blue: 79))
}

@Test func `resolves SakuraScript web mail and ghost relative file targets`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "descript.txt")
    try Data("name,test".utf8).write(to: file)

    #expect(SakuraScriptOpenTargetResolver.resolve(
        "https://example.com/",
        relativeTo: root
    )?.absoluteString == "https://example.com/")
    #expect(SakuraScriptOpenTargetResolver.resolve(
        "mailto:test@example.com",
        relativeTo: root
    )?.absoluteString == "mailto:test@example.com")
    #expect(SakuraScriptOpenTargetResolver.resolve(
        "file:///descript.txt",
        relativeTo: root
    ) == file.standardizedFileURL)
    #expect(SakuraScriptOpenTargetResolver.resolve("javascript:alert(1)", relativeTo: root) == nil)
}

import UtataneSakuraScript
import UtataneShell

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
func `renders the installed rage partner when optional element images are missing`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let shellDirectory = repositoryRoot.appending(
        path: "Content/Local/Ghosts/rage/shell/master",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: shellDirectory.path) else { return }
    let shell = try ShellLoader().load(from: shellDirectory)
    let controller = SurfaceWindowController()
    defer { controller.hideAll() }

    try controller.show(shell: shell, scope: 1, surfaceID: 10)

    #expect(controller.surfaceID(for: 1) == 10)
    #expect(try #require(controller.renderedImage(for: 1)).hasVisiblePixels)
}

@Test
@MainActor
func `shell presentation defaults place and align a surface`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 200).write(to: directory.appending(path: "surface0000.png"))
    let geometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 100, y: 50, width: 1000, height: 700),
            visibleFrame: NSRect(x: 100, y: 50, width: 1000, height: 700),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(id: 0, collisions: [], animations: [])],
        surfaceTable: nil,
        maximumSurfaceWidth: nil,
        desktopAlignment: .bottom,
        presentationSettings: [
            0: ShellScopePresentationSettings(
                desktopAlignment: .free,
                defaultLeft: 30,
                defaultTop: 40
            )
        ]
    )
    let controller = SurfaceWindowController(positionStore: positionStore, geometryProvider: geometry)
    controller.setPlacement(locksToDesktopBottom: false, keepsOnScreen: true)
    defer { controller.hideAll() }

    try controller.show(shell: shell, surfaceID: 0)

    #expect(controller.windowFrame?.origin == NSPoint(x: 130, y: 510))
}

@Test
@MainActor
func `shell defaults configure balloon alignment movement and synchronized scale`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 80).write(to: directory.appending(path: "balloons0.png"))
    let geometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [:],
        surfaceTable: nil,
        maximumSurfaceWidth: nil,
        presentationSettings: [
            0: ShellScopePresentationSettings(
                balloonOffsets: ShellBalloonOffsets(leftX: 10, leftY: 20),
                balloonAlignment: .left,
                preventsBalloonMovement: true,
                synchronizesBalloonScale: true
            )
        ]
    )
    let controller = BalloonWindowController(positionStore: positionStore, geometryProvider: geometry)
    controller.setDisplayScale(1, textScale: 1, surfaceScale: 1.5)
    controller.configure(shell: shell)
    let surfaceFrame = NSRect(x: 600, y: 200, width: 100, height: 300)

    try controller.show(balloon: makeBalloon(directory: directory), text: "test", near: surfaceFrame)
    defer { controller.hideAll() }

    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 150, height: 120))
    #expect(controller.windowFrame(for: 0)?.origin == NSPoint(x: 457, y: 350))
    #expect(controller.alignment(scope: 0) == .left)
    #expect(controller.isMovementLocked(scope: 0))
}

@Test
@MainActor
func `changes to a surface by its surfaces txt name`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 50, height: 90).write(to: directory.appending(path: "surface0005.png"))
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [
            0: SurfaceDefinition(id: 0, name: "normal", collisions: [], animations: []),
            5: SurfaceDefinition(id: 5, name: "smile", collisions: [], animations: [])
        ]
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    defer { controller.hideAll() }

    try controller.show(shell: shell, surfaceID: 0)
    try controller.changeSurface(named: "smile")

    #expect(controller.surfaceID(for: 0) == 5)
    #expect(controller.windowFrame(for: 0)?.size == NSSize(width: 50, height: 90))
}

@Test
@MainActor
func `surface base position stays fixed across changes scaling and saved positions`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 100, height: 60).write(to: directory.appending(path: "surface0001.png"))
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [
            0: SurfaceDefinition(
                id: 0,
                points: ["basepos": SurfacePoint(x: 10, y: 20)],
                collisions: [],
                animations: []
            ),
            1: SurfaceDefinition(
                id: 1,
                points: ["basepos": SurfacePoint(x: 40, y: 50)],
                collisions: [],
                animations: []
            )
        ],
        surfaceTable: nil,
        maximumSurfaceWidth: nil,
        desktopAlignment: .free
    )
    positionStore.setContentID(directory)
    let controller = SurfaceWindowController(positionStore: positionStore)
    controller.setPlacement(locksToDesktopBottom: false, keepsOnScreen: true)
    try controller.show(shell: shell, surfaceID: 0)
    controller.restoreLayoutPresetPositions([0: NSPoint(x: 500, y: 500)])

    try controller.changeSurface(to: 1)
    #expect(controller.windowFrame(for: 0)?.origin == NSPoint(x: 470, y: 550))
    await controller.setRuntimeScale(horizontal: 2, vertical: 2, scope: 0, durationMilliseconds: 0)
    #expect(controller.windowFrame(for: 0)?.origin == NSPoint(x: 430, y: 540))
    controller.resetContent()

    let restored = SurfaceWindowController(positionStore: positionStore)
    restored.setPlacement(locksToDesktopBottom: false, keepsOnScreen: true)
    defer { restored.resetContent() }
    try restored.show(shell: shell, surfaceID: 1)
    #expect(restored.windowFrame(for: 0)?.origin == NSPoint(x: 470, y: 550))
}

@Test
@MainActor
func `speech history thumbnail uses the surface icon rectangle`() throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 100,
        pixelsHigh: 160,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 400,
        bitsPerPixel: 32
    ))
    let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    for y in 0 ..< 160 {
        for x in 0 ..< 100 {
            bitmap.setColor(x < 40 && y < 40 ? red : blue, atX: x, y: y)
        }
    }
    let image = NSImage(size: NSSize(width: 100, height: 160))
    image.addRepresentation(bitmap)

    let data = try #require(SpeechHistoryThumbnail.pngData(
        from: image,
        iconRect: SurfaceRect(left: 0, top: 0, right: 40, bottom: 40),
        pixelSize: 32
    ))
    let thumbnail = try #require(NSBitmapImageRep(data: data))
    let center = try #require(thumbnail.colorAt(x: 16, y: 16)?.usingColorSpace(.deviceRGB))
    #expect(center.redComponent > 0.9)
    #expect(center.blueComponent < 0.1)
    // Without icon.rect, use the top square of a tall image, not its feet.
    let defaultData = try #require(SpeechHistoryThumbnail.pngData(from: image, pixelSize: 100))
    let defaultThumbnail = try #require(NSBitmapImageRep(data: defaultData))
    let topLeft = try #require(defaultThumbnail.colorAt(x: 20, y: 20)?.usingColorSpace(.deviceRGB))
    let below = try #require(defaultThumbnail.colorAt(x: 20, y: 80)?.usingColorSpace(.deviceRGB))
    #expect(topLeft.redComponent > 0.9)
    #expect(below.blueComponent > 0.9)
}

@Test(arguments: [false, true])
@MainActor
func `combines shell surface and SakuraScript balloon offsets`(hasUserOffset: Bool) async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let dragX: CGFloat = hasUserOffset ? 35 : 0
    let dragY: CGFloat = hasUserOffset ? -20 : 0
    if hasUserOffset {
        positionStore.saveBalloonDragOffset(NSPoint(x: dragX, y: dragY), scope: 0, coordinateSpace: .desktop)
    }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 200).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons0.png"))
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [
            0: SurfaceDefinition(
                id: 0,
                balloonOffset: SurfacePoint(x: 30, y: 40),
                collisions: [],
                animations: []
            )
        ],
        surfaceTable: nil,
        maximumSurfaceWidth: nil,
        presentationSettings: [
            0: ShellScopePresentationSettings(
                balloonOffsets: ShellBalloonOffsets(leftX: 10, leftY: 20),
                balloonAlignment: .left
            )
        ]
    )
    let surfaces = SurfaceWindowController(positionStore: positionStore)
    surfaces.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)
    try surfaces.show(shell: shell, surfaceID: 0)
    await surfaces.setFixedPosition(x: 500, y: 300, scope: 0)
    let balloons = BalloonWindowController(positionStore: positionStore)
    balloons.configure(shell: shell)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaces,
        balloonWindowController: balloons
    )
    defer { player.cancel(); surfaces.hideAll(); balloons.hideAll() }

    player.play(
        SakuraScript(rawValue: #"\0\![set,balloonoffset,@5,@6]hello\x\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        balloons.visibleScopes.contains(0)
            && balloons.displayedText(for: 0) == "hello"
    }

    #expect(balloons.offset(scope: 0) == NSPoint(x: 5, y: 6))
    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: 417 + dragX, y: 354 + dragY))

    player.advance()
    try await requireEventually {
        balloons.offset(scope: 0) == nil
    }

    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: 412 + dragX, y: 360 + dragY))

    player.play(
        SakuraScript(rawValue: #"\0\![set,balloonoffset,5,6]hello\x\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        balloons.visibleScopes.contains(0)
            && balloons.displayedText(for: 0) == "hello"
    }

    #expect(balloons.offset(scope: 0) == NSPoint(x: 5, y: 6))
    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: 377 + dragX, y: 414 + dragY))

    player.advance()
    try await requireEventually {
        balloons.offset(scope: 0) == nil
    }

    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: 412 + dragX, y: 360 + dragY))

    player.play(
        SakuraScript(rawValue: #"\0hello\![set,balloonoffset,5,6]\x\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        balloons.offset(scope: 0) == NSPoint(x: 5, y: 6)
    }

    #expect(balloons.windowFrame(for: 0)?.origin == NSPoint(x: 377 + dragX, y: 414 + dragY))

    player.advance()
    try await requireEventually {
        balloons.offset(scope: 0) == nil
    }
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
    try await requireEventually {
        controller.renderedImage()?.colorAtCenter()?.blueComponent ?? 0 > 0.9
    }
    #expect(try #require(controller.renderedImage()?.colorAtCenter()).blueComponent > 0.9)
    controller.stopAnimation(id: 101)
}

@Test
@MainActor
func `SakuraScript dynamic animation can overlay and replace the base surface`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
        .write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        .write(to: directory.appending(path: "surface1.png"))
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1))
        .write(to: directory.appending(path: "surface2.png"))
    let controller = SurfaceWindowController(positionStore: positionStore)
    defer { controller.resetContent() }
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [:], usesSelfAlpha: true),
        defaultSurfaceIDs: [0: 0]
    )

    controller.addAnimation(.surfaces(
        method: "base",
        frames: [.init(surfaceID: 2)],
        repeats: false
    ))
    #expect(try #require(controller.renderedImage()?.colorAtCenter()).greenComponent > 0.9)
    controller.addAnimation(.surfaces(
        method: "overlay",
        frames: [.init(surfaceID: 1)],
        repeats: false
    ))
    try await requireEventually {
        controller.renderedImage()?.colorAtCenter()?.redComponent ?? 0 > 0.9
    }
}

@Test
@MainActor
func `self referencing blink reuses the loaded base surface`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let baseURL = directory.appending(path: "surface0.png")
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: baseURL)
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface1000.png"))
    let animation = SurfaceAnimation(
        id: 0,
        interval: nil,
        patterns: [
            SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: 1000,
                waitMilliseconds: 1000, x: 0, y: 0
            ),
            SurfaceAnimationPattern(
                order: 1, method: "overlay", surfaceID: 0,
                waitMilliseconds: 1000, x: 0, y: 0
            )
        ]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(id: 0, collisions: [], animations: [animation])],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    defer { controller.resetContent() }
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    let initialImage = try #require(controller.renderedImage(for: 0))
    try FileManager.default.removeItem(at: baseURL)

    controller.playAnimation(id: 0)
    try await requireEventually {
        controller.renderedImage(for: 0)?.colorAtCenter()?.blueComponent ?? 0 > 0.9
    }
    #expect(try #require(controller.renderedImage(for: 0)?.colorAtCenter()).blueComponent > 0.9)

    var reopenedFrame: NSImage?
    try await requireEventually {
        if let candidate = controller.renderedImage(for: 0),
           candidate !== initialImage,
           candidate.colorAtCenter()?.redComponent ?? 0 > 0.9
        {
            reopenedFrame = candidate
            return true
        }
        return false
    }
    let reopenedImage = try #require(reopenedFrame)
    #expect(reopenedImage !== initialImage)
    #expect(try #require(reopenedImage.colorAtCenter()).redComponent > 0.9)
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

    controller.playAnimation(id: 0, minimumFrameDurationMilliseconds: 30000)
    try await Task.sleep(for: .milliseconds(50))
    var didFinishWaiting = false
    let waitTask = Task { @MainActor in
        await controller.waitForAnimation(id: 0)
        didFinishWaiting = true
    }
    controller.stopAnimation(id: 0)
    try await requireEventually(timeout: .seconds(5)) {
        didFinishWaiting
    }
    await waitTask.value
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
func `records displayed speech using backlog voice modes`() async throws {
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
    defer { surfaceController.resetContent() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    defer { balloonController.resetContent() }
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let history = SpeechHistoryStore()
    player.configureSpeechHistory(
        store: history,
        context: SpeechHistoryContext(
            ghostIdentifier: "test-ghost",
            ghostName: "テストゴースト",
            speakerNames: [0: "さくら", 1: "うにゅう"]
        )
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\0表示\__v[disable]除外\__v\__v[alternate,代替]見た目\__v終端\q[選択,OnSelect]\_a[OnAnchor]錨\_a\1相手\n二行目\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(history.entries.map(\.scope) == [0, 1])
    #expect(history.entries.map(\.speakerName) == ["さくら", "うにゅう"])
    #expect(history.entries.map(\.surfaceID) == [0, 1])
    #expect(history.entries.allSatisfy { $0.thumbnailPNGData != nil })
    #expect(history.entries.map(\.text) == ["表示代替終端選択錨", "相手\n二行目"])
    #expect(Set(history.entries.map(\.talkIdentifier)).count == 1)
}

@Test
@MainActor
func `speech history keeps its newest entries within capacity`() {
    let history = SpeechHistoryStore(capacityPerGhost: 2)
    for index in 0 ..< 3 {
        history.append(SpeechHistoryEntry(
            ghostIdentifier: "test-ghost",
            ghostName: "テストゴースト",
            scope: 0,
            speakerName: "さくら",
            surfaceID: 0,
            text: "発話\(index)"
        ))
    }

    #expect(history.entries.map(\.text) == ["発話1", "発話2"])
}

@Test
@MainActor
func `speech synthesis follows scope and voice mode sections`() async throws {
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

    let surfaces = SurfaceWindowController(positionStore: positionStore)
    try surfaces.show(shell: ShellDefinition(directory: directory, surfaces: [:]), defaultSurfaceIDs: [0: 0, 1: 1])
    defer { surfaces.resetContent() }
    let balloons = BalloonWindowController(positionStore: positionStore)
    defer { balloons.resetContent() }
    let synthesizer = RecordingSpeechSynthesizer()
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaces,
        balloonWindowController: balloons
    )
    player.configureSpeechSynthesis(synthesizer: synthesizer) { scope in
        SpeechSynthesisConfiguration(voiceIdentifier: "voice-\(scope)", rate: 0.6)
    }

    await player.playAndWait(
        SakuraScript(rawValue: #"\0読む\__v[disable]読まない\__v\__v[alternate,だいたい]代替\__v\1相方\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(synthesizer.requests.map(\.text) == ["読む", "だいたい", "相方"])
    #expect(synthesizer.requests.map(\.scope) == [0, 0, 1])
    #expect(synthesizer.requests.map(\.configuration.voiceIdentifier) == ["voice-0", "voice-0", "voice-1"])
}

@MainActor
private final class RecordingSpeechSynthesizer: SpeechSynthesizing {
    var requests: [SpeechSynthesisRequest] = []

    func speak(_ request: SpeechSynthesisRequest) async throws {
        requests.append(request)
    }

    func stop() {}
}

@Test
@MainActor
func `speech history batches live updates and commits the complete entry`() {
    let history = SpeechHistoryStore()
    var recorder = SpeechHistoryRecorder(
        store: history,
        context: SpeechHistoryContext(
            ghostIdentifier: "test-ghost",
            ghostName: "テストゴースト",
            speakerNames: [0: "さくら", 1: "うにゅう"]
        ),
        initialScope: 0,
        surfaceID: { $0 }
    )

    recorder.append("一")
    let firstID = history.entries.first?.id
    #expect(history.entries.map(\.text) == ["一"])

    recorder.append("言")
    #expect(history.entries.count == 1)
    #expect(history.entries.first?.id == firstID)
    #expect(history.entries.first?.text == "一")

    recorder.finish()
    #expect(history.entries.first?.text == "一言")

    recorder.setScope(1)
    recorder.append("返")
    #expect(history.entries.map(\.text) == ["一言", "返"])
    #expect(Set(history.entries.map(\.talkIdentifier)).count == 1)
}

@Test
@MainActor
func `speech history does not publish every displayed character`() {
    let history = SpeechHistoryStore()
    var publicationCount = 0
    let observation = history.objectWillChange.sink { publicationCount += 1 }
    var recorder = SpeechHistoryRecorder(
        store: history,
        context: SpeechHistoryContext(
            ghostIdentifier: "test-ghost",
            ghostName: "テストゴースト"
        ),
        initialScope: 0,
        surfaceID: { _ in 0 }
    )

    for _ in 0 ..< 100 {
        recorder.append("字")
    }
    recorder.finish()

    #expect(history.entries.first?.text.count == 100)
    #expect(publicationCount < 20)
    withExtendedLifetime(observation) {}
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
    player.onInputBox = { command in
        calls.append("input:\(command.id):\(command.timeoutMilliseconds ?? -1):\(command.initialValue)")
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
    var methods: [String] = []
    player.onEmbeddedNotification = { id, arguments in
        methods.append("NOTIFY")
        events.append((id, arguments))
    }
    player.onEmbeddedEvent = { id, arguments in
        methods.append("GET")
        events.append((id, arguments))
        return id == "OnNotifyDressupInfo" ? SakuraScript(rawValue: #"\![embed,OnDressupReply]"#) : nil
    }
    let balloon = makeBalloon(directory: directory)

    await player.notifyInitialDressupInfo()
    #expect(methods == ["NOTIFY"])
    #expect(events.first?.0 == "OnNotifyDressupInfo")
    #expect(events.first?.1.first == "0\u{1}服\u{1}コート\u{1}mustselect\u{1}1\u{1}")
    methods.removeAll()
    events.removeAll()
    await player.playAndWait(
        SakuraScript(rawValue: #"\![bind,服,パーカー,1]\![bind-noevent,服,コート,1]\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    let info = surfaceController.dressupInfo()
    #expect(info.first(where: { $0.group.id == 10 })?.enabled == true)
    #expect(info.first(where: { $0.group.id == 11 })?.enabled == false)
    #expect(events.map(\.0) == ["OnDressupChanged", "OnDressupChanged", "OnNotifyDressupInfo", "OnDressupReply"])
    #expect(methods == ["NOTIFY", "GET", "GET", "GET"])
    #expect(events[0].1 == ["0", "コート", "0", "服", "script"])
    #expect(events[1].1 == ["0", "パーカー", "1", "服", "script"])
    methods.removeAll()
    events.removeAll()
    let changes = surfaceController.changeBind(scope: 0, category: "服", part: "パーカー", enabled: true)
    let response = await player.notifyDressupChanges(changes, source: "user")
    #expect(try #require(events.first).1.last == "user")
    #expect(response?.rawValue == #"\![embed,OnDressupReply]"#)
    methods.removeAll()
    events.removeAll()
    _ = try await player.notifyDressupChanges(Array(repeating: #require(changes.first), count: 100), source: "user")
    #expect(methods == ["GET"])
    #expect(events.map(\.0) == ["OnNotifyDressupInfo"])
    player.onEmbeddedEvent = { _, _ in SakuraScript(rawValue: "") }
    #expect(await player.notifyDressupChanges(changes, source: "user") == nil)
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

@Test
@MainActor
func `dressup context menu follows shell menu item order titles and visibility`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(
            directory: directory,
            surfaces: [:],
            bindGroups: [
                0: [
                    10: ShellBindGroup(id: 10, category: "服", part: "コート"),
                    11: ShellBindGroup(id: 11, category: "服", part: "パーカー")
                ],
                1: [20: ShellBindGroup(id: 20, category: "帽子", part: "帽子")]
            ],
            bindMenuItems: [0: [
                .group(id: 11, title: "上着"),
                .separator,
                .group(id: 10)
            ]],
            hiddenBindMenuScopes: [1]
        ),
        scope: 0,
        surfaceID: 0
    )
    defer { controller.hideAll() }

    let root = try #require(controller.dressupContextMenuItem(title: "着せ替え"))
    guard case let .submenu(_, categories) = root,
          case let .submenu(_, items) = try #require(categories.first)
    else {
        Issue.record("expected ordered dressup menu")
        return
    }
    #expect(items.count == 3)
    guard case let .action(firstTitle, _, _, _) = items[0],
          case .separator = items[1],
          case let .action(lastTitle, _, _, _) = items[2]
    else {
        Issue.record("expected action, separator, action")
        return
    }
    #expect(firstTitle == "上着")
    #expect(lastTitle == "コート")
    #expect(categories.count == 1)
}

@Test
@MainActor
func `dressup selection persists per ghost and shell`() throws {
    let suiteName = "DressupSelectionStoreTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
    let ghost = directory.appending(path: "ghost-a", directoryHint: .isDirectory)

    do {
        let controller = SurfaceWindowController(
            dressupSelectionStore: DressupSelectionStore(defaults: defaults, namespace: suiteName)
        )
        controller.setPositionContentID(ghost)
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        _ = controller.changeBind(scope: 0, category: "服", part: "パーカー", enabled: true)
        #expect(controller.dressupInfo().first(where: { $0.group.id == 11 })?.enabled == true)
        controller.hideAll()
    }

    do {
        let controller = SurfaceWindowController(
            dressupSelectionStore: DressupSelectionStore(defaults: defaults, namespace: suiteName)
        )
        controller.setPositionContentID(ghost)
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        defer { controller.hideAll() }
        #expect(controller.dressupInfo().first(where: { $0.group.id == 10 })?.enabled == false)
        #expect(controller.dressupInfo().first(where: { $0.group.id == 11 })?.enabled == true)
    }

    do {
        let controller = SurfaceWindowController(
            dressupSelectionStore: DressupSelectionStore(defaults: defaults, namespace: suiteName)
        )
        controller.setPositionContentID(directory.appending(path: "ghost-b", directoryHint: .isDirectory))
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        defer { controller.hideAll() }
        #expect(controller.dressupInfo().first(where: { $0.group.id == 10 })?.enabled == true)
        #expect(controller.dressupInfo().first(where: { $0.group.id == 11 })?.enabled == false)
    }
}

@Test
@MainActor
func `visited anchors use the balloon visited appearance`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 200, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let controller = BalloonWindowController(positionStore: positionStore)
    let balloon = BalloonDefinition(
        directory: directory,
        name: "visited",
        originX: 10,
        originY: 10,
        wordWrapPointX: 190,
        wordWrapPointY: 10,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        anchorNotSelectedStyle: BalloonLinkAppearance(
            shape: .underline,
            fontColor: BalloonColor(red: 10, green: 20, blue: 30)
        ),
        anchorVisitedStyle: BalloonLinkAppearance(
            shape: .square,
            fontColor: BalloonColor(red: 200, green: 40, blue: 50),
            brushColor: BalloonColor(red: 1, green: 2, blue: 3)
        )
    )
    try controller.show(balloon: balloon, text: "link", near: .zero)
    defer { controller.hideAll() }
    controller.updateContent(
        text: "link",
        links: [BalloonTextLink(
            range: NSRange(location: 0, length: 4),
            id: "OnAnchor",
            arguments: [],
            kind: .anchor
        )]
    )

    let before = try #require(controller.textAttributes(at: 0, scope: 0)?[.foregroundColor] as? NSColor)
    #expect(before.redComponent < 0.1)
    controller.markAnchorVisited("OnAnchor")
    let after = try #require(controller.textAttributes(at: 0, scope: 0)?[.foregroundColor] as? NSColor)
    #expect(after.redComponent > 0.7)
    #expect(controller.textAttributes(at: 0, scope: 0)?[.backgroundColor] != nil)
}

@Test
@MainActor
func `positioned balloon images use top left coordinates`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 200, height: 100).write(to: directory.appending(path: "balloons0.png"))
    let overlay = try #require(NSImage(data: makePNG(width: 20, height: 10)))

    let controller = BalloonWindowController(positionStore: positionStore)
    let balloon = BalloonDefinition(
        directory: directory,
        name: "positioned-image",
        originX: 10,
        originY: 10,
        wordWrapPointX: 190,
        wordWrapPointY: 10,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )
    try controller.show(balloon: balloon, text: "text", near: .zero)
    defer { controller.hideAll() }
    controller.addPositionedImage(overlay, x: 50, y: 20)

    let frame = try #require(controller.positionedImageFrames(scope: 0).first)
    #expect(frame.origin.x == 50)
    #expect(frame.origin.y == 20)
    #expect(frame.size.width == 20)
    #expect(frame.size.height == 10)

    controller.clearPositionedImages(scope: 0)
    #expect(controller.positionedImageFrames(scope: 0).isEmpty)
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

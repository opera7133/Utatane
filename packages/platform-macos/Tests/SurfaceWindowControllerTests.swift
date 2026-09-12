import AppKit
import CoreText
import SwiftUI
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

@Test func `accepts NAR and ZIP files dropped on a surface`() {
    let urls = [
        URL(filePath: "/tmp/ghost.nar"),
        URL(filePath: "/tmp/SHELL.NAR"),
        URL(filePath: "/tmp/old_ghost.zip"),
        URL(filePath: "/tmp/BALLOON.ZIP"),
        URL(filePath: "/tmp/readme.txt"),
        URL(filePath: "/tmp/not-a-nar")
    ]

    #expect(SurfaceDropPayload.narURLs(from: urls).map(\.lastPathComponent) == [
        "ghost.nar", "SHELL.NAR", "old_ghost.zip", "BALLOON.ZIP"
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

    let geometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let controller = SurfaceWindowController(
        positionStore: positionStore,
        geometryProvider: geometry
    )
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

@Test
@MainActor
func `window mode hosts a surface and balloon in one capturable window`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let host = WindowModePresentationHost(contentSize: NSSize(width: 640, height: 480))
    let surfaces = SurfaceWindowController(positionStore: positionStore, presentationHost: host)
    let balloons = BalloonWindowController(positionStore: positionStore, presentationHost: host)
    defer {
        surfaces.hideAll()
        balloons.hideAll()
        host.window.orderOut(nil)
    }

    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let surfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "stage",
        near: surfaceFrame
    )

    #expect(host.itemCount == 2)
    #expect(host.rootView.presentationView.subviews.count == 2)
    #expect(surfaces.visibleScopes == [0])
    #expect(balloons.visibleScopes == [0])
    #expect(Set(surfaces.windowNumbers + balloons.windowNumbers).count == 1)
    #expect(MacOSPropertySnapshot.values(geometryProvider: host.geometryProvider)["system.monitor.index(0).rect"] == "0,0,640,480")

    host.window.setContentSize(NSSize(width: 800, height: 600))
    #expect(host.geometryProvider.mainScreen?.frame.size == NSSize(width: 800, height: 600))

    host.setBackground(.black)
    #expect(host.background == .black)
    host.setShowsWindowFrame(false)
    #expect(!host.window.styleMask.contains(.titled))
    #expect(host.window.styleMask.contains(.resizable))
    #expect(host.rootView.transientControlsAreEnabled)
    host.rootView.setPointerInside(true)
    #expect(host.rootView.transientControlButtons.allSatisfy { !$0.isHidden })
    host.setShowsWindowFrame(true)
    #expect(host.window.styleMask.contains(.titled))
    #expect(!host.rootView.transientControlsAreEnabled)
    let allTransientControlsHidden = host.rootView.transientControlButtons.allSatisfy(\.isHidden)
    #expect(allTransientControlsHidden)

    let operationMenu = host.makeOperationMenu()
    let modeMenu = try #require(operationMenu.items.first?.submenu)
    #expect(modeMenu.items.count == GhostWindowMode.allCases.count)
    #expect(modeMenu.items.filter { $0.state == NSControl.StateValue.on }.count == 1)
    #expect(operationMenu.items.contains { $0.title == String(localized: "スクリーンショット...") })
    let closeItem = try #require(operationMenu.items.first { $0.title == String(localized: "閉じる") })
    #expect(closeItem.keyEquivalent == "w")
    #expect(closeItem.keyEquivalentModifierMask == [.control])
}

@Test
@MainActor
func `presentation coordinator reparents live views between desktop and window mode`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let desktopGeometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let coordinator = PresentationHostCoordinator(
        initialHost: DesktopPresentationHost(geometryProvider: desktopGeometry)
    )
    let surfaces = SurfaceWindowController(positionStore: positionStore, presentationHost: coordinator)
    let balloons = BalloonWindowController(positionStore: positionStore, presentationHost: coordinator)
    defer {
        surfaces.hideAll()
        balloons.hideAll()
    }

    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let surfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "rehost",
        near: surfaceFrame
    )
    surfaces.onPresentationMove = { scope, delta, reason in
        balloons.moveWithSurface(by: delta, scope: scope, reason: reason)
    }
    let desktopSurfaceFrame = try #require(surfaces.windowFrame(for: 0))
    let desktopBalloonFrame = try #require(balloons.windowFrame(for: 0))
    let renderedBeforeSwitch = try #require(surfaces.renderedImage(for: 0))
    #expect(Set(surfaces.windowNumbers + balloons.windowNumbers).count == 2)

    let stage = WindowModePresentationHost(contentSize: NSSize(width: 640, height: 480))
    coordinator.switchHost(to: stage)

    #expect(stage.itemCount == 2)
    #expect(stage.rootView.presentationView.subviews.count == 2)
    #expect(Set(surfaces.windowNumbers + balloons.windowNumbers).count == 1)
    #expect(surfaces.renderedImage(for: 0) === renderedBeforeSwitch)
    #expect(coordinator.mainScreen?.frame.size == NSSize(width: 640, height: 480))
    let mappedSurfaceOrigin = try #require(mappedPresentationOrigin(
        desktopSurfaceFrame,
        from: desktopGeometry.mainScreen?.visibleFrame,
        to: stage.geometryProvider.mainScreen?.visibleFrame
    ))
    #expect(surfaces.windowFrame(for: 0)?.origin == NSPoint(x: mappedSurfaceOrigin.x, y: 0))
    #expect(balloons.windowFrame(for: 0)?.origin == mappedPresentationOrigin(
        desktopBalloonFrame,
        from: desktopGeometry.mainScreen?.visibleFrame,
        to: stage.geometryProvider.mainScreen?.visibleFrame
    ))

    coordinator.switchHost(to: DesktopPresentationHost(geometryProvider: desktopGeometry))

    #expect(stage.itemCount == 0)
    #expect(stage.rootView.presentationView.subviews.isEmpty)
    #expect(!stage.window.isVisible)
    #expect(Set(surfaces.windowNumbers + balloons.windowNumbers).count == 2)
    #expect(surfaces.renderedImage(for: 0) === renderedBeforeSwitch)
    #expect(surfaces.windowFrame(for: 0)?.origin == desktopSurfaceFrame.origin)
    #expect(balloons.windowFrame(for: 0)?.origin == desktopBalloonFrame.origin)
}

@Test
@MainActor
func `first mode switch restores saved surface and balloon positions in the destination space`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    positionStore.setContentID(URL(filePath: "/ghosts/mode-restore", directoryHint: .isDirectory))
    let desktopSurfaceOrigin = NSPoint(x: 500, y: 0)
    let desktopBalloonOrigin = NSPoint(x: 260, y: 400)
    let windowSurfaceOrigin = NSPoint(x: 420, y: 0)
    let windowBalloonOrigin = NSPoint(x: 120, y: 280)
    positionStore.save(desktopSurfaceOrigin, for: .surface, scope: 0)
    positionStore.save(desktopBalloonOrigin, for: .balloon, scope: 0)
    positionStore.save(
        windowSurfaceOrigin,
        for: .surface,
        scope: 0,
        coordinateSpace: .sharedWindowMode
    )
    positionStore.save(
        windowBalloonOrigin,
        for: .balloon,
        scope: 0,
        coordinateSpace: .sharedWindowMode
    )

    let desktopGeometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let coordinator = PresentationHostCoordinator(
        initialHost: DesktopPresentationHost(geometryProvider: desktopGeometry)
    )
    let surfaces = SurfaceWindowController(positionStore: positionStore, presentationHost: coordinator)
    let balloons = BalloonWindowController(positionStore: positionStore, presentationHost: coordinator)
    defer {
        surfaces.resetContent()
        balloons.resetContent()
    }

    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let surfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "restore",
        near: surfaceFrame
    )
    #expect(surfaces.windowFrame(for: 0)?.origin == desktopSurfaceOrigin)
    #expect(balloons.windowFrame(for: 0)?.origin == desktopBalloonOrigin)

    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: 480),
        mode: .shared
    )
    coordinator.switchHost(to: stage)
    #expect(surfaces.windowFrame(for: 0)?.origin == windowSurfaceOrigin)
    #expect(balloons.windowFrame(for: 0)?.origin == windowBalloonOrigin)

    coordinator.switchHost(to: DesktopPresentationHost(geometryProvider: desktopGeometry))
    #expect(surfaces.windowFrame(for: 0)?.origin == desktopSurfaceOrigin)
    #expect(balloons.windowFrame(for: 0)?.origin == desktopBalloonOrigin)
}

@Test
@MainActor
func `speech history is presented only inside a window mode stage and stays docked at the bottom`() {
    let desktopGeometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let coordinator = PresentationHostCoordinator(
        initialHost: DesktopPresentationHost(geometryProvider: desktopGeometry)
    )
    let item = coordinator.makeItem(
        kind: .speechHistory,
        title: "history",
        onMove: { _, _ in },
        onCancel: nil
    )
    defer { item.discard() }
    item.contentView = NSView()
    item.setContentSize(NSSize(width: 380, height: 500))
    item.show(activating: false)
    #expect(!item.isVisible)

    let firstStage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: 480),
        automaticallyExpandsForSpeechHistory: false
    )
    coordinator.switchHost(to: firstStage)
    #expect(item.isVisible)
    #expect(item.frame == NSRect(x: 0, y: 0, width: 640, height: 180))
    #expect(firstStage.geometryProvider.mainScreen?.frame == NSRect(x: 0, y: 0, width: 640, height: 300))
    #expect(firstStage.rootView.presentationView.frame == NSRect(x: 0, y: 180, width: 640, height: 300))

    firstStage.window.setContentSize(NSSize(width: 800, height: 600))
    #expect(item.frame == NSRect(x: 0, y: 0, width: 800, height: 204))
    #expect(firstStage.geometryProvider.mainScreen?.frame == NSRect(x: 0, y: 0, width: 800, height: 396))
    #expect(firstStage.rootView.presentationView.frame == NSRect(x: 0, y: 204, width: 800, height: 396))

    item.hide()
    #expect(firstStage.geometryProvider.mainScreen?.frame == NSRect(x: 0, y: 0, width: 800, height: 600))
    #expect(firstStage.rootView.presentationView.frame == NSRect(x: 0, y: 0, width: 800, height: 600))
    item.show(activating: false)

    coordinator.switchHost(to: DesktopPresentationHost(geometryProvider: desktopGeometry))
    #expect(!item.isVisible)
    #expect(!firstStage.window.isVisible)

    let secondStage = WindowModePresentationHost(
        contentSize: NSSize(width: 700, height: 500),
        automaticallyExpandsForSpeechHistory: false
    )
    coordinator.switchHost(to: secondStage)
    #expect(item.isVisible)
    #expect(item.frame == NSRect(x: 0, y: 0, width: 700, height: 180))
}

@Test
@MainActor
func `opening speech history expands the stage before reserving its panel`() {
    let stage = WindowModePresentationHost(contentSize: NSSize(width: 640, height: 480))
    let item = stage.makeItem(
        kind: .speechHistory,
        title: "history",
        onMove: { _, _ in },
        onCancel: nil
    )
    defer { item.discard() }
    item.contentView = NSView()

    item.show(activating: false)

    #expect(stage.rootView.bounds.height > 480)
    #expect(stage.rootView.presentationView.bounds.height >= 475)
    #expect(item.frame.maxY == stage.rootView.presentationView.frame.minY)
}

@Test
@MainActor
func `standalone speech history uses a practical minimum window size`() throws {
    let controller = SpeechHistoryWindowController(store: SpeechHistoryStore())
    defer { controller.close() }

    controller.show(ghostIdentifier: "ghost", ghostName: "Ghost")

    let window = try #require(controller.window)
    #expect(window.contentMinSize == SpeechHistoryWindowController.minimumContentSize)
    #expect(window.contentLayoutRect.width >= SpeechHistoryWindowController.minimumContentSize.width)
    #expect(window.contentLayoutRect.height >= SpeechHistoryWindowController.minimumContentSize.height)
}

@Test
@MainActor
func `shared window mode shows only the most recently opened speech history`() {
    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: 480),
        mode: .shared,
        automaticallyExpandsForSpeechHistory: false
    )
    let first = stage.makeItem(
        kind: .speechHistory,
        title: "first history",
        onMove: { _, _ in },
        onCancel: nil
    )
    let second = stage.makeItem(
        kind: .speechHistory,
        title: "second history",
        onMove: { _, _ in },
        onCancel: nil
    )
    defer {
        first.discard()
        second.discard()
    }

    first.show(activating: false)
    #expect(first.isVisible)
    second.show(activating: false)
    #expect(!first.isVisible)
    #expect(second.isVisible)
    first.show(activating: false)
    #expect(first.isVisible)
    #expect(!second.isVisible)
}

@Test
@MainActor
func `switching presentation modes restores each coordinate space and retires old stages`() {
    let desktopGeometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let coordinator = PresentationHostCoordinator(
        initialHost: DesktopPresentationHost(geometryProvider: desktopGeometry)
    )
    let item = coordinator.makeItem(kind: .surface, title: "surface", onMove: { _, _ in }, onCancel: nil)
    defer { item.discard() }
    item.setContentSize(NSSize(width: 80, height: 120))
    item.setFrameOrigin(NSPoint(x: 100, y: 200))
    item.show(activating: false)

    let firstSharedStage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: 480),
        mode: .shared
    )
    coordinator.switchHost(to: firstSharedStage)
    item.setFrameOrigin(NSPoint(x: 40, y: 50))

    let perGhostStage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: 480),
        mode: .perGhost
    )
    coordinator.switchHost(to: perGhostStage)
    #expect(!firstSharedStage.window.isVisible)
    item.setFrameOrigin(NSPoint(x: 80, y: 90))

    let secondSharedStage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: 480),
        mode: .shared
    )
    coordinator.switchHost(to: secondSharedStage)
    #expect(!perGhostStage.window.isVisible)
    #expect(item.frame.origin == NSPoint(x: 40, y: 50))

    coordinator.switchHost(to: DesktopPresentationHost(geometryProvider: desktopGeometry))
    #expect(!secondSharedStage.window.isVisible)
    #expect(item.frame.origin == NSPoint(x: 100, y: 200))
}

@Test
@MainActor
func `per ghost identity switch retires the previous stage`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let coordinator = PresentationCoordinator(mode: .perGhost, defaults: defaults)
    let session = coordinator.makeSession(title: "Previous", identifier: "previous")
    let surfaces = SurfaceWindowController(positionStore: positionStore, presentationSession: session)
    let balloons = BalloonWindowController(positionStore: positionStore, presentationSession: session)
    defer {
        surfaces.resetContent()
        balloons.resetContent()
    }
    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let surfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "previous",
        near: surfaceFrame
    )
    let previousWindowNumber = try #require(surfaces.windowNumbers.first)
    let previousWindow = try #require(NSApp.window(withWindowNumber: previousWindowNumber))
    #expect(previousWindow.isVisible)

    surfaces.resetContent()
    balloons.resetContent()
    session.setTitle("Next")
    session.setIdentifier("next")
    #expect(!previousWindow.isVisible)

    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let nextWindowNumber = try #require(surfaces.windowNumbers.first)
    #expect(nextWindowNumber != previousWindowNumber)
    #expect(NSApp.window(withWindowNumber: nextWindowNumber)?.isVisible == true)
    #expect(!previousWindow.isVisible)
}

@Test
@MainActor
func `releasing a ghost presentation retires its stage`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))

    let coordinator = PresentationCoordinator(mode: .perGhost, defaults: defaults)
    var session: GhostPresentationSession? = coordinator.makeSession(
        title: "Called Ghost",
        identifier: "called"
    )
    var surfaces: SurfaceWindowController? = session.map {
        SurfaceWindowController(positionStore: positionStore, presentationSession: $0)
    }
    try surfaces?.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let windowNumber = try #require(surfaces?.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: windowNumber))
    #expect(window.isVisible)

    surfaces = nil
    session = nil

    #expect(!window.isVisible)
}

@Test
@MainActor
func `window mode stage delegates close without disappearing first`() {
    var closeRequests = 0
    let stage = WindowModePresentationHost(onCloseRequest: { closeRequests += 1 })
    #expect(stage.window.standardWindowButton(.closeButton)?.isEnabled == true)
    #expect(!stage.windowShouldClose(stage.window))
    #expect(closeRequests == 1)
}

@Test
@MainActor
func `window mode screenshots can include or omit the stage background`() throws {
    let stage = WindowModePresentationHost(contentSize: NSSize(width: 20, height: 20))
    stage.setBackground(.black)
    let item = stage.makeItem(kind: .surface, title: "surface", onMove: { _, _ in }, onCancel: nil)
    defer { item.discard() }
    let image = try #require(NSImage(data: makePNG(
        width: 4,
        height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    )))
    let sourceBitmap = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    #expect(sourceBitmap.colorAt(x: 0, y: 0)?.redComponent ?? 0 > 0.8)
    let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
    imageView.image = image
    imageView.imageScaling = .scaleAxesIndependently
    item.contentView = imageView
    item.setContentSize(NSSize(width: 4, height: 4))
    item.setFrameOrigin(NSPoint(x: 8, y: 8))
    item.show(activating: false)
    stage.setShowsWindowFrame(false)
    stage.rootView.setPointerInside(true)
    #expect(stage.rootView.transientControlButtons.allSatisfy { !$0.isHidden })

    let includedData = try #require(stage.screenshotPNGData(kind: .backgroundIncluded))
    let transparentData = try #require(stage.screenshotPNGData(kind: .transparentBackground))
    let included = try #require(NSBitmapImageRep(data: includedData))
    let transparent = try #require(NSBitmapImageRep(data: transparentData))

    #expect(included.pixelsWide == transparent.pixelsWide)
    #expect(included.pixelsHigh == transparent.pixelsHigh)
    #expect(included.colorAt(x: 0, y: 0)?.alphaComponent == 1)
    #expect(transparent.colorAt(x: 0, y: 0)?.alphaComponent == 0)
    #expect(bitmapContainsRedPixel(included))
    #expect(bitmapContainsRedPixel(transparent))
}

@Test
@MainActor
func `window mode screenshot preserves balloon text orientation`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let stage = WindowModePresentationHost(contentSize: NSSize(width: 240, height: 160))
    stage.setBackground(.black)
    let balloons = BalloonWindowController(presentationHost: stage)
    defer { balloons.hideAll() }
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "TOP line\nsecond line",
        near: NSRect(x: 100, y: 40, width: 40, height: 80)
    )
    let itemFrame = try #require(balloons.windowFrame(for: 0))
    let container = try #require(stage.presentationItemViews.first)
    container.layoutSubtreeIfNeeded()
    let expected = try #require(container.bitmapImageRepForCachingDisplay(in: container.bounds))
    container.cacheDisplay(in: container.bounds, to: expected)

    let data = try #require(stage.screenshotPNGData(kind: .transparentBackground))
    let actual = try #require(NSBitmapImageRep(data: data))
    let scale = CGFloat(actual.pixelsWide) / stage.rootView.bounds.width
    let normalDifference = bitmapDifference(
        actual,
        itemOrigin: itemFrame.origin,
        expected: expected,
        scale: scale,
        flipsExpectedVertically: false
    )
    let flippedDifference = bitmapDifference(
        actual,
        itemOrigin: itemFrame.origin,
        expected: expected,
        scale: scale,
        flipsExpectedVertically: true
    )
    #expect(normalDifference < flippedDifference)
}

@Test
@MainActor
func `window mode screenshot includes the docked speech history boundaries`() throws {
    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 320, height: 240),
        automaticallyExpandsForSpeechHistory: false
    )
    stage.setBackground(.black)
    let store = SpeechHistoryStore()
    let talkIdentifier = UUID()
    store.append(SpeechHistoryEntry(
        talkIdentifier: talkIdentifier,
        ghostIdentifier: "ghost",
        ghostName: "Ghost",
        scope: 0,
        speakerName: "Sakura",
        surfaceID: 0,
        text: "first"
    ))
    store.append(SpeechHistoryEntry(
        talkIdentifier: talkIdentifier,
        ghostIdentifier: "ghost",
        ghostName: "Ghost",
        scope: 1,
        speakerName: "Kero",
        surfaceID: 1,
        text: "last"
    ))
    let item = stage.makeItem(
        kind: .speechHistory,
        title: "history",
        onMove: { _, _ in },
        onCancel: nil
    )
    defer { item.discard() }
    item.contentView = NSHostingView(rootView: SpeechHistoryView(
        store: store,
        ghostIdentifier: "ghost",
        ghostName: "Ghost",
        showsHeader: false
    ))
    item.show(activating: false)
    stage.rootView.layoutSubtreeIfNeeded()

    #expect(item.frame == NSRect(x: 0, y: 0, width: 320, height: 180))
    let data = try #require(stage.screenshotPNGData(kind: .transparentBackground))
    let bitmap = try #require(NSBitmapImageRep(data: data))
    #expect(bitmapContainsRedAccentPixel(bitmap))
}

@Test
@MainActor
func `desktop wallpaper background follows provider changes and screenshot transparency`() throws {
    let firstImage = try #require(NSImage(data: makePNG(
        width: 4,
        height: 4,
        color: NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
    )))
    let secondImage = try #require(NSImage(data: makePNG(
        width: 4,
        height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    )))
    let provider = StubDesktopWallpaperProvider(snapshot: WindowModeDesktopWallpaperSnapshot(
        image: firstImage,
        url: URL(fileURLWithPath: "/tmp/first.png"),
        scaling: .scaleAxesIndependently,
        allowsClipping: false,
        fillColor: .black,
        signature: "first"
    ))
    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 20, height: 20),
        desktopWallpaperProvider: provider
    )
    defer { stage.window.orderOut(nil) }

    #expect(stage.background == .desktop)
    #expect(stage.rootView.desktopWallpaper?.signature == "first")
    let includedData = try #require(stage.screenshotPNGData(kind: .backgroundIncluded))
    let transparentData = try #require(stage.screenshotPNGData(kind: .transparentBackground))
    let included = try #require(NSBitmapImageRep(data: includedData))
    let transparent = try #require(NSBitmapImageRep(data: transparentData))
    #expect(included.colorAt(x: 0, y: 0)?.greenComponent ?? 0 > 0.8)
    #expect(transparent.colorAt(x: 0, y: 0)?.alphaComponent == 0)

    provider.currentSnapshot = WindowModeDesktopWallpaperSnapshot(
        image: secondImage,
        url: URL(fileURLWithPath: "/tmp/second.png"),
        scaling: .scaleAxesIndependently,
        allowsClipping: false,
        fillColor: .black,
        signature: "second"
    )
    #expect(stage.refreshDesktopWallpaper())
    #expect(stage.rootView.desktopWallpaper?.signature == "second")
    #expect(!stage.refreshDesktopWallpaper())
}

@Test
@MainActor
func `desktop wallpaper stays out of the speech history area`() throws {
    let wallpaper = try #require(NSImage(data: makePNG(
        width: 4,
        height: 4,
        color: NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
    )))
    let provider = StubDesktopWallpaperProvider(snapshot: WindowModeDesktopWallpaperSnapshot(
        image: wallpaper,
        url: URL(fileURLWithPath: "/tmp/wallpaper.png"),
        scaling: .scaleAxesIndependently,
        allowsClipping: false,
        fillColor: .black,
        signature: "wallpaper"
    ))
    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 320, height: 240),
        desktopWallpaperProvider: provider,
        automaticallyExpandsForSpeechHistory: false
    )
    defer { stage.window.orderOut(nil) }
    stage.rootView.setSpeechHistoryHeight(120)

    let data = try #require(stage.screenshotPNGData(kind: .backgroundIncluded))
    let bitmap = try #require(NSBitmapImageRep(data: data))
    let colors = [bitmap.pixelsHigh / 4, bitmap.pixelsHigh * 3 / 4].compactMap {
        bitmap.colorAt(x: bitmap.pixelsWide / 2, y: $0)?.usingColorSpace(.deviceRGB)
    }
    let wallpaperSamples = colors.filter {
        $0.greenComponent > 0.8 && $0.redComponent < 0.2 && $0.blueComponent < 0.2
    }

    #expect(colors.count == 2)
    #expect(wallpaperSamples.count == 1)
}

@Test
@MainActor
func `desktop wallpaper layout respects system scaling options`() {
    let bounds = NSRect(x: 0, y: 0, width: 200, height: 100)
    let imageSize = NSSize(width: 100, height: 100)
    #expect(WindowModeDesktopWallpaperRenderer.destinationRect(
        imageSize: imageSize,
        bounds: bounds,
        scaling: .scaleAxesIndependently,
        allowsClipping: false
    ) == bounds)
    #expect(WindowModeDesktopWallpaperRenderer.destinationRect(
        imageSize: imageSize,
        bounds: bounds,
        scaling: .scaleProportionallyUpOrDown,
        allowsClipping: false
    ) == NSRect(x: 50, y: 0, width: 100, height: 100))
    #expect(WindowModeDesktopWallpaperRenderer.destinationRect(
        imageSize: imageSize,
        bounds: bounds,
        scaling: .scaleProportionallyUpOrDown,
        allowsClipping: true
    ) == NSRect(x: 0, y: -50, width: 200, height: 200))
}

@Test
@MainActor
func `presentation modes share one stage or separate stages without replacing rendered views`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))

    let systemGeometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let coordinator = PresentationCoordinator(systemGeometry: systemGeometry)
    let firstSession = coordinator.makeSession(title: "First")
    let secondSession = coordinator.makeSession(title: "Second")
    let first = SurfaceWindowController(presentationSession: firstSession)
    let second = SurfaceWindowController(presentationSession: secondSession)
    defer {
        first.hideAll()
        second.hideAll()
    }
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try first.show(shell: shell, surfaceID: 0)
    try second.show(shell: shell, surfaceID: 0)
    let firstImage = try #require(first.renderedImage())
    let secondImage = try #require(second.renderedImage())

    #expect(Set(first.windowNumbers + second.windowNumbers).count == 2)

    coordinator.setMode(.shared)
    #expect(Set(first.windowNumbers + second.windowNumbers).count == 1)
    #expect(first.renderedImage() === firstImage)
    #expect(second.renderedImage() === secondImage)

    coordinator.setMode(.perGhost)
    #expect(Set(first.windowNumbers + second.windowNumbers).count == 2)
    #expect(first.renderedImage() === firstImage)
    #expect(second.renderedImage() === secondImage)

    coordinator.setMode(.off)
    #expect(Set(first.windowNumbers + second.windowNumbers).count == 2)
    #expect(first.renderedImage() === firstImage)
    #expect(second.renderedImage() === secondImage)
}

@Test
func `window mode launch option supports SSP mode names and the previous layout`() {
    #expect(GhostWindowMode.launchOverride(in: ["Utatane"]) == nil)
    #expect(GhostWindowMode.launchOverride(in: ["Utatane", "--windowmode"]) == .shared)
    #expect(GhostWindowMode.launchOverride(
        in: ["Utatane", "--windowmode"],
        previousLayout: .perGhost
    ) == .perGhost)
    #expect(GhostWindowMode.launchOverride(in: ["Utatane", "--windowmode=shared"]) == .shared)
    #expect(GhostWindowMode.launchOverride(in: ["Utatane", "--windowmode=perghost"]) == .perGhost)
    #expect(GhostWindowMode.launchOverride(in: ["Utatane", "--windowmode=invalid"]) == nil)
}

@Test
func `window mode stage appearance is persisted per stage identifier`() throws {
    let suiteName = "WindowModeStageTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WindowModeStageStateStore(defaults: defaults, namespace: "stage-test")
    let shared = WindowModeStageState(
        contentSize: NSSize(width: 800, height: 600),
        origin: NSPoint(x: 120, y: 90),
        background: .black,
        showsWindowFrame: false
    )
    let perGhost = WindowModeStageState(
        contentSize: NSSize(width: 640, height: 480),
        origin: nil,
        background: .white,
        showsWindowFrame: true
    )

    store.save(shared, identifier: "shared")
    store.save(perGhost, identifier: "per-ghost:/ghosts/a")

    let restoredShared = try #require(store.load(identifier: "shared"))
    let restoredPerGhost = try #require(store.load(identifier: "per-ghost:/ghosts/a"))
    #expect(restoredShared.contentSize == shared.contentSize)
    #expect(restoredShared.origin == shared.origin)
    #expect(restoredShared.background == .black)
    #expect(!restoredShared.showsWindowFrame)
    #expect(restoredPerGhost.contentSize == perGhost.contentSize)
    #expect(restoredPerGhost.origin == nil)
    #expect(restoredPerGhost.background == .white)
    #expect(restoredPerGhost.showsWindowFrame)
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
func `speech history updates the current entry while text is being displayed`() {
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
    #expect(history.entries.first?.text == "一言")

    recorder.setScope(1)
    recorder.append("返")
    #expect(history.entries.map(\.text) == ["一言", "返"])
    #expect(Set(history.entries.map(\.talkIdentifier)).count == 1)
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
@MainActor
func `keeps desktop and both window mode positions separate`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

    positionStore.save(
        NSPoint(x: 100, y: 200),
        for: .surface,
        scope: 0,
        coordinateSpace: .desktop
    )
    positionStore.save(
        NSPoint(x: 20, y: 30),
        for: .surface,
        scope: 0,
        coordinateSpace: .sharedWindowMode
    )
    positionStore.save(
        NSPoint(x: 40, y: 50),
        for: .surface,
        scope: 0,
        coordinateSpace: .perGhostWindowMode
    )

    let desktopOrigin = positionStore.restoredOrigin(
        for: .surface,
        scope: 0,
        windowSize: NSSize(width: 50, height: 50),
        screens: [],
        coordinateSpace: .desktop
    )
    let sharedWindowModeOrigin = positionStore.restoredOrigin(
        for: .surface,
        scope: 0,
        windowSize: NSSize(width: 50, height: 50),
        screens: [],
        coordinateSpace: .sharedWindowMode
    )
    let perGhostWindowModeOrigin = positionStore.restoredOrigin(
        for: .surface,
        scope: 0,
        windowSize: NSSize(width: 50, height: 50),
        screens: [],
        coordinateSpace: .perGhostWindowMode
    )

    #expect(desktopOrigin == NSPoint(x: 100, y: 200))
    #expect(sharedWindowModeOrigin == NSPoint(x: 20, y: 30))
    #expect(perGhostWindowModeOrigin == NSPoint(x: 40, y: 50))
}

@Test
@MainActor
func `startup content sizing does not overwrite restored desktop positions`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let contentID = URL(filePath: "/ghosts/restart", directoryHint: .isDirectory)
    positionStore.setContentID(contentID)
    let surfaceOrigin = NSPoint(x: 320, y: 180)
    let balloonOrigin = NSPoint(x: 90, y: 520)
    positionStore.save(surfaceOrigin, for: .surface, scope: 0)
    positionStore.save(balloonOrigin, for: .balloon, scope: 0)
    let geometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let surfaces = SurfaceWindowController(positionStore: positionStore, geometryProvider: geometry)
    let balloons = BalloonWindowController(positionStore: positionStore, geometryProvider: geometry)
    defer {
        surfaces.resetContent()
        balloons.resetContent()
    }
    surfaces.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)

    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let restoredSurfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "restored",
        near: restoredSurfaceFrame
    )

    #expect(surfaces.windowFrame(for: 0)?.origin == surfaceOrigin)
    #expect(balloons.windowFrame(for: 0)?.origin == balloonOrigin)
}

@Test
@MainActor
func `automatic desktop layout is not saved as a user position`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 70, height: 110).write(to: directory.appending(path: "surface0001.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    positionStore.setContentID(URL(filePath: "/ghosts/automatic-layout", directoryHint: .isDirectory))
    let geometry = MutablePresentationGeometryProvider(screens: [
        PresentationScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 760),
            bitsPerPixel: 32,
            scale: 2,
            isPrimary: true
        )
    ])
    let surfaces = SurfaceWindowController(positionStore: positionStore, geometryProvider: geometry)
    let balloons = BalloonWindowController(positionStore: positionStore, geometryProvider: geometry)
    defer {
        surfaces.resetContent()
        balloons.resetContent()
    }

    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let surfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(balloon: makeBalloon(directory: directory), text: "first", near: surfaceFrame)
    try surfaces.changeSurface(scope: 0, to: 1)
    let changedSurfaceFrame = try #require(surfaces.windowFrame(for: 0))
    try balloons.show(
        balloon: makeBalloon(directory: directory),
        text: "resized",
        near: changedSurfaceFrame
    )

    #expect(positionStore.restoredOrigin(
        for: .surface,
        scope: 0,
        windowSize: NSSize(width: 70, height: 110),
        visibleFrames: geometry.visibleFrames
    ) == nil)
    #expect(positionStore.restoredOrigin(
        for: .balloon,
        scope: 0,
        windowSize: NSSize(width: 160, height: 100),
        visibleFrames: geometry.visibleFrames
    ) == nil)
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
    #expect(balloonController.visibleScopes.isEmpty)
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
    let geometry = MutablePresentationGeometryProvider(
        screens: [
            PresentationScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 960, height: 540),
                visibleFrame: CGRect(x: 0, y: 0, width: 960, height: 520),
                bitsPerPixel: 32,
                scale: 2,
                isPrimary: true
            )
        ]
    )
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController,
        geometryProvider: geometry
    )
    player.configure(environmentVariables: ["selfname": "さくら"])
    player.onEmbeddedEvent = { id, arguments in
        #expect(id == "OnRaised")
        #expect(arguments == ["arg"])
        return SakuraScript(rawValue: "応答\\e")
    }

    await player.playAndWait(
        SakuraScript(rawValue: #"%selfnameと%me（%screenwidth×%screenheight）から\![raise,OnRaised,arg]捨てる\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let content = try #require(balloonController.textAndLinks(for: 0))
    #expect(content.0.hasPrefix("さくらと"))
    #expect(content.0.contains("960×540"))
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

private func bitmapContainsRedPixel(_ bitmap: NSBitmapImageRep) -> Bool {
    for y in 0 ..< bitmap.pixelsHigh {
        for x in 0 ..< bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.redComponent > 0.8, color.greenComponent < 0.2, color.blueComponent < 0.2,
               color.alphaComponent > 0.8
            {
                return true
            }
        }
    }
    return false
}

private func bitmapContainsRedAccentPixel(_ bitmap: NSBitmapImageRep) -> Bool {
    for y in 0 ..< bitmap.pixelsHigh {
        for x in 0 ..< bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.redComponent > color.greenComponent + 0.2,
               color.redComponent > color.blueComponent + 0.2,
               color.alphaComponent > 0.5
            {
                return true
            }
        }
    }
    return false
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
private final class StubDesktopWallpaperProvider: WindowModeDesktopWallpaperProviding {
    var currentSnapshot: WindowModeDesktopWallpaperSnapshot?

    init(snapshot: WindowModeDesktopWallpaperSnapshot?) {
        currentSnapshot = snapshot
    }

    func snapshot(for screen: NSScreen?) -> WindowModeDesktopWallpaperSnapshot? {
        currentSnapshot
    }
}

private func mappedPresentationOrigin(
    _ itemFrame: NSRect,
    from oldVisibleFrame: NSRect?,
    to newVisibleFrame: NSRect?
) -> NSPoint? {
    guard let oldVisibleFrame, let newVisibleFrame else { return nil }
    let normalizedX = (itemFrame.midX - oldVisibleFrame.minX) / oldVisibleFrame.width
    let normalizedY = (itemFrame.midY - oldVisibleFrame.minY) / oldVisibleFrame.height
    return NSPoint(
        x: newVisibleFrame.minX + normalizedX * newVisibleFrame.width - itemFrame.width / 2,
        y: newVisibleFrame.minY + normalizedY * newVisibleFrame.height - itemFrame.height / 2
    )
}

private func bitmapDifference(
    _ actual: NSBitmapImageRep,
    itemOrigin: NSPoint,
    expected: NSBitmapImageRep,
    scale: CGFloat,
    flipsExpectedVertically: Bool
) -> Double {
    var difference = 0.0
    let originX = Int((itemOrigin.x * scale).rounded())
    let originY = Int((itemOrigin.y * scale).rounded())
    for y in 0 ..< expected.pixelsHigh {
        let expectedY = flipsExpectedVertically ? expected.pixelsHigh - y - 1 : y
        for x in 0 ..< expected.pixelsWide {
            guard let lhs = actual.colorAt(x: originX + x, y: originY + y)?.usingColorSpace(.deviceRGB),
                  let rhs = expected.colorAt(x: x, y: expectedY)?.usingColorSpace(.deviceRGB)
            else { continue }
            difference += abs(Double(lhs.redComponent - rhs.redComponent))
                + abs(Double(lhs.greenComponent - rhs.greenComponent))
                + abs(Double(lhs.blueComponent - rhs.blueComponent))
                + abs(Double(lhs.alphaComponent - rhs.alphaComponent))
        }
    }
    return difference
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

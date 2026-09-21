import AppKit
import CoreText
import SwiftUI
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

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
    let backgroundMenu = try #require(operationMenu.items.first {
        $0.title == String(localized: "背景")
    }?.submenu)
    #expect(backgroundMenu.items.contains { $0.title == String(localized: "画像を選択...") })
    #expect(operationMenu.items.contains {
        $0.title == String(localized: "発話履歴の背景")
    })
    let integratesHistory = try #require(operationMenu.items.first {
        $0.title == String(localized: "発話履歴をウィンドウ内に表示")
    })
    #expect(integratesHistory.state == .on)
    host.setIntegratesSpeechHistory(false)
    let updatedIntegration = try #require(host.makeOperationMenu().items.first {
        $0.title == String(localized: "発話履歴をウィンドウ内に表示")
    })
    #expect(updatedIntegration.state == .off)
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
    let initialPresentationHeight: CGFloat = 320
    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 640, height: initialPresentationHeight)
    )
    let item = stage.makeItem(
        kind: .speechHistory,
        title: "history",
        onMove: { _, _ in },
        onCancel: nil
    )
    defer { item.discard() }
    item.contentView = NSView()

    item.show(activating: false)

    #expect(stage.rootView.bounds.height > initialPresentationHeight)
    #expect(stage.rootView.presentationView.bounds.height >= initialPresentationHeight - 5)
    #expect(item.frame.maxY == stage.rootView.presentationView.frame.minY)
}

@Test
@MainActor
func `standalone speech history uses a practical minimum window size`() {
    let controller = SpeechHistoryWindowController(
        store: SpeechHistoryStore(),
        frameAutosaveName: nil
    )
    defer { controller.close() }

    let window = controller.prepareWindow(ghostIdentifier: "ghost", ghostName: "Ghost")
    #expect(window.contentMinSize == SpeechHistoryWindowController.minimumContentSize)
    #expect(window.contentLayoutRect.width >= SpeechHistoryWindowController.minimumContentSize.width)
    #expect(window.contentLayoutRect.height >= SpeechHistoryWindowController.minimumContentSize.height)
}

@Test
@MainActor
func `standalone speech history keeps its size when reopened`() {
    let controller = SpeechHistoryWindowController(
        store: SpeechHistoryStore(),
        frameAutosaveName: nil
    )
    defer { controller.close() }

    let window = controller.prepareWindow(ghostIdentifier: "ghost", ghostName: "Ghost")
    let resizedContentSize = NSSize(width: 840, height: 700)
    window.setContentSize(resizedContentSize)
    window.close()
    #expect(window.contentViewController == nil)

    let reopenedWindow = controller.prepareWindow(ghostIdentifier: "ghost", ghostName: "Ghost")

    #expect(reopenedWindow === window)
    #expect(abs(reopenedWindow.contentLayoutRect.width - resizedContentSize.width) < 1)
    #expect(abs(reopenedWindow.contentLayoutRect.height - resizedContentSize.height) < 1)
    #expect(reopenedWindow.contentViewController != nil)
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
func `releasing a ghost presentation retires its stage`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 40, height: 80).write(to: directory.appending(path: "surface0000.png"))

    let window = try makeReleasedPresentationWindow(
        directory: directory,
        positionStore: positionStore,
        defaults: defaults
    )

    try await requireEventually {
        !window.isVisible
    }
}

@MainActor
private func makeReleasedPresentationWindow(
    directory: URL,
    positionStore: WindowPositionStore,
    defaults: UserDefaults
) throws -> NSWindow {
    let coordinator = PresentationCoordinator(mode: .perGhost, defaults: defaults)
    let session = coordinator.makeSession(
        title: "Called Ghost",
        identifier: "called"
    )
    let surfaces = SurfaceWindowController(positionStore: positionStore, presentationSession: session)
    try surfaces.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    let windowNumber = try #require(surfaces.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: windowNumber))
    #expect(window.isVisible)
    return window
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
func `custom image background supports layout and keeps speech history on a solid background`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let imageURL = directory.appending(path: "background.png")
    try makePNG(
        width: 8,
        height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: imageURL)

    let stage = WindowModePresentationHost(
        contentSize: NSSize(width: 40, height: 40),
        automaticallyExpandsForSpeechHistory: false
    )
    defer { stage.window.orderOut(nil) }

    #expect(stage.setBackgroundImage(imageURL))
    stage.setBackgroundImageLayout(.stretch)
    stage.setSpeechHistoryBackground(.black)
    stage.rootView.setSpeechHistoryHeight(20)

    #expect(stage.background == .image)
    #expect(stage.backgroundImageURL == imageURL.standardizedFileURL)
    #expect(stage.backgroundImageLayout == .stretch)
    #expect(stage.speechHistoryBackground == .black)

    let data = try #require(stage.screenshotPNGData(kind: .backgroundIncluded))
    let bitmap = try #require(NSBitmapImageRep(data: data))
    let samples = [bitmap.pixelsHigh / 4, bitmap.pixelsHigh * 3 / 4].compactMap {
        bitmap.colorAt(x: bitmap.pixelsWide / 2, y: $0)?.usingColorSpace(.deviceRGB)
    }
    #expect(samples.count == 2)
    #expect(samples.contains { $0.redComponent > 0.8 && $0.greenComponent < 0.2 })
    #expect(samples.contains {
        $0.redComponent < 0.2 && $0.greenComponent < 0.2 && $0.blueComponent < 0.2
    })
}

@Test
@MainActor
func `desktop wallpaper stays out of history and scales to the presentation area`() throws {
    let wallpaper = try #require(NSImage(data: makePNG(
        width: 4,
        height: 4,
        color: NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
    )))
    let provider = StubDesktopWallpaperProvider(snapshot: WindowModeDesktopWallpaperSnapshot(
        image: wallpaper,
        url: URL(fileURLWithPath: "/tmp/wallpaper.png"),
        scaling: .scaleProportionallyUpOrDown,
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
    let edgeColors = [bitmap.pixelsHigh / 4, bitmap.pixelsHigh * 3 / 4].compactMap {
        bitmap.colorAt(x: bitmap.pixelsWide * 3 / 16, y: $0)?.usingColorSpace(.deviceRGB)
    }
    let wallpaperSamples = colors.filter {
        $0.greenComponent > 0.8 && $0.redComponent < 0.2 && $0.blueComponent < 0.2
    }
    let edgeWallpaperSamples = edgeColors.filter {
        $0.greenComponent > 0.8 && $0.redComponent < 0.2 && $0.blueComponent < 0.2
    }

    #expect(colors.count == 2)
    #expect(edgeColors.count == 2)
    #expect(wallpaperSamples.count == 1)
    #expect(edgeWallpaperSamples.isEmpty)
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
func `window mode change detector reports SSP update references and skips initial state`() {
    #expect(GhostWindowMode.off.sspIdentifier == "normal")
    #expect(GhostWindowMode.shared.sspIdentifier == "shared")
    #expect(GhostWindowMode.perGhost.sspIdentifier == "perghost")
    #expect(GhostWindowMode.shared.startupChangeReferences == [0: "init", 1: "shared", 2: ""])

    var detector = WindowModeChangeDetector()
    #expect(detector.consume(.off) == nil)
    #expect(detector.consume(.off) == nil)
    #expect(detector.consume(.shared) == [0: "update", 1: "shared", 2: "normal"])
    #expect(detector.consume(.perGhost) == [0: "update", 1: "perghost", 2: "shared"])
    #expect(detector.consume(.off) == [0: "update", 1: "normal", 2: "perghost"])
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
        background: .image,
        showsWindowFrame: false,
        backgroundImagePath: "/tmp/stage.png",
        backgroundImageLayout: .fit,
        speechHistoryBackground: .black
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
    #expect(restoredShared.background == .image)
    #expect(!restoredShared.showsWindowFrame)
    #expect(restoredShared.backgroundImagePath == "/tmp/stage.png")
    #expect(restoredShared.backgroundImageLayout == .fit)
    #expect(restoredShared.speechHistoryBackground == .black)
    #expect(restoredPerGhost.contentSize == perGhost.contentSize)
    #expect(restoredPerGhost.origin == nil)
    #expect(restoredPerGhost.background == .white)
    #expect(restoredPerGhost.showsWindowFrame)
    #expect(restoredPerGhost.backgroundImagePath == nil)
    #expect(restoredPerGhost.backgroundImageLayout == .fill)
    #expect(restoredPerGhost.speechHistoryBackground == .automatic)
}

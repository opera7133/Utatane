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

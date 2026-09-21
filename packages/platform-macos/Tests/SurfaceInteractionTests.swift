import AppKit
import CoreText
import SwiftUI
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

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
    func `image color collision regions drive mouse events`() throws {
        let (defaults, positionStore) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-region-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try makePNG(width: 20, height: 20).write(to: directory.appending(path: "surface0.png"))
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 80, bitsPerPixel: 32
        ))
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        for y in 0 ..< 20 {
            for x in 0 ..< 20 {
                bitmap.setColor(y < 10 ? red : blue, atX: x, y: y)
            }
        }
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appending(path: "hit.png"))
        let collisions = [
            SurfaceCollision(
                id: 0, left: 0, top: 0, right: 0, bottom: 0, name: "Red",
                shape: .region(filename: "hit.png", red: 255, green: 0, blue: 0, inverted: false)
            ),
            SurfaceCollision(
                id: 1, left: 0, top: 0, right: 0, bottom: 0, name: "NotRed",
                shape: .region(filename: "hit.png", red: 255, green: 0, blue: 0, inverted: true)
            )
        ]
        let shell = ShellDefinition(
            directory: directory,
            surfaces: [0: SurfaceDefinition(id: 0, collisions: collisions, animations: [])]
        )
        let controller = SurfaceWindowController(positionStore: positionStore)
        controller.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        defer { controller.hideAll() }
        let windowNumber = try #require(controller.windowNumbers.first)
        let window = try #require(NSApp.window(withWindowNumber: windowNumber))
        window.setFrameOrigin(NSPoint(x: 200, y: 200))
        let view = try #require(window.contentView)
        var clicks: [String?] = []
        controller.onMouseEvent = { event in
            if event.kind == .click {
                clicks.append(event.region)
            }
        }

        let redPoint = NSPoint(x: window.frame.minX + 5, y: window.frame.maxY - 5)
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: redPoint, window: window))
        try view.mouseUp(with: surfaceDragEvent(.leftMouseUp, pointer: redPoint, window: window))
        let bluePoint = NSPoint(x: window.frame.minX + 5, y: window.frame.maxY - 15)
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: bluePoint, window: window))
        try view.mouseUp(with: surfaceDragEvent(.leftMouseUp, pointer: bluePoint, window: window))

        #expect(clicks == ["Red", "NotRed"])
    }

    @Test @MainActor
    func `surface input emits boundary down double click and hover events`() async throws {
        let fixture = try makeSurfaceDragFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let window = fixture.window
        let view = try #require(window.contentView)
        let pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        var events: [GhostMouseEvent] = []
        controller.onMouseEvent = { events.append($0) }

        let movement = try surfaceDragEvent(.mouseMoved, pointer: pointer, window: window)
        view.mouseEntered(with: movement)
        view.mouseExited(with: movement)
        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: pointer, window: window, clickCount: 2))
        try view.mouseUp(with: surfaceDragEvent(.leftMouseUp, pointer: pointer, window: window, clickCount: 2))
        try view.otherMouseDown(with: surfaceDragEvent(.otherMouseDown, pointer: pointer, window: window, clickCount: 2))
        try view.otherMouseUp(with: surfaceDragEvent(.otherMouseUp, pointer: pointer, window: window, clickCount: 2))
        view.mouseMoved(with: movement)
        try await requireEventually {
            events.contains { $0.kind == .hover }
        }

        #expect(events.contains { $0.kind == .enterAll })
        #expect(events.contains { $0.kind == .leaveAll })
        #expect(events.contains { $0.kind == .down && $0.button == 0 })
        #expect(events.contains { $0.kind == .up && $0.button == 0 })
        #expect(events.contains { $0.kind == .doubleClick && $0.button == 0 })
        #expect(events.contains { $0.kind == .down && $0.button == 2 })
        #expect(events.contains { $0.kind == .doubleClick && $0.button == 2 })
        #expect(events.contains { $0.kind == .hover })
    }

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

    @Test @MainActor
    func `user desktop bottom lock overrides free shell alignment at startup`() throws {
        let (defaults, positionStore) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "utatane-bottom-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try makePNG(width: 80, height: 120).write(to: directory.appending(path: "surface0.png"))
        let shell = ShellDefinition(
            directory: directory,
            surfaces: [:],
            surfaceTable: nil,
            maximumSurfaceWidth: nil,
            desktopAlignment: .free
        )
        let controller = SurfaceWindowController(positionStore: positionStore, interactionHoverDelay: 0)
        controller.setPlacement(locksToDesktopBottom: true, keepsOnScreen: true)
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        defer { controller.hideAll() }
        let windowNumber = try #require(controller.windowNumbers.first)
        let window = try #require(NSApp.window(withWindowNumber: windowNumber))
        let view = try #require(window.contentView)
        let start = window.frame
        let pointer = NSPoint(x: start.midX, y: start.midY)

        try view.mouseDown(with: surfaceDragEvent(.leftMouseDown, pointer: pointer, window: window))
        try view.mouseDragged(with: surfaceDragEvent(
            .leftMouseDragged,
            pointer: NSPoint(x: pointer.x + 30, y: pointer.y + 80),
            window: window
        ))

        #expect(window.frame.minX == start.minX + 30)
        #expect(window.frame.minY == start.minY)
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

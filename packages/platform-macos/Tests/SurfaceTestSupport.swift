import AppKit
import CoreText
import SwiftUI
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

extension NSImage {
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

    func containsColor(_ predicate: (NSColor) -> Bool) -> Bool {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else { return false }
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if predicate(color) {
                    return true
                }
            }
        }
        return false
    }
}

@MainActor
func makePNG(
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

func bitmapContainsRedPixel(_ bitmap: NSBitmapImageRep) -> Bool {
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

func bitmapContainsRedAccentPixel(_ bitmap: NSBitmapImageRep) -> Bool {
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

func makeTopLeftKeyedPNG(width: Int, height: Int) throws -> Data {
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

func makeBalloon(directory: URL) -> BalloonDefinition {
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
func makePositionStore() -> (UserDefaults, WindowPositionStore) {
    let suiteName = "dev.utatane.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(suiteName, forKey: "test-suite-name")
    return (defaults, WindowPositionStore(defaults: defaults, namespace: "positions"))
}

func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "test-suite-name")!
}

@MainActor
struct SurfaceDragFixture {
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
final class StubDesktopWallpaperProvider: WindowModeDesktopWallpaperProviding {
    var currentSnapshot: WindowModeDesktopWallpaperSnapshot?

    init(snapshot: WindowModeDesktopWallpaperSnapshot?) {
        currentSnapshot = snapshot
    }

    func snapshot(for screen: NSScreen?) -> WindowModeDesktopWallpaperSnapshot? {
        currentSnapshot
    }
}

func mappedPresentationOrigin(
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

func bitmapDifference(
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
func makeSurfaceDragFixture() throws -> SurfaceDragFixture {
    let (defaults, positionStore) = makePositionStore()
    let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-drag-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 80, height: 120).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 80, height: 120).write(to: directory.appending(path: "surface1.png"))
    let controller = SurfaceWindowController(positionStore: positionStore, interactionHoverDelay: 0)
    controller.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:]), scope: 0, surfaceID: 0)
    let number = try #require(controller.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: number))
    window.setFrameOrigin(NSPoint(x: 200, y: 200))
    return SurfaceDragFixture(directory: directory, defaults: defaults, controller: controller, window: window)
}

@MainActor
func surfaceDragEvent(
    _ type: NSEvent.EventType,
    pointer: NSPoint,
    window: NSWindow,
    clickCount: Int = 1
) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
        with: type, location: window.convertPoint(fromScreen: pointer), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
    ))
}

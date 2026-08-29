import AppKit
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS

@Test
@MainActor
func `uses top left pixel as transparency key without PNA`() throws {
    let source = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 8,
        bitsPerPixel: 32
    ))
    let keyColor = NSColor(deviceRed: 1, green: 0, blue: 1, alpha: 1)
    let contentColor = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    let nonKeyColor = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    for y in 0 ..< 2 {
        for x in 0 ..< 2 {
            source.setColor(nonKeyColor, atX: x, y: y)
        }
    }
    source.setColor(keyColor, atX: 0, y: 0)
    source.setColor(keyColor, atX: 1, y: 1)
    source.setColor(contentColor, atX: 1, y: 0)
    // Simulates a 400 DPI image: 2 px is only 0.36 pt at 72 points per inch.
    source.size = NSSize(width: 0.36, height: 0.36)
    let sourceImage = NSImage(size: source.size)
    sourceImage.addRepresentation(source)

    let image = try SurfaceImageLoader().applyingTopLeftTransparency(to: sourceImage)
    #expect(image.size == NSSize(width: 2, height: 2))
    let tiff = try #require(image.tiffRepresentation)
    let output = try #require(NSBitmapImageRep(data: tiff))
    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
    #expect((output.colorAt(x: 1, y: 1)?.alphaComponent ?? 1) == 0)
    #expect((output.colorAt(x: 0, y: 1)?.alphaComponent ?? 0) > 0.9)
    #expect((output.colorAt(x: 1, y: 0)?.alphaComponent ?? 0) > 0.9)
}

@Test
@MainActor
func `preserves embedded alpha instead of keying opaque pixels with the same decoded color`() throws {
    let source = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 1,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 8,
        bitsPerPixel: 32
    ))
    source.setColor(NSColor(deviceRed: 0.8, green: 0.8, blue: 0.8, alpha: 0), atX: 0, y: 0)
    source.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1), atX: 1, y: 0)
    let sourceImage = NSImage(size: NSSize(width: 2, height: 1))
    sourceImage.addRepresentation(source)

    let image = try SurfaceImageLoader().applyingTopLeftTransparency(to: sourceImage)
    let tiff = try #require(image.tiffRepresentation)
    let output = try #require(NSBitmapImageRep(data: tiff))
    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
    #expect((output.colorAt(x: 1, y: 0)?.alphaComponent ?? 0) > 0.9)
}

@Test
func `maps both SERIKO overlay fast spellings to source atop`() {
    #expect(surfaceCompositingOperation(for: "overlay") == .sourceOver)
    #expect(surfaceCompositingOperation(for: "overlay-fast") == .sourceAtop)
    #expect(surfaceCompositingOperation(for: "overlayfast") == .sourceAtop)
}

@Test
func `maps SERIKO blend and mask methods to native compositing`() {
    #expect(surfaceCompositingOperation(for: "blend-multiply") == .multiply)
    #expect(surfaceCompositingOperation(for: "blend-multiply-fast") == .multiply)
    #expect(surfaceCompositingOperation(for: "overlaymultiply") == .multiply)
    #expect(surfaceCompositingOperation(for: "blend-screen") == .screen)
    #expect(surfaceCompositingOperation(for: "blend-overlay") == .overlay)
    #expect(surfaceCompositingOperation(for: "blend-add-glow-fast") == .plusLighter)
    #expect(surfaceCompositingOperation(for: "blend-soft-light") == .softLight)
    #expect(surfaceCompositingOperation(for: "blend-color-dodge") == .colorDodge)
    #expect(surfaceCompositingOperation(for: "blend-color-burn") == .colorBurn)
    #expect(surfaceCompositingOperation(for: "blend-difference") == .difference)
    #expect(surfaceCompositingOperation(for: "blend-exclusion-fast") == .exclusion)
    #expect(surfaceCompositingOperation(for: "replace") == .copy)
    #expect(surfaceCompositingOperation(for: "interpolate") == .destinationOver)
    #expect(surfaceCompositingOperation(for: "reduce") == .destinationIn)
    #expect(surfaceCompositingOperation(for: "asis") == nil)
}

@Test
func `multiply fast clips the overlay to the base alpha`() throws {
    let base = try makeTestImage(colors: [
        NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 0),
        NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
    ])
    let overlay = try makeTestImage(colors: [
        NSColor(deviceRed: 0.5, green: 0.25, blue: 0.25, alpha: 1),
        NSColor(deviceRed: 0.5, green: 0.25, blue: 0.25, alpha: 1)
    ])

    let image = SurfaceImageLoader().composite(
        base: base,
        overlay: overlay,
        x: 0,
        y: 0,
        operation: .multiply,
        clipsToBaseAlpha: true
    )
    let data = try #require(image.tiffRepresentation)
    let output = try #require(NSBitmapImageRep(data: data))
    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
    #expect((output.colorAt(x: 1, y: 0)?.redComponent ?? 0) > 0.4)
    #expect((output.colorAt(x: 1, y: 0)?.redComponent ?? 1) < 0.6)
}

@Test
func `self alpha falls back to the top left key for a PNG without alpha`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "surface0.png")
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 1,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 6,
        bitsPerPixel: 24
    ))
    let bytes = try #require(bitmap.bitmapData)
    bytes[0] = 255
    bytes[1] = 255
    bytes[2] = 255
    bytes[3] = 0
    bytes[4] = 0
    bytes[5] = 0
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)

    let image = try SurfaceImageLoader().load(
        SurfaceAsset(id: 0, imageURL: url, alphaMaskURL: nil),
        usesSelfAlpha: true
    )
    let data = try #require(image.tiffRepresentation)
    let output = try #require(NSBitmapImageRep(data: data))
    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
    #expect((output.colorAt(x: 1, y: 0)?.alphaComponent ?? 0) > 0.9)
}

@Test
@MainActor
func `overlay fast clips the new layer to the base alpha`() throws {
    let base = try makeTestImage(colors: [
        NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1),
        NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
    ])
    let overlay = try makeTestImage(colors: [
        NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1),
        NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
    ])

    let image = SurfaceImageLoader().composite(
        base: base,
        overlay: overlay,
        x: 0,
        y: 0,
        operation: .sourceAtop
    )
    let data = try #require(image.tiffRepresentation)
    let output = try #require(NSBitmapImageRep(data: data))

    #expect((output.colorAt(x: 0, y: 0)?.greenComponent ?? 0) > 0.9)
    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) > 0.9)
    #expect((output.colorAt(x: 1, y: 0)?.alphaComponent ?? 1) < 0.1)
}

private func makeTestImage(colors: [NSColor]) throws -> NSImage {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: colors.count,
        pixelsHigh: 1,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: colors.count * 4,
        bitsPerPixel: 32
    ))
    for (x, color) in colors.enumerated() {
        bitmap.setColor(color, atX: x, y: 0)
    }
    bitmap.size = NSSize(width: colors.count, height: 1)
    let image = NSImage(size: bitmap.size)
    image.addRepresentation(bitmap)
    return image
}

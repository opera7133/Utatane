import AppKit
import Testing
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

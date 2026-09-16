import AppKit
import Foundation
import ImageIO
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
@MainActor
func `preserves APNG frames and timing when the animation uses alpha`() throws {
    let data = try #require(Data(base64Encoded: animatedPNGBase64))
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "surface0.apng")
    try data.write(to: url)

    let loader = SurfaceImageLoader()
    let image = try loader.load(SurfaceAsset(id: 0, imageURL: url, alphaMaskURL: nil))
    let representation = try #require(image.representations.first as? NSBitmapImageRep)
    let duration = try #require(representation.value(forProperty: .currentFrameDuration) as? Double)

    #expect(loader.frameCount(of: image) == 2)
    #expect(abs(duration - 0.2) < 0.001)
}

@Test
@MainActor
func `preserves APNG frames and timing after applying a PNA mask`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let imageURL = directory.appending(path: "surface0.apng")
    let maskURL = directory.appending(path: "surface0.pna")
    try #require(Data(base64Encoded: animatedPNGBase64)).write(to: imageURL)
    try makeMaskPNG(width: 4, height: 4, transparentAt: (x: 0, y: 0)).write(to: maskURL)

    let loader = SurfaceImageLoader()
    let image = try loader.load(SurfaceAsset(id: 0, imageURL: imageURL, alphaMaskURL: maskURL))
    let representation = try #require(image.representations.first as? NSBitmapImageRep)

    #expect(loader.frameCount(of: image) == 2)
    #expect(representation.pixelsWide == 4)
    #expect(representation.pixelsHigh == 4)
    representation.setProperty(.currentFrame, withValue: 0)
    #expect(abs((representation.value(forProperty: .currentFrameDuration) as? Double ?? 0) - 0.2) < 0.001)
    let firstFrame = try #require(representation.currentFrameBitmap)
    #expect((firstFrame.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
}

@Test
@MainActor
func `preserves APNG frames and timing while compositing a static element`() throws {
    let data = try #require(Data(base64Encoded: animatedPNGBase64))
    let animated = try #require(NSImage(data: data))
    let overlay = try makeTestImage(colors: [NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)])
    let loader = SurfaceImageLoader()

    let image = loader.composite(base: animated, overlay: overlay, x: 0, y: 0)
    let representation = try #require(image.representations.first as? NSBitmapImageRep)

    #expect(loader.frameCount(of: image) == 2)
    #expect(representation.pixelsWide == 4)
    #expect(representation.pixelsHigh == 4)
    representation.setProperty(.currentFrame, withValue: 0)
    #expect(abs((representation.value(forProperty: .currentFrameDuration) as? Double ?? 0) - 0.2) < 0.001)
    let firstFrame = try #require(representation.currentFrameBitmap)
    #expect(firstFrame.containsOpaqueRedPixel)
    #expect(firstFrame.containsOpaqueGreenPixel)
    representation.setProperty(.currentFrame, withValue: 1)
    let secondFrame = try #require(representation.currentFrameBitmap)
    #expect(secondFrame.containsOpaqueBluePixel)
    #expect(secondFrame.containsOpaqueGreenPixel)
}

@Test
@MainActor
func `merges APNG layers that use different frame timelines`() throws {
    let base = try makeAnimatedTestImage(durations: [0.1, 0.2])
    let overlay = try makeAnimatedTestImage(durations: [0.15, 0.15])

    let loader = SurfaceImageLoader()
    let image = loader.composite(base: base, overlay: overlay, x: 0, y: 0)
    let representation = try #require(image.representations.first as? NSBitmapImageRep)

    let frameCount = loader.frameCount(of: image)
    #expect(frameCount > 2)
    for index in 0 ..< frameCount {
        representation.setProperty(.currentFrame, withValue: index)
        #expect((representation.value(forProperty: .currentFrameDuration) as? Double ?? 0) > 0)
    }
}

@Test
@MainActor
func `asis loading ignores embedded alpha and PNA`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let imageURL = directory.appending(path: "surface0.png")
    let maskURL = directory.appending(path: "surface0.pna")
    let source = try makeTestImage(colors: [
        NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 0),
        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 0.5)
    ])
    let sourceRepresentation = try #require(source.representations.first as? NSBitmapImageRep)
    try #require(sourceRepresentation.representation(using: .png, properties: [:])).write(to: imageURL)
    try makeMaskPNG(width: 2, height: 1, transparentAt: (x: 0, y: 0)).write(to: maskURL)

    let image = try SurfaceImageLoader().load(
        SurfaceAsset(id: 0, imageURL: imageURL, alphaMaskURL: maskURL),
        ignoresTransparency: true
    )
    let output = try #require(image.representations.first as? NSBitmapImageRep)

    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) > 0.9)
    #expect((output.colorAt(x: 1, y: 0)?.alphaComponent ?? 0) > 0.9)
}

@Test
func `maps both SERIKO overlay fast spellings to source atop`() {
    #expect(surfaceCompositingOperation(for: "overlay") == .sourceOver)
    #expect(surfaceCompositingOperation(for: "overlay-fast") == .sourceAtop)
    #expect(surfaceCompositingOperation(for: "overlayfast") == .sourceAtop)
}

@Test
func `maps asis animation drawing to an overlay operation`() {
    #expect(surfaceCompositingOperation(for: "asis") == nil)
    #expect(animationCompositingOperation(for: "asis") == .sourceOver)
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
func `full self alpha keeps a PNG without alpha opaque`() throws {
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
        usesSelfAlpha: true,
        usesFullSelfAlpha: true
    )
    let data = try #require(image.tiffRepresentation)
    let output = try #require(NSBitmapImageRep(data: data))
    #expect((output.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) > 0.9)
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

private func makeAnimatedTestImage(durations: [TimeInterval]) throws -> NSImage {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data,
        "public.png" as CFString,
        durations.count,
        nil
    ))
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
    ] as CFDictionary)
    let colors: [NSColor] = [.red, .blue]
    for (index, duration) in durations.enumerated() {
        let frame = try makeTestImage(colors: [colors[index % colors.count]])
        let image = try #require(frame.cgImage(forProposedRect: nil, context: nil, hints: nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGDelayTime: duration,
                kCGImagePropertyAPNGUnclampedDelayTime: duration
            ]
        ] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    return try #require(NSImage(data: data as Data))
}

private func makeMaskPNG(
    width: Int,
    height: Int,
    transparentAt pixel: (x: Int, y: Int)
) throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 3,
        bitsPerPixel: 24
    ))
    for y in 0 ..< height {
        for x in 0 ..< width {
            let color = x == pixel.x && y == pixel.y
                ? NSColor(deviceWhite: 0, alpha: 1)
                : NSColor(deviceWhite: 1, alpha: 1)
            bitmap.setColor(color, atX: x, y: y)
        }
    }
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private extension NSBitmapImageRep {
    var currentFrameBitmap: NSBitmapImageRep? {
        cgImage.map(NSBitmapImageRep.init(cgImage:))
    }

    var containsOpaqueRedPixel: Bool {
        containsOpaquePixel {
            $0.redComponent > 0.8
                && $0.redComponent > $0.greenComponent * 3
                && $0.redComponent > $0.blueComponent * 3
        }
    }

    var containsOpaqueGreenPixel: Bool {
        containsOpaquePixel {
            $0.greenComponent > 0.8
                && $0.greenComponent > $0.redComponent * 3
                && $0.greenComponent > $0.blueComponent * 3
        }
    }

    var containsOpaqueBluePixel: Bool {
        containsOpaquePixel {
            $0.blueComponent > 0.8
                && $0.blueComponent > $0.redComponent * 3
                && $0.blueComponent > $0.greenComponent * 3
        }
    }

    private func containsOpaquePixel(matching predicate: (NSColor) -> Bool) -> Bool {
        for y in 0 ..< pixelsHigh {
            for x in 0 ..< pixelsWide {
                guard let color = colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.9, predicate(color) {
                    return true
                }
            }
        }
        return false
    }
}

let animatedPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAACXBIWXMAAAAAAAAAAQCEeRdzAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAAEAAAABAAAAAAAAAAAAAEABQAAXC5E3AAAACRJREFUeJxjfMPF8J8BCKLc7BlBNAsDGmCJcIfI8PzgYcCqAgDqiATS2a3PlwAAABpmY1RMAAAAAQAAAAQAAAAEAAAAAAAAAAAAAQAFAADHXa4IAAAAJGZkQVQAAAACeJxj1BVUZACBt7zfwTQLAxpggcm8fvTkP1YVAB/oB//52BKiAAAAAElFTkSuQmCC"

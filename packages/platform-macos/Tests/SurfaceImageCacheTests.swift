import AppKit
import Testing
@testable import UtatanePlatformMacOS

@MainActor
struct SurfaceImageCacheTests {
    @Test func `eviction keeps recently used images and separates opaque layers`() throws {
        let image = try #require(NSImage(data: makePNG(width: 1, height: 1)))
        let cost = try #require(SurfaceImageCache.estimatedDecodedBytes(of: image))
        let cache = SurfaceImageCache(byteLimit: cost * 2)
        cache[1] = image
        cache[1, true] = image
        #expect(cache[1] === image)
        cache[2] = image
        #expect(cache[1, true] == nil)
        #expect(cache[1] === image)
        #expect(cache[2] === image)
        #expect(cache.estimatedBytes == cost * 2)

        cache[1] = nil
        #expect(cache.estimatedBytes == cost)
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.estimatedBytes == 0)
        // Eviction never mutates an image still owned by the renderer.
        #expect(image.size == NSSize(width: 1, height: 1))
    }

    @Test func `oversized replacement is not retained and small entries are bounded`() throws {
        let small = try #require(NSImage(data: makePNG(width: 1, height: 1)))
        let big = try #require(NSImage(data: makePNG(width: 256, height: 1)))
        let cost = try #require(SurfaceImageCache.estimatedDecodedBytes(of: small))
        let cache = SurfaceImageCache(byteLimit: cost, countLimit: 1)
        cache[1] = small
        cache[1] = big
        #expect(cache[1] == nil)
        #expect(cache.estimatedBytes == 0)
        let countLimited = SurfaceImageCache(byteLimit: cost * 10, countLimit: 2)
        for id in 0 ..< 10 {
            countLimited[id] = small
        }
        #expect(countLimited.count == 2)
        #expect(countLimited[0] == nil)
        #expect(countLimited[9] === small)
    }

    @Test func `rendered surfaces do not replace source layers`() throws {
        let layer = try #require(NSImage(data: makePNG(width: 1, height: 1)))
        let rendered = try #require(NSImage(data: makePNG(width: 2, height: 1)))
        let cache = SurfaceImageCache()
        cache[0] = layer
        cache[0, renderedSurface: true] = rendered
        #expect(cache[0] === layer)
        #expect(cache[0, renderedSurface: true] === rendered)
    }

    @Test func `accounts for retina pixels and every animation frame`() throws {
        let data = try #require(Data(base64Encoded: animatedPNGBase64))
        let decoded = try #require(NSImage(data: data))
        let rep = try #require(decoded.representations.first as? NSBitmapImageRep)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.addRepresentation(rep)
        let frame = rep.value(forProperty: .currentFrame) as? Int
        let frames = try #require(rep.value(forProperty: .frameCount) as? Int)
        #expect(frames == 2)
        #expect(SurfaceImageCache.estimatedDecodedBytes(of: image) == max(rep.bytesPerRow, rep.pixelsWide * 4) * rep.pixelsHigh * frames)
        #expect(rep.value(forProperty: .currentFrame) as? Int == frame)
    }
}

import AppKit
import Testing
@testable import UtatanePlatformMacOS

@MainActor private func regionTestBitmap() throws -> NSBitmapImageRep {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 9, pixelsHigh: 3, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 40, bitsPerPixel: 32
    ))
    let pixels = try #require(bitmap.bitmapData)
    for y in 0 ..< 3 {
        for x in 0 ..< 9 {
            let offset = y * 40 + x * 4
            pixels[offset] = x < 4 ? 255 : 0
            pixels[offset + 1] = 0; pixels[offset + 2] = x < 4 ? 0 : 255
            pixels[offset + 3] = y == 0 ? 0 : 255
        }
    }
    return bitmap
}

@MainActor struct SurfaceRegionMaskCacheTests {
    @Test func `packed mask preserves exact RGB inversion row padding and image bounds`() throws {
        let bitmap = try regionTestBitmap()
        let mask = try #require(SurfaceRegionMask(bitmap: bitmap, red: 255, green: 0, blue: 0))
        #expect(mask.byteCount == 4)
        for y in -1 ... 3 {
            for x in -1 ... 9 {
                let inside = x >= 0 && y >= 0 && x < 9 && y < 3
                #expect(mask.contains(x: x, y: y, inverted: false) == (inside && x < 4))
                #expect(mask.contains(x: x, y: y, inverted: true) == (inside && x >= 4))
            }
        }
        #expect(mask.bounds(inverted: false) == .init(minX: 0, minY: 0, maxX: 3, maxY: 2))
        #expect(mask.bounds(inverted: true) == .init(minX: 4, minY: 0, maxX: 8, maxY: 2))
        let absent = try #require(SurfaceRegionMask(bitmap: bitmap, red: 999, green: 0, blue: 0))
        #expect(absent.bounds(inverted: false) == nil)
        #expect(absent.bounds(inverted: true) == .init(minX: 0, minY: 0, maxX: 8, maxY: 2))
    }

    @Test func `mask cache bounds bytes and entries promotes recent hits and keeps returned masks alive`() throws {
        let bitmap = try regionTestBitmap()
        var reads = 0
        let cache = SurfaceRegionMaskCache(byteLimit: 8, countLimit: 2) { _ in reads += 1; return bitmap }
        let a = URL(filePath: "/a"), b = URL(filePath: "/b"), c = URL(filePath: "/c")
        let retained = try #require(cache.mask(url: a, red: 255, green: 0, blue: 0))
        _ = cache.mask(url: b, red: 255, green: 0, blue: 0)
        _ = cache.mask(url: a, red: 255, green: 0, blue: 0)
        #expect(reads == 2)
        _ = cache.mask(url: c, red: 255, green: 0, blue: 0)
        #expect(cache.estimatedBytes == 8)
        #expect(cache.count == 2)
        _ = cache.mask(url: b, red: 255, green: 0, blue: 0)
        #expect(reads == 4)
        cache.removeAll()
        #expect(cache.estimatedBytes == 0)
        #expect(retained.contains(x: 0, y: 0, inverted: false))
    }

    @Test func `failed regions and distinct colors are bounded and suspension frees retained masks`() throws {
        let bitmap = try regionTestBitmap()
        var reads = 0
        let cache = SurfaceRegionMaskCache(byteLimit: 8, countLimit: 2) { url in
            reads += 1; return url.lastPathComponent == "missing" ? nil : bitmap
        }
        let url = URL(filePath: "/image")
        let red = try #require(cache.mask(url: url, red: 255, green: 0, blue: 0))
        let blue = try #require(cache.mask(url: url, red: 0, green: 0, blue: 255))
        #expect(red.contains(x: 0, y: 0, inverted: false))
        #expect(blue.contains(x: 8, y: 0, inverted: false))
        for index in 0 ..< 200 {
            _ = cache.mask(url: URL(filePath: "/\(index)/missing"), red: 0, green: 0, blue: 0)
        }
        let previous = reads
        #expect(cache.mask(url: URL(filePath: "/199/missing"), red: 0, green: 0, blue: 0) == nil)
        #expect(reads == previous)
        #expect(cache.count == 2)
        #expect(cache.estimatedBytes == 0)
        cache.setSuspended(true)
        #expect(cache.count == 0)
        #expect(cache.mask(url: url, red: 255, green: 0, blue: 0) != nil)
        #expect(cache.estimatedBytes == 0)
        cache.setSuspended(false)
        _ = cache.mask(url: url, red: 255, green: 0, blue: 0)
        #expect(cache.estimatedBytes == 4)
    }

    @Test func `temporary RGBA images are released and oversized masks remain usable without retention`() {
        weak var decoded: NSBitmapImageRep?
        let cache = SurfaceRegionMaskCache(byteLimit: 1) { _ in
            let bitmap = try? regionTestBitmap(); decoded = bitmap; return bitmap
        }
        let mask = cache.mask(url: URL(filePath: "/image"), red: 255, green: 0, blue: 0)
        #expect(mask?.contains(x: 0, y: 0, inverted: false) == true)
        #expect(decoded == nil)
        #expect(cache.count == 0)
        #expect(cache.estimatedBytes == 0)
    }
}

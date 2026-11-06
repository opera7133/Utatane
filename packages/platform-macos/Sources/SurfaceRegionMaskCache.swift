import AppKit

/// Exact RGB matches in the same top-row-first, premultiplied RGBA space used
/// by surface region collisions. Alpha remains deliberately irrelevant.
struct SurfaceRegionMask {
    struct Bounds: Equatable {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        mutating func include(x: Int, y: Int) {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
    }

    let width: Int
    let height: Int
    private let bits: [UInt8]
    private let matchingBounds: Bounds?
    private let otherBounds: Bounds?
    var byteCount: Int {
        bits.count
    }

    init?(bitmap: NSBitmapImageRep, red: Int, green: Int, blue: Int) {
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, pixels <= Int.max - 7,
              bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 4, bitmap.bitsPerPixel == 32, !bitmap.isPlanar,
              width <= Int.max / 4, bitmap.bytesPerRow >= width * 4,
              let data = bitmap.bitmapData else { return nil }
        self.width = width; self.height = height
        var bits = [UInt8](repeating: 0, count: (pixels + 7) / 8)
        var matches: Bounds?, others: Bounds?
        bits.withUnsafeMutableBufferPointer { bits in
            for y in 0 ..< height {
                let row = data.advanced(by: y * bitmap.bytesPerRow)
                for x in 0 ..< width {
                    let offset = x * 4
                    if Int(row[offset]) == red, Int(row[offset + 1]) == green, Int(row[offset + 2]) == blue {
                        let index = y * width + x
                        bits[index >> 3] |= UInt8(1 << (index & 7))
                        if matches == nil {
                            matches = Bounds(minX: x, minY: y, maxX: x, maxY: y)
                        } else {
                            matches?.include(x: x, y: y)
                        }
                    } else {
                        if others == nil {
                            others = Bounds(minX: x, minY: y, maxX: x, maxY: y)
                        } else {
                            others?.include(x: x, y: y)
                        }
                    }
                }
            }
        }
        self.bits = bits
        matchingBounds = matches; otherBounds = others
    }

    func contains(x: Int, y: Int, inverted: Bool) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        let index = y * width + x
        let matches = bits[index >> 3] & UInt8(1 << (index & 7)) != 0
        return inverted ? !matches : matches
    }

    func bounds(inverted: Bool) -> Bounds? {
        inverted ? otherBounds : matchingBounds
    }
}

/// Per interaction view. Masks and failed lookups share an entry limit, so
/// nonexistent filenames cannot grow an unbounded negative cache either.
@MainActor
final class SurfaceRegionMaskCache {
    private struct Key: Hashable {
        let url: URL
        let red: Int
        let green: Int
        let blue: Int
    }

    private struct Entry {
        let mask: SurfaceRegionMask?
        var lastAccess: UInt64
    }

    private let byteLimit: Int
    private let countLimit: Int
    private let decode: @MainActor (URL) -> NSBitmapImageRep?
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private var enabled = true
    private(set) var estimatedBytes = 0
    var count: Int {
        entries.count
    }

    init(byteLimit: Int = 4 * 1024 * 1024, countLimit: Int = 128,
         decode: @escaping @MainActor (URL) -> NSBitmapImageRep? = SurfaceRegionMaskCache.decodeBitmap)
    {
        self.byteLimit = max(0, byteLimit); self.countLimit = max(0, countLimit)
        self.decode = decode
    }

    func mask(url: URL, red: Int, green: Int, blue: Int) -> SurfaceRegionMask? {
        let key = Key(url: url, red: red, green: green, blue: blue)
        clock &+= 1
        if let entry = entries[key] {
            entries[key]?.lastAccess = clock
            return entry.mask
        }
        // Release the temporary decoded RGBA image before returning the bit mask.
        let mask = autoreleasepool {
            decode(url).flatMap { SurfaceRegionMask(bitmap: $0, red: red, green: green, blue: blue) }
        }
        let cost = mask?.byteCount ?? 0
        guard enabled, cost <= byteLimit, countLimit > 0 else { return mask }
        while estimatedBytes > byteLimit - cost || entries.count >= countLimit {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            if let removed = entries.removeValue(forKey: oldest) {
                estimatedBytes -= removed.mask?.byteCount ?? 0
            }
        }
        entries[key] = Entry(mask: mask, lastAccess: clock)
        estimatedBytes += cost
        return mask
    }

    func setSuspended(_ suspended: Bool) {
        enabled = !suspended
        if suspended {
            removeAll()
        }
    }

    func removeAll() {
        entries.removeAll(); estimatedBytes = 0; clock = 0
    }

    /// Keep conversion identical to the old collision bitmap path, including
    /// coordinate orientation, color space and premultiplication.
    static func decodeBitmap(url: URL) -> NSBitmapImageRep? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cgImage.width,
            pixelsHigh: cgImage.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: cgImage.width * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)).draw(
            in: NSRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: cgImage.width, height: cgImage.height)
        return bitmap
    }
}

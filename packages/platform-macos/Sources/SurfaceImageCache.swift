import AppKit

/// Discardable render results only. Images used by the current surface or an
/// active animation have their own references and survive cache eviction.
@MainActor
final class SurfaceImageCache {
    private struct Key: Hashable {
        let surfaceID: Int
        let opaque: Bool
        let renderedSurface: Bool
    }

    private struct Entry {
        let image: NSImage
        let cost: Int
        var lastAccess: UInt64
    }

    // Combined budget for rendered surfaces and normal/opaque layers, per character. Small
    // images also have an entry limit to bound dictionary/NSImage overhead.
    let byteLimit: Int
    private let countLimit: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var estimatedBytes = 0
    var count: Int {
        entries.count
    }

    init(byteLimit: Int = 16 * 1024 * 1024, countLimit: Int = 128) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(0, countLimit)
    }

    subscript(_ surfaceID: Int, _ opaque: Bool = false, renderedSurface renderedSurface: Bool = false) -> NSImage? {
        get {
            let key = Key(surfaceID: surfaceID, opaque: opaque, renderedSurface: renderedSurface)
            guard entries[key] != nil else { return nil }
            clock &+= 1
            entries[key]?.lastAccess = clock
            return entries[key]?.image
        }
        set {
            let key = Key(surfaceID: surfaceID, opaque: opaque, renderedSurface: renderedSurface)
            remove(key)
            guard let image = newValue, let cost = Self.estimatedDecodedBytes(of: image),
                  cost <= byteLimit, countLimit > 0
            else { return }
            while estimatedBytes > byteLimit - cost || entries.count >= countLimit {
                guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
                remove(oldest)
            }
            clock &+= 1
            entries[key] = Entry(image: image, cost: cost, lastAccess: clock)
            estimatedBytes += cost
        }
    }

    func removeAll() {
        entries.removeAll()
        estimatedBytes = 0
        clock = 0
    }

    private func remove(_ key: Key) {
        if let old = entries.removeValue(forKey: key) {
            estimatedBytes -= old.cost
        }
    }

    /// Estimate from pixels, row padding and all animation frames, not point
    /// size or compressed file size. Unknown/overflowing representations are
    /// rendered normally but not cached. Do not decode frames to measure them.
    static func estimatedDecodedBytes(of image: NSImage) -> Int? {
        guard !image.representations.isEmpty else { return nil }
        var total = 0
        for rep in image.representations {
            guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
            let (minimumRow, widthOverflow) = rep.pixelsWide.multipliedReportingOverflow(by: 4)
            guard !widthOverflow else { return nil }
            let rowBytes: Int
            let frames: Int
            if let bitmap = rep as? NSBitmapImageRep {
                let (planarRow, rowOverflow) = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.isPlanar ? bitmap.samplesPerPixel : 1)
                guard !rowOverflow else { return nil }
                rowBytes = max(minimumRow, planarRow)
                frames = max((bitmap.value(forProperty: .frameCount) as? NSNumber)?.intValue ?? 1, 1)
            } else {
                rowBytes = minimumRow
                frames = 1
            }
            let (frameBytes, heightOverflow) = rowBytes.multipliedReportingOverflow(by: rep.pixelsHigh)
            let (allFrames, framesOverflow) = frameBytes.multipliedReportingOverflow(by: frames)
            let (sum, sumOverflow) = total.addingReportingOverflow(allFrames)
            guard !heightOverflow, !framesOverflow, !sumOverflow else { return nil }
            total = sum
        }
        return total
    }
}

import AppKit

/// Share the immutable PNG bytes only while history entries reference them.
/// Surface IDs are not sufficient: dress-up and animation can change the image.
@MainActor
final class SpeechHistoryThumbnailPool {
    private var references: [Data: Int] = [:]

    var count: Int {
        references.count
    }

    func retain(_ data: Data?) -> Data? {
        guard let data else { return nil }
        if let index = references.index(forKey: data) {
            let canonical = references[index].key
            references[canonical] = references[index].value + 1
            return canonical
        }
        references[data] = 1
        return data
    }

    func release(_ data: Data?) {
        guard let data, let count = references[data] else { return }
        if count == 1 {
            references.removeValue(forKey: data)
        } else {
            references[data] = count - 1
        }
    }

    func removeAll() {
        references.removeAll()
    }
}

/// Owned by the history view, so closing it also releases decoded thumbnails.
/// NSCache may evict earlier under memory pressure; these are soft limits.
@MainActor
final class SpeechHistoryThumbnailCache {
    private let images = NSCache<NSData, NSImage>()

    init() {
        images.countLimit = 32
        images.totalCostLimit = 1024 * 1024
    }

    func image(for data: Data?) -> NSImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let image = images.object(forKey: key) {
            return image
        }
        guard let image = NSImage(data: data) else { return nil }
        if let cost = SurfaceImageCache.estimatedDecodedBytes(of: image),
           cost <= images.totalCostLimit
        {
            images.setObject(image, forKey: key, cost: cost)
        }
        return image
    }
}

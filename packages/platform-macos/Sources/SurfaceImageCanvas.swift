import AppKit

/// An image together with its top-left origin in surface coordinates.
struct SurfaceImageCanvas {
    let image: NSImage
    var origin: NSPoint = .zero

    var bounds: NSRect {
        NSRect(origin: origin, size: image.size)
    }

    func compositing(
        _ overlay: SurfaceImageCanvas,
        x: Int,
        y: Int,
        operation: NSCompositingOperation,
        clipsToBaseAlpha: Bool,
        expands: Bool,
        loader: SurfaceImageLoader
    ) throws -> SurfaceImageCanvas {
        guard expands else {
            return SurfaceImageCanvas(image: loader.composite(
                base: image, overlay: overlay.image, x: x, y: y,
                operation: operation, clipsToBaseAlpha: clipsToBaseAlpha
            ))
        }
        let overlayOrigin = NSPoint(x: CGFloat(x) + overlay.origin.x, y: CGFloat(y) + overlay.origin.y)
        let extent = bounds.union(NSRect(origin: overlayOrigin, size: overlay.image.size))
        // A distant element must not turn an export into an unbounded allocation.
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width <= 16384, extent.height <= 16384,
              extent.width * extent.height <= 16_777_216
        else {
            throw SurfaceImageError.compositionFailed(URL(filePath: "surface-export"))
        }
        let background = loader.composite(
            base: NSImage(size: extent.size), overlay: image,
            x: Int(origin.x - extent.minX), y: Int(origin.y - extent.minY)
        )
        return SurfaceImageCanvas(image: loader.composite(
            base: background, overlay: overlay.image,
            x: Int(overlayOrigin.x - extent.minX), y: Int(overlayOrigin.y - extent.minY),
            operation: operation, clipsToBaseAlpha: clipsToBaseAlpha
        ), origin: extent.origin)
    }

    func croppedFromZero(loader: SurfaceImageLoader) -> NSImage {
        guard origin != .zero else { return image }
        let size = NSSize(width: max(1, bounds.maxX), height: max(1, bounds.maxY))
        return loader.composite(base: NSImage(size: size), overlay: image,
                                x: Int(origin.x), y: Int(origin.y))
    }
}

import AppKit

enum WindowModeScreenshotKind: Sendable {
    case backgroundIncluded
    case transparentBackground
}

enum WindowModeScreenshotRenderer {
    @MainActor
    static func pngData(
        rootView: NSView,
        itemViews: [NSView],
        kind: WindowModeScreenshotKind
    ) -> Data? {
        let size = rootView.bounds.size
        let scale = max(rootView.window?.backingScaleFactor ?? 1, 1)
        let pixelWidth = max(1, Int(ceil(size.width * scale)))
        let pixelHeight = max(1, Int(ceil(size.height * scale)))
        guard !rootView.bounds.isEmpty,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.clear(rootView.bounds)
        if kind == .backgroundIncluded {
            if let stageRootView = rootView as? WindowModeStageRootView {
                stageRootView.drawStageBackground(in: context)
            } else if let backgroundColor = rootView.layer?.backgroundColor {
                context.setFillColor(backgroundColor)
                context.fill(rootView.bounds)
            }
        }

        let presentedViews = Set(itemViews.map(ObjectIdentifier.init))
        for itemView in presentedItemViews(in: rootView, identifiers: presentedViews) where !itemView.isHidden {
            let metalSnapshots = metalSnapshots(in: itemView)
            context.saveGState()
            if let layer = itemView.layer, layer.shadowOpacity > 0 {
                let color = layer.shadowColor ?? NSColor.black.cgColor
                context.setShadow(
                    offset: layer.shadowOffset,
                    blur: layer.shadowRadius,
                    color: color.copy(alpha: CGFloat(layer.shadowOpacity))
                )
            }
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawHierarchy(
                itemView,
                rootView: rootView,
                inheritedAlpha: 1,
                metalSnapshots: metalSnapshots,
                in: context
            )
            context.endTransparencyLayer()
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return nil }
        let output = NSBitmapImageRep(cgImage: image)
        output.size = size
        return output.representation(using: .png, properties: [:])
    }

    @MainActor
    private static func presentedItemViews(
        in view: NSView,
        identifiers: Set<ObjectIdentifier>
    ) -> [NSView] {
        view.subviews.flatMap { subview in
            if identifiers.contains(ObjectIdentifier(subview)) {
                [subview]
            } else {
                presentedItemViews(in: subview, identifiers: identifiers)
            }
        }
    }

    @MainActor
    private static func drawHierarchy(
        _ view: NSView,
        rootView: NSView,
        inheritedAlpha: CGFloat,
        metalSnapshots: [ObjectIdentifier: CGImage],
        in context: CGContext
    ) {
        guard !view.isHidden else { return }
        let alpha = inheritedAlpha * (view === rootView ? 1 : view.alphaValue)
        let destination = view === rootView
            ? view.frame
            : rootView.convert(view.bounds, from: view)
        context.saveGState()
        context.setAlpha(alpha)
        if let metalImage = metalSnapshots[ObjectIdentifier(view)] {
            context.interpolationQuality = .high
            context.draw(metalImage, in: destination)
        } else if metalSnapshots.isEmpty, let cachedImage = cachedImage(of: view) {
            context.interpolationQuality = .high
            context.draw(cachedImage, in: destination)
        } else if let imageView = view as? NSImageView,
                  let image = imageView.image.flatMap(cgImage)
        {
            context.interpolationQuality = imageView.imageScaling == .scaleNone ? .none : .high
            context.draw(image, in: destination)
        } else {
            drawView(view, in: destination, context: context)
        }
        context.restoreGState()
        guard !metalSnapshots.isEmpty else { return }
        for subview in view.subviews {
            drawHierarchy(
                subview,
                rootView: rootView,
                inheritedAlpha: alpha,
                metalSnapshots: metalSnapshots,
                in: context
            )
        }
    }

    @MainActor
    private static func metalSnapshots(in view: NSView) -> [ObjectIdentifier: CGImage] {
        var snapshots: [ObjectIdentifier: CGImage] = [:]
        func collect(_ candidate: NSView) {
            if let image = NijigenerateViewFactory.snapshotImage(candidate) {
                snapshots[ObjectIdentifier(candidate)] = image
            }
            candidate.subviews.forEach(collect)
        }
        collect(view)
        return snapshots
    }

    @MainActor
    private static func cachedImage(of view: NSView) -> CGImage? {
        guard !view.bounds.isEmpty,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation.cgImage
    }

    @MainActor
    private static func drawView(_ view: NSView, in destination: NSRect, context: CGContext) {
        guard !view.bounds.isEmpty else { return }
        context.saveGState()
        context.translateBy(x: destination.minX, y: destination.minY)
        context.scaleBy(
            x: destination.width / view.bounds.width,
            y: destination.height / view.bounds.height
        )
        context.translateBy(x: -view.bounds.minX, y: -view.bounds.minY)
        let previousContext = NSGraphicsContext.current
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: view.isFlipped)
        NSGraphicsContext.current = graphicsContext
        view.draw(view.bounds)
        graphicsContext.flushGraphics()
        NSGraphicsContext.current = previousContext
        context.restoreGState()
    }

    private static func cgImage(of image: NSImage) -> CGImage? {
        image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { lhs, rhs in
                lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
            }?
            .cgImage
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

@MainActor
enum WindowModeScreenshotFileName {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    static func make(date: Date = Date()) -> String {
        "utatane_\(formatter.string(from: date)).png"
    }
}

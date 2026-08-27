import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UtataneCore

struct SurfaceImageLoader {
    private let context = CIContext()

    func load(_ surface: SurfaceAsset, usesSelfAlpha: Bool = false) throws -> NSImage {
        guard let alphaMaskURL = surface.alphaMaskURL else {
            if usesSelfAlpha,
               let source = NSImage(contentsOf: surface.imageURL),
               let representation = source.representations
               .compactMap({ $0 as? NSBitmapImageRep })
               .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
               representation.hasAlpha
            {
                let pixelSize = NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
                representation.size = pixelSize
                let image = NSImage(size: pixelSize)
                image.addRepresentation(representation)
                return image
            }
            return try loadUsingTopLeftTransparency(surface.imageURL)
        }
        guard let source = NSImage(contentsOf: surface.imageURL),
              let mask = NSImage(contentsOf: alphaMaskURL)
        else {
            throw SurfaceImageError.invalidImage(alphaMaskURL)
        }
        return try applyingAlphaMask(source: source, mask: mask, sourceURL: surface.imageURL)
    }

    func composite(
        base: NSImage,
        overlay: NSImage,
        x: Int,
        y: Int,
        operation: NSCompositingOperation = .sourceOver,
        clipsToBaseAlpha: Bool = false
    ) -> NSImage {
        if operation == .multiply, clipsToBaseAlpha,
           let composited = compositeMultiplySourceAtop(base: base, overlay: overlay, x: x, y: y)
        {
            return composited
        }
        if operation == .sourceAtop,
           let composited = compositeSourceAtop(base: base, overlay: overlay, x: x, y: y)
        {
            return composited
        }

        let result = NSImage(size: base.size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        base.draw(in: NSRect(origin: .zero, size: base.size))
        overlay.draw(
            in: NSRect(
                x: CGFloat(x),
                y: base.size.height - CGFloat(y) - overlay.size.height,
                width: overlay.size.width,
                height: overlay.size.height
            ),
            from: .zero,
            operation: operation,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }

    private func compositeMultiplySourceAtop(
        base: NSImage,
        overlay: NSImage,
        x: Int,
        y: Int
    ) -> NSImage? {
        guard let baseImage = ciImage(from: base),
              let overlayImage = ciImage(from: overlay)
        else { return nil }

        let translatedOverlay = overlayImage.transformed(by: CGAffineTransform(
            translationX: CGFloat(x),
            y: baseImage.extent.height - CGFloat(y) - overlayImage.extent.height
        ))
        let multiply = CIFilter.multiplyBlendMode()
        multiply.inputImage = translatedOverlay
        multiply.backgroundImage = baseImage
        guard let multiplied = multiply.outputImage else { return nil }

        let clip = CIFilter.sourceAtopCompositing()
        clip.inputImage = multiplied
        clip.backgroundImage = baseImage
        guard let outputImage = clip.outputImage?.cropped(to: baseImage.extent),
              let output = context.createCGImage(outputImage, from: baseImage.extent)
        else { return nil }
        return NSImage(cgImage: output, size: base.size)
    }

    func translated(_ image: NSImage, x: Int, y: Int) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(
            in: NSRect(
                x: CGFloat(x),
                y: -CGFloat(y),
                width: image.size.width,
                height: image.size.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }

    private func compositeSourceAtop(
        base: NSImage,
        overlay: NSImage,
        x: Int,
        y: Int
    ) -> NSImage? {
        guard let baseImage = ciImage(from: base),
              let overlayImage = ciImage(from: overlay)
        else { return nil }

        let translatedOverlay = overlayImage.transformed(by: CGAffineTransform(
            translationX: CGFloat(x),
            y: baseImage.extent.height - CGFloat(y) - overlayImage.extent.height
        ))
        let filter = CIFilter.sourceAtopCompositing()
        filter.inputImage = translatedOverlay
        filter.backgroundImage = baseImage
        guard let outputImage = filter.outputImage?.cropped(to: baseImage.extent),
              let output = context.createCGImage(outputImage, from: baseImage.extent)
        else { return nil }
        return NSImage(cgImage: output, size: base.size)
    }

    private func ciImage(from image: NSImage) -> CIImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else { return nil }
        return CIImage(cgImage: cgImage)
    }

    func loadUsingTopLeftTransparency(_ url: URL) throws -> NSImage {
        if let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep.imageReps(with: data).compactMap({ $0 as? NSBitmapImageRep }).first
        {
            let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
            image.addRepresentation(rep)
            return try applyingTopLeftTransparency(to: image, sourceURL: url)
        }
        guard let source = NSImage(contentsOf: url) else {
            throw SurfaceImageError.invalidImage(url)
        }
        return try applyingTopLeftTransparency(to: source, sourceURL: url)
    }

    func applyingTopLeftTransparency(
        to source: NSImage,
        sourceURL: URL = URL(filePath: "surface.png")
    ) throws -> NSImage {
        guard let sourceRepresentation = source.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh })
            ?? source.cgImage(forProposedRect: nil, context: nil, hints: nil).map({ NSBitmapImageRep(cgImage: $0) })
        else {
            throw SurfaceImageError.invalidImage(sourceURL)
        }
        let pixelWidth = sourceRepresentation.pixelsWide
        let pixelHeight = sourceRepresentation.pixelsHigh
        let pixelSize = NSSize(width: pixelWidth, height: pixelHeight)

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ),
            let graphicsContext = NSGraphicsContext(bitmapImageRep: representation)
        else {
            throw SurfaceImageError.invalidImage(sourceURL)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        source.draw(in: NSRect(origin: .zero, size: pixelSize))
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let pixels = representation.bitmapData else {
            throw SurfaceImageError.invalidImage(sourceURL)
        }
        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        let bytesPerRow = representation.bytesPerRow
        // NSBitmapImageRep uses y == 0 for the image's top row. The previous
        // implementation sampled the bottom-left pixel, which left YAYA's
        // bright-green marker visible for one animation frame.
        let keyOffset = 0
        let key = (pixels[keyOffset], pixels[keyOffset + 1], pixels[keyOffset + 2])

        for row in 0 ..< height {
            for column in 0 ..< width {
                let offset = row * bytesPerRow + column * 4
                if pixels[offset] == key.0,
                   pixels[offset + 1] == key.1,
                   pixels[offset + 2] == key.2
                {
                    // Avoid chroma-key color bleeding back in when AppKit
                    // interpolates small animation overlays.
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                }
            }
        }

        representation.size = pixelSize
        let image = NSImage(size: pixelSize)
        image.addRepresentation(representation)
        return image
    }

    private func applyingAlphaMask(source: NSImage, mask: NSImage, sourceURL: URL) throws -> NSImage {
        guard let sourceRepresentation = source.representations
            .compactMap({ $0 as? NSBitmapImageRep }).first,
            let maskRepresentation = mask.representations
            .compactMap({ $0 as? NSBitmapImageRep }).first
        else {
            throw SurfaceImageError.invalidImage(sourceURL)
        }
        let width = sourceRepresentation.pixelsWide
        let height = sourceRepresentation.pixelsHigh
        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )
        else {
            throw SurfaceImageError.compositionFailed(sourceURL)
        }

        for y in 0 ..< height {
            for x in 0 ..< width {
                let sourceColor = sourceRepresentation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) ?? .clear
                // PNA masks may use a larger canvas than their PNG. Both are
                // aligned at the top-left; Core Image's bottom-left crop shifted
                // such masks vertically (Juda-System's fringe mask is 100 px taller).
                let maskColor = if x < maskRepresentation.pixelsWide, y < maskRepresentation.pixelsHigh {
                    maskRepresentation.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB) ?? .black
                } else {
                    NSColor.black
                }
                output.setColor(NSColor(
                    deviceRed: sourceColor.redComponent,
                    green: sourceColor.greenComponent,
                    blue: sourceColor.blueComponent,
                    alpha: sourceColor.alphaComponent * maskColor.redComponent
                ), atX: x, y: y)
            }
        }
        output.size = NSSize(width: width, height: height)
        let result = NSImage(size: output.size)
        result.addRepresentation(output)
        return result
    }
}

enum SurfaceImageError: LocalizedError {
    case invalidImage(URL)
    case compositionFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidImage(url):
            "画像を読み込めない: \(url.path)"
        case let .compositionFailed(url):
            "Surfaceを合成できない: \(url.path)"
        }
    }
}

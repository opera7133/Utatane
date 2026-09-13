import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UtataneCore

struct SurfaceImageLoader {
    private let context = CIContext()

    func load(
        _ surface: SurfaceAsset,
        usesSelfAlpha: Bool = false,
        ignoresTransparency: Bool = false
    ) throws -> NSImage {
        if ignoresTransparency {
            guard let source = NSImage(contentsOf: surface.imageURL) else {
                throw SurfaceImageError.invalidImage(surface.imageURL)
            }
            return try applyingOpaqueAlpha(to: source, sourceURL: surface.imageURL)
        }
        guard let alphaMaskURL = surface.alphaMaskURL else {
            if usesSelfAlpha,
               let source = NSImage(contentsOf: surface.imageURL),
               let representation = bestBitmapRepresentation(in: source),
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

    func applyingOpaqueAlpha(
        to source: NSImage,
        sourceURL: URL = URL(filePath: "surface.png")
    ) throws -> NSImage {
        if let animation = imageAnimation(from: source) {
            let frames = try animation.frames.map {
                try applyingOpaqueAlpha(to: $0, sourceURL: sourceURL)
            }
            if let result = makeAnimatedImage(
                frames: frames,
                durations: animation.durations,
                loopCount: animation.loopCount
            ) {
                return result
            }
        }
        guard let sourceRepresentation = bestBitmapRepresentation(in: source)
            ?? source.cgImage(forProposedRect: nil, context: nil, hints: nil).map({ NSBitmapImageRep(cgImage: $0) })
        else {
            throw SurfaceImageError.invalidImage(sourceURL)
        }
        let width = sourceRepresentation.pixelsWide
        let height = sourceRepresentation.pixelsHigh
        guard let output = makeBitmapRepresentation(width: width, height: height) else {
            throw SurfaceImageError.compositionFailed(sourceURL)
        }
        for y in 0 ..< height {
            for x in 0 ..< width {
                let color = sourceRepresentation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) ?? .black
                output.setColor(NSColor(
                    deviceRed: color.redComponent,
                    green: color.greenComponent,
                    blue: color.blueComponent,
                    alpha: 1
                ), atX: x, y: y)
            }
        }
        output.size = NSSize(width: width, height: height)
        let result = NSImage(size: output.size)
        result.addRepresentation(output)
        return result
    }

    func frameCount(of image: NSImage) -> Int {
        guard let representation = bestBitmapRepresentation(in: image) else { return 1 }
        return max(representation.value(forProperty: .frameCount) as? Int ?? 1, 1)
    }

    func importAnimation(at url: URL) throws -> (image: NSImage, durationMilliseconds: Int) {
        guard let source = NSImage(contentsOf: url) else {
            throw SurfaceImageError.invalidImage(url)
        }
        guard let animation = imageAnimation(from: source) else {
            return (source, 100)
        }
        let image = makeAnimatedImage(
            frames: animation.frames,
            durations: animation.durations,
            loopCount: 1
        ) ?? source
        let durationMilliseconds = max(Int((animation.durations.reduce(0, +) * 1000).rounded()), 1)
        return (image, durationMilliseconds)
    }

    func composite(
        base: NSImage,
        overlay: NSImage,
        x: Int,
        y: Int,
        operation: NSCompositingOperation = .sourceOver,
        clipsToBaseAlpha: Bool = false
    ) -> NSImage {
        if let animated = compositeAnimated(
            base: base,
            overlay: overlay,
            x: x,
            y: y,
            operation: operation,
            clipsToBaseAlpha: clipsToBaseAlpha
        ) {
            return animated
        }
        return compositeFrame(
            base: base,
            overlay: overlay,
            x: x,
            y: y,
            operation: operation,
            clipsToBaseAlpha: clipsToBaseAlpha
        )
    }

    private func compositeFrame(
        base: NSImage,
        overlay: NSImage,
        x: Int,
        y: Int,
        operation: NSCompositingOperation,
        clipsToBaseAlpha: Bool
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

        return rasterizedImage(size: base.size) {
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
        }
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
        if let animation = imageAnimation(from: image),
           let result = makeAnimatedImage(
               frames: animation.frames.map { translatedFrame($0, x: x, y: y) },
               durations: animation.durations,
               loopCount: animation.loopCount
           )
        {
            return result
        }
        return translatedFrame(image, x: x, y: y)
    }

    private func translatedFrame(_ image: NSImage, x: Int, y: Int) -> NSImage {
        rasterizedImage(size: image.size) {
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
        }
    }

    private func rasterizedImage(size: NSSize, drawing: () -> Void) -> NSImage {
        let width = max(Int(size.width.rounded(.up)), 1)
        let height = max(Int(size.height.rounded(.up)), 1)
        guard let representation = makeBitmapRepresentation(width: width, height: height),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: representation)
        else {
            return NSImage(size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .none
        drawing()
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        representation.size = size
        let result = NSImage(size: size)
        result.addRepresentation(representation)
        return result
    }

    private func makeBitmapRepresentation(width: Int, height: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
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
        if let animation = imageAnimation(from: source) {
            let frames = try animation.frames.map {
                try applyingTopLeftTransparency(to: $0, sourceURL: sourceURL)
            }
            if let result = makeAnimatedImage(
                frames: frames,
                durations: animation.durations,
                loopCount: animation.loopCount
            ) {
                return result
            }
        }
        guard let sourceRepresentation = bestBitmapRepresentation(in: source)
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
        let hasEmbeddedTransparency = (0 ..< height).contains { row in
            (0 ..< width).contains { column in
                pixels[row * bytesPerRow + column * 4 + 3] < 255
            }
        }
        if hasEmbeddedTransparency {
            representation.size = pixelSize
            let image = NSImage(size: pixelSize)
            image.addRepresentation(representation)
            return image
        }
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

    private func bestBitmapRepresentation(in image: NSImage) -> NSBitmapImageRep? {
        image.representations.compactMap { $0 as? NSBitmapImageRep }.max { lhs, rhs in
            let lhsFrames = lhs.value(forProperty: .frameCount) as? Int ?? 1
            let rhsFrames = rhs.value(forProperty: .frameCount) as? Int ?? 1
            if (lhsFrames > 1) != (rhsFrames > 1) {
                return lhsFrames <= 1
            }
            return lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }
    }

    private func applyingAlphaMask(source: NSImage, mask: NSImage, sourceURL: URL) throws -> NSImage {
        if let animation = imageAnimation(from: source) {
            let frames = try animation.frames.map {
                try applyingAlphaMask(source: $0, mask: mask, sourceURL: sourceURL)
            }
            if let result = makeAnimatedImage(
                frames: frames,
                durations: animation.durations,
                loopCount: animation.loopCount
            ) {
                return result
            }
        }
        guard let sourceRepresentation = bestBitmapRepresentation(in: source)
            ?? source.cgImage(forProposedRect: nil, context: nil, hints: nil).map({ NSBitmapImageRep(cgImage: $0) }),
            let maskRepresentation = bestBitmapRepresentation(in: mask)
            ?? mask.cgImage(forProposedRect: nil, context: nil, hints: nil).map({ NSBitmapImageRep(cgImage: $0) })
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

    private func compositeAnimated(
        base: NSImage,
        overlay: NSImage,
        x: Int,
        y: Int,
        operation: NSCompositingOperation,
        clipsToBaseAlpha: Bool
    ) -> NSImage? {
        let baseAnimation = imageAnimation(from: base)
        let overlayAnimation = imageAnimation(from: overlay)
        let frames: [NSImage]
        let durations: [TimeInterval]
        let loopCount: Int

        switch (baseAnimation, overlayAnimation) {
        case let (baseAnimation?, nil):
            frames = baseAnimation.frames.map {
                compositeFrame(
                    base: $0,
                    overlay: overlay,
                    x: x,
                    y: y,
                    operation: operation,
                    clipsToBaseAlpha: clipsToBaseAlpha
                )
            }
            durations = baseAnimation.durations
            loopCount = baseAnimation.loopCount
        case let (nil, overlayAnimation?):
            frames = overlayAnimation.frames.map {
                compositeFrame(
                    base: base,
                    overlay: $0,
                    x: x,
                    y: y,
                    operation: operation,
                    clipsToBaseAlpha: clipsToBaseAlpha
                )
            }
            durations = overlayAnimation.durations
            loopCount = overlayAnimation.loopCount
        case let (baseAnimation?, overlayAnimation?) where baseAnimation.hasSameTimeline(as: overlayAnimation):
            frames = zip(baseAnimation.frames, overlayAnimation.frames).map { baseFrame, overlayFrame in
                compositeFrame(
                    base: baseFrame,
                    overlay: overlayFrame,
                    x: x,
                    y: y,
                    operation: operation,
                    clipsToBaseAlpha: clipsToBaseAlpha
                )
            }
            durations = baseAnimation.durations
            loopCount = combinedLoopCount(baseAnimation.loopCount, overlayAnimation.loopCount)
        default:
            return nil
        }

        return makeAnimatedImage(frames: frames, durations: durations, loopCount: loopCount)
    }

    private func combinedLoopCount(_ lhs: Int, _ rhs: Int) -> Int {
        if lhs == 0 {
            return rhs
        }
        if rhs == 0 {
            return lhs
        }
        return min(lhs, rhs)
    }

    private func imageAnimation(from image: NSImage) -> SurfaceImageAnimation? {
        guard let representation = bestBitmapRepresentation(in: image),
              let frameCount = representation.value(forProperty: .frameCount) as? Int,
              frameCount > 1
        else { return nil }
        let currentFrame = representation.value(forProperty: .currentFrame) as? Int ?? 0
        defer { representation.setProperty(.currentFrame, withValue: currentFrame) }

        var frames: [NSImage] = []
        var durations: [TimeInterval] = []
        for index in 0 ..< frameCount {
            representation.setProperty(.currentFrame, withValue: index)
            guard let frame = representation.cgImage else { return nil }
            let size = NSSize(width: frame.width, height: frame.height)
            frames.append(NSImage(cgImage: frame, size: size))
            let duration = (representation.value(forProperty: .currentFrameDuration) as? NSNumber)?
                .doubleValue ?? 0.1
            durations.append(max(duration, 0.01))
        }
        let loopCount = (representation.value(forProperty: .loopCount) as? NSNumber)?.intValue ?? 0
        return SurfaceImageAnimation(frames: frames, durations: durations, loopCount: loopCount)
    }

    private func makeAnimatedImage(
        frames: [NSImage],
        durations: [TimeInterval],
        loopCount: Int
    ) -> NSImage? {
        guard frames.count > 1, frames.count == durations.count else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            frames.count,
            nil
        ) else { return nil }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGLoopCount: loopCount
            ]
        ] as CFDictionary)
        for (frame, duration) in zip(frames, durations) {
            guard let image = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: duration,
                    kCGImagePropertyAPNGUnclampedDelayTime: duration
                ]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination),
              let decoded = NSImage(data: data as Data),
              let representation = bestBitmapRepresentation(in: decoded)
        else { return nil }
        let size = frames[0].size
        representation.size = size
        let result = NSImage(size: size)
        result.addRepresentation(representation)
        return result
    }
}

private struct SurfaceImageAnimation {
    let frames: [NSImage]
    let durations: [TimeInterval]
    let loopCount: Int

    func hasSameTimeline(as other: SurfaceImageAnimation) -> Bool {
        guard frames.count == other.frames.count,
              durations.count == other.durations.count
        else { return false }
        return zip(durations, other.durations).allSatisfy { abs($0 - $1) < 0.001 }
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

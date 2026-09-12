import AppKit

@MainActor
struct WindowModeDesktopWallpaperSnapshot {
    let image: NSImage
    let url: URL
    let scaling: NSImageScaling
    let allowsClipping: Bool
    let fillColor: NSColor
    let signature: String

    var styleName: String {
        switch scaling {
        case .scaleAxesIndependently:
            "stretch"
        case .scaleNone:
            "center"
        case .scaleProportionallyDown, .scaleProportionallyUpOrDown:
            allowsClipping ? "fill" : "fit"
        @unknown default:
            "fit"
        }
    }
}

@MainActor
protocol WindowModeDesktopWallpaperProviding: AnyObject {
    func snapshot(for screen: NSScreen?) -> WindowModeDesktopWallpaperSnapshot?
}

@MainActor
final class SystemWindowModeDesktopWallpaperProvider: WindowModeDesktopWallpaperProviding {
    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private var cachedSnapshot: WindowModeDesktopWallpaperSnapshot?

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func snapshot(for screen: NSScreen?) -> WindowModeDesktopWallpaperSnapshot? {
        guard let screen = screen ?? NSScreen.main,
              let url = workspace.desktopImageURL(for: screen)
        else { return nil }

        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let scalingValue = (options[.imageScaling] as? NSNumber)?.uintValue
        let scaling = scalingValue.flatMap(NSImageScaling.init(rawValue:))
            ?? .scaleProportionallyUpOrDown
        let allowsClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? false
        let fillColor = options[.fillColor] as? NSColor ?? .black
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let rgb = fillColor.usingColorSpace(.deviceRGB) ?? .black
        let signatureComponents: [String] = [
            url.path,
            String(modified),
            String(fileSize),
            String(scaling.rawValue),
            String(allowsClipping),
            String(Double(rgb.redComponent)),
            String(Double(rgb.greenComponent)),
            String(Double(rgb.blueComponent))
        ]
        let signature = signatureComponents.joined(separator: "|")
        if cachedSnapshot?.signature == signature {
            return cachedSnapshot
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let snapshot = WindowModeDesktopWallpaperSnapshot(
            image: image,
            url: url,
            scaling: scaling,
            allowsClipping: allowsClipping,
            fillColor: fillColor,
            signature: signature
        )
        cachedSnapshot = snapshot
        return snapshot
    }
}

@MainActor
enum WindowModeDesktopWallpaperRenderer {
    static func draw(
        _ snapshot: WindowModeDesktopWallpaperSnapshot,
        in bounds: NSRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setFillColor(snapshot.fillColor.cgColor)
        context.fill(bounds)
        context.clip(to: bounds)

        let destination = destinationRect(
            imageSize: snapshot.image.size,
            bounds: bounds,
            scaling: snapshot.scaling,
            allowsClipping: snapshot.allowsClipping
        )
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        snapshot.image.draw(
            in: destination,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.current = previousContext
        context.restoreGState()
    }

    static func destinationRect(
        imageSize: NSSize,
        bounds: NSRect,
        scaling: NSImageScaling,
        allowsClipping: Bool
    ) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        switch scaling {
        case .scaleAxesIndependently:
            return bounds
        case .scaleNone:
            return centered(size: imageSize, in: bounds)
        case .scaleProportionallyDown, .scaleProportionallyUpOrDown:
            let widthScale = bounds.width / imageSize.width
            let heightScale = bounds.height / imageSize.height
            var scale = allowsClipping
                ? max(widthScale, heightScale)
                : min(widthScale, heightScale)
            if scaling == .scaleProportionallyDown {
                scale = min(scale, 1)
            }
            return centered(
                size: NSSize(width: imageSize.width * scale, height: imageSize.height * scale),
                in: bounds
            )
        @unknown default:
            return bounds
        }
    }

    private static func centered(size: NSSize, in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

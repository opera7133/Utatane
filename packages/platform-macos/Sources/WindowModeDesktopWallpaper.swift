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
        desktopWallpaperStyleName(scaling: scaling, allowsClipping: allowsClipping)
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

public struct DesktopWallpaperScreenState: Equatable, Sendable {
    public let path: String
    public let style: String
    public let backgroundColor: String
    fileprivate let signature: String

    public init(
        path: String,
        style: String,
        backgroundColor: String,
        signature: String? = nil
    ) {
        self.path = path
        self.style = style
        self.backgroundColor = backgroundColor
        self.signature = signature ?? [path, style, backgroundColor].joined(separator: "|")
    }
}

public struct DesktopWallpaperState: Equatable, Sendable {
    public let screens: [DesktopWallpaperScreenState]

    public init(screens: [DesktopWallpaperScreenState]) {
        self.screens = screens
    }

    public func initialEvent() -> DesktopWallpaperChangeEvent? {
        event(kind: "init", cause: .unknown, previous: nil)
    }

    fileprivate func updateEvent(
        previous: DesktopWallpaperState,
        cause: DesktopWallpaperChangeCause
    ) -> DesktopWallpaperChangeEvent? {
        event(kind: "update", cause: cause, previous: previous)
    }

    private func event(
        kind: String,
        cause: DesktopWallpaperChangeCause,
        previous: DesktopWallpaperState?
    ) -> DesktopWallpaperChangeEvent? {
        guard let primary = screens.first else { return nil }
        var references: [Int: String] = [
            0: kind,
            1: cause.rawValue,
            2: primary.path,
            3: previous?.screens.first?.path ?? "",
            4: primary.style,
            5: primary.backgroundColor
        ]
        for (index, screen) in screens.enumerated() {
            references[index + 6] = [String(index), screen.path, screen.style]
                .joined(separator: "\u{1}")
        }
        return DesktopWallpaperChangeEvent(
            references: references,
            delivery: kind == "init" || cause.requiresNotification ? .notification : .event
        )
    }
}

public enum DesktopWallpaperChangeCause: String, Equatable, Sendable {
    case user
    case slideshow
    case spotlight
    case theme
    case `self`
    case unknown

    fileprivate var requiresNotification: Bool {
        self == .slideshow || self == .spotlight
    }
}

public struct DesktopWallpaperChangeEvent: Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        case event
        case notification
    }

    public let references: [Int: String]
    public let delivery: Delivery

    public init(references: [Int: String], delivery: Delivery) {
        self.references = references
        self.delivery = delivery
    }
}

public struct DesktopWallpaperChangeDetector: Sendable {
    private var previous: DesktopWallpaperState?

    public init() {}

    public mutating func consume(
        _ current: DesktopWallpaperState,
        cause: DesktopWallpaperChangeCause = .unknown
    ) -> DesktopWallpaperChangeEvent? {
        defer { previous = current }
        guard let previous, previous != current else { return nil }
        return current.updateEvent(previous: previous, cause: cause)
    }
}

@MainActor
public final class SystemDesktopWallpaperSampler {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    public init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    public func sample() -> DesktopWallpaperState? {
        let screens = NSScreen.screens.map { screen -> DesktopWallpaperScreenState in
            let url = workspace.desktopImageURL(for: screen)
            let options = workspace.desktopImageOptions(for: screen) ?? [:]
            let scalingValue = (options[.imageScaling] as? NSNumber)?.uintValue
            let scaling = scalingValue.flatMap(NSImageScaling.init(rawValue:))
                ?? .scaleProportionallyUpOrDown
            let allowsClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? false
            let fillColor = options[.fillColor] as? NSColor ?? .black
            let rgb = fillColor.usingColorSpace(.deviceRGB) ?? .black
            let color = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                .map { String(Int(($0 * 255).rounded())) }
                .joined(separator: ",")
            let attributes = url.flatMap { try? fileManager.attributesOfItem(atPath: $0.path) }
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let style = desktopWallpaperStyleName(scaling: scaling, allowsClipping: allowsClipping)
            let path = url?.path ?? ""
            return DesktopWallpaperScreenState(
                path: path,
                style: style,
                backgroundColor: color,
                signature: [path, style, color, String(modified), String(fileSize)].joined(separator: "|")
            )
        }
        guard !screens.isEmpty else { return nil }
        return DesktopWallpaperState(screens: screens)
    }
}

private func desktopWallpaperStyleName(scaling: NSImageScaling, allowsClipping: Bool) -> String {
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

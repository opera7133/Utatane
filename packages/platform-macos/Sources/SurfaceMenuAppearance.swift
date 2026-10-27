import AppKit

public enum SurfaceMenuMode: String, Sendable, CaseIterable {
    case automatic
    case standard
}

/// Resolved assets for one ghost's menu. Resource paths are relative to ghost/master;
/// shell descript paths are relative to the selected shell.
@MainActor
public final class SurfaceMenuAppearance {
    public static let resourceKeys: [String] = {
        var keys = ["menu.font.name", "menu.font.height"]
        for part in ["background", "foreground", "sidebar"] {
            keys += ["menu.\(part).bitmap.filename", "menu.\(part).alignment"]
        }
        for part in ["background.font", "foreground.font", "disable.font", "separator", "frame"] {
            keys += ["r", "g", "b"].map { "menu.\(part).color.\($0)" }
        }
        return keys
    }()

    let background: NSImage?
    let foreground: NSImage?
    let sidebar: NSImage?
    let backgroundAlignment: String
    let foregroundAlignment: String
    let sidebarAlignment: String
    let textColor: NSColor
    let selectedTextColor: NSColor
    let disabledTextColor: NSColor
    let separatorColor: NSColor
    let frameColor: NSColor
    let font: NSFont
    var sidebarWidth: CGFloat {
        min(sidebar?.size.width ?? 0, 320)
    }

    var rowHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading) + 10
    }

    public init?(shellDirectory: URL, shellValues: [String: String], ghostDirectory: URL, overrides: [String: String] = [:]) {
        let values = shellValues.merging(overrides) { _, resource in resource }
        func image(_ part: String) -> NSImage? {
            let key = "menu.\(part).bitmap.filename"
            guard let path = values[key], !path.isEmpty else { return nil }
            let root = (overrides[key] == nil ? shellDirectory : ghostDirectory).standardizedFileURL.resolvingSymlinksInPath()
            let url = root.appending(path: path.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/"),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024,
                  let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0,
                  source.size.width <= 8192, source.size.height <= 8192 else { return nil }
            return source
        }
        func color(_ part: String, fallback: NSColor) -> NSColor {
            let components = ["r", "g", "b"].compactMap { values["menu.\(part).color.\($0)"].flatMap(Int.init) }
            guard components.count == 3 else { return fallback }
            return NSColor(deviceRed: CGFloat(max(0, min(255, components[0]))) / 255,
                           green: CGFloat(max(0, min(255, components[1]))) / 255,
                           blue: CGFloat(max(0, min(255, components[2]))) / 255, alpha: 1)
        }
        background = image("background")
        foreground = image("foreground")
        sidebar = image("sidebar")
        // An unreadable image alone must not replace a usable system menu.
        let hasColors = values.keys.contains { $0.hasPrefix("menu.") && $0.contains(".color.") }
        guard background != nil || foreground != nil || sidebar != nil || hasColors
            || values["menu.font.name"] != nil || values["menu.font.height"] != nil else { return nil }
        backgroundAlignment = values["menu.background.alignment"] ?? "lefttop"
        foregroundAlignment = values["menu.foreground.alignment"] ?? "lefttop"
        sidebarAlignment = values["menu.sidebar.alignment"] ?? "bottom"
        textColor = color("background.font", fallback: .labelColor)
        selectedTextColor = color("foreground.font", fallback: .selectedMenuItemTextColor)
        disabledTextColor = color("disable.font", fallback: .disabledControlTextColor)
        separatorColor = color("separator", fallback: textColor)
        frameColor = color("frame", fallback: .separatorColor)
        let height = CGFloat(max(8, min(36, abs(max(-36, min(36, Int(values["menu.font.height"] ?? "") ?? 13))))))
        font = values["menu.font.name"].flatMap { NSFont(name: $0, size: height) } ?? .menuFont(ofSize: height)
    }

    func drawBackground(in bounds: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        if let background {
            draw(background, in: bounds, alignment: backgroundAlignment)
        }
        if let sidebar {
            draw(sidebar, in: NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height), alignment: sidebarAlignment)
        }
    }

    func drawSelection(in row: NSRect, bounds: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: row.intersection(NSRect(x: sidebarWidth, y: 0, width: bounds.width - sidebarWidth, height: bounds.height))).addClip()
        if let foreground {
            draw(foreground, in: bounds, alignment: foregroundAlignment)
        } else {
            NSColor.selectedContentBackgroundColor.setFill(); row.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Stretch the outermost pixel beyond each edge, keeping the original image at 1:1.
    func draw(_ image: NSImage, in target: NSRect, alignment: String) {
        let alignment = alignment.lowercased()
        let w = image.size.width, h = image.size.height
        let x = alignment.contains("right") ? target.maxX - w : target.minX
        let y = alignment.contains("bottom") || alignment == "bottom" ? target.maxY - h : target.minY
        let rect = NSRect(x: x, y: y, width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: target).addClip()
        let xs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(target.minX, max(0, rect.minX - target.minX), 0, 1), (rect.minX, w, 0, w), (rect.maxX, max(0, target.maxX - rect.maxX), w - 1, 1)]
        // NSImage's source rectangle uses bottom-up coordinates.
        let ys: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(target.minY, max(0, rect.minY - target.minY), h - 1, 1), (rect.minY, h, 0, h), (rect.maxY, max(0, target.maxY - rect.maxY), 0, 1)]
        for (dx, dw, sx, sw) in xs where dw > 0 {
            for (dy, dh, sy, sh) in ys where dh > 0 {
                image.draw(in: NSRect(x: dx, y: dy, width: dw, height: dh), from: NSRect(x: sx, y: sy, width: sw, height: sh),
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

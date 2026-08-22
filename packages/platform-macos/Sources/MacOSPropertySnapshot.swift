import AppKit

@MainActor
public enum MacOSPropertySnapshot {
    public static func values() -> [String: String] {
        var values: [String: String] = [
            "system.monitor.count": String(NSScreen.screens.count),
            "system.cursor.pos": point(NSEvent.mouseLocation),
            "system.theme.os.mode": NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? "dark" : "light"
        ]

        for (index, screen) in NSScreen.screens.enumerated() {
            let prefix = "system.monitor.index(\(index))"
            values["\(prefix).rect"] = rect(screen.frame)
            values["\(prefix).work"] = rect(screen.visibleFrame)
            let bitsPerSample = (screen.deviceDescription[.bitsPerSample] as? NSNumber)?.intValue ?? 8
            values["\(prefix).bpp"] = String(bitsPerSample * 4)
            values["\(prefix).dpi"] = String(Int((72 * screen.backingScaleFactor).rounded()))
            values["\(prefix).primary"] = screen == NSScreen.screens.first ? "1" : "0"
        }
        return values
    }

    private static func point(_ point: NSPoint) -> String {
        "\(Int(point.x)),\(Int(point.y))"
    }

    private static func rect(_ rect: NSRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.maxX)),\(Int(rect.maxY))"
    }
}

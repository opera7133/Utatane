import AppKit

@MainActor
public enum MacOSPropertySnapshot {
    public static func values(
        geometryProvider: any PresentationGeometryProviding = SystemPresentationGeometryProvider()
    ) -> [String: String] {
        let screens = geometryProvider.screens
        var values: [String: String] = [
            "system.monitor.count": String(screens.count),
            "system.cursor.pos": point(geometryProvider.pointerPosition),
            "system.theme.os.mode": NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? "dark" : "light"
        ]

        for (index, screen) in screens.enumerated() {
            let prefix = "system.monitor.index(\(index))"
            values["\(prefix).rect"] = rect(screen.frame)
            values["\(prefix).work"] = rect(screen.visibleFrame)
            values["\(prefix).bpp"] = String(screen.bitsPerPixel)
            values["\(prefix).dpi"] = String(Int((72 * screen.scale).rounded()))
            values["\(prefix).primary"] = screen.isPrimary ? "1" : "0"
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

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
                ? "dark" : "light",
            "system.theme.app.mode": NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? "dark" : "light",
            "system.os.type": "MacOS",
            "system.os.arch": architectureName,
            "system.os.name": ProcessInfo.processInfo.operatingSystemVersionString,
            "system.os.version": operatingSystemVersion,
            "system.os.parenttype": "",
            "system.os.parentname": "",
            "system.os.locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
            "system.os.locale.language": Locale.current.language.languageCode?.identifier ?? "",
            "system.os.locale.country": Locale.current.region?.identifier ?? "",
            "system.os.timezone.offset": String(-TimeZone.current.secondsFromGMT() / 60),
            "system.os.dst": TimeZone.current.isDaylightSavingTime() ? "1" : "0",
            "system.os.uptime": String(Int(ProcessInfo.processInfo.systemUptime)),
            "system.os.unixtime": String(Int(Date().timeIntervalSince1970)),
            "system.os.idletime": String(Int(CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .null
            ))),
            "system.cpu.num": String(ProcessInfo.processInfo.processorCount),
            "system.memory.phyt": String(ProcessInfo.processInfo.physicalMemory / 1_048_576),
            "system.dnd.mode": "normal"
        ]

        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        values["system.disk.count"] = String(volumes.count)
        for (index, volume) in volumes.enumerated() {
            let prefix = "system.disk.index(\(index))"
            let resourceValues = try? volume.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            values["\(prefix).mountpoint"] = volume.path
            values["\(prefix).type"] = "fixed"
            values["\(prefix).total"] = resourceValues?.volumeTotalCapacity
                .map { String($0 / 1_048_576) } ?? "-1"
            values["\(prefix).free"] = resourceValues?.volumeAvailableCapacity
                .map { String($0 / 1_048_576) } ?? "-1"
        }

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

    private static var architectureName: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x64"
        #else
            "unknown"
        #endif
    }

    private static var operatingSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

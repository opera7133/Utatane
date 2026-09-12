import CoreGraphics
import Testing
@testable import UtatanePlatformMacOS

@MainActor
@Test
func `provides monitor cursor and theme properties`() {
    let values = MacOSPropertySnapshot.values()

    #expect(Int(values["system.monitor.count"] ?? "") != nil)
    #expect(values["system.cursor.pos"]?.contains(",") == true)
    #expect(["dark", "light"].contains(values["system.theme.os.mode"] ?? ""))
    if (Int(values["system.monitor.count"] ?? "0") ?? 0) > 0 {
        #expect(values["system.monitor.index(0).rect"]?.split(separator: ",").count == 4)
        #expect(values["system.monitor.index(0).primary"] == "1")
    }
}

@MainActor
@Test
func `uses injected virtual presentation geometry`() {
    let geometry = MutablePresentationGeometryProvider(
        screens: [
            PresentationScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 960, height: 540),
                visibleFrame: CGRect(x: 0, y: 0, width: 960, height: 520),
                bitsPerPixel: 32,
                scale: 2,
                isPrimary: true
            )
        ],
        pointerPosition: CGPoint(x: 120, y: 80)
    )

    let values = MacOSPropertySnapshot.values(geometryProvider: geometry)

    #expect(values["system.monitor.count"] == "1")
    #expect(values["system.monitor.index(0).rect"] == "0,0,960,540")
    #expect(values["system.monitor.index(0).work"] == "0,0,960,520")
    #expect(values["system.monitor.index(0).bpp"] == "32")
    #expect(values["system.monitor.index(0).dpi"] == "144")
    #expect(values["system.monitor.index(0).primary"] == "1")
    #expect(values["system.cursor.pos"] == "120,80")
}

import CoreGraphics
import Testing
@testable import UtatanePlatformMacOS

@Test
func `display handover reports initialization and screen changes`() {
    let primary = screen(x: 0, primary: true)
    let secondary = screen(x: 1920, primary: false)
    var tracker = DisplayHandoverTracker()

    let initial = tracker.initialize(
        scope: 1,
        windowFrame: CGRect(x: 100, y: 200, width: 300, height: 400),
        screens: [primary, secondary]
    )
    #expect(initial?.references == [
        0: "init",
        1: "1",
        2: "",
        3: "0,0,1920,1080,32,1"
    ])

    let unchanged = tracker.update(
        scope: 1,
        windowFrame: CGRect(x: 120, y: 200, width: 300, height: 400),
        screens: [primary, secondary]
    )
    #expect(unchanged == nil)

    let moved = tracker.update(
        scope: 1,
        windowFrame: CGRect(x: 2100, y: 200, width: 300, height: 400),
        screens: [primary, secondary]
    )
    #expect(moved?.references == [
        0: "update",
        1: "1",
        2: "0,0,1920,1080,32,1",
        3: "1920,0,3840,1080,32,0"
    ])
}

private func screen(x: CGFloat, primary: Bool) -> PresentationScreenGeometry {
    PresentationScreenGeometry(
        frame: CGRect(x: x, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: x, y: 0, width: 1920, height: 1040),
        bitsPerPixel: 32,
        scale: 2,
        isPrimary: primary
    )
}

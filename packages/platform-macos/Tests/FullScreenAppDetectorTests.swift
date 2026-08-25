import CoreGraphics
import Testing
@testable import UtatanePlatformMacOS

@Test
func `detects a window matching a screen size`() {
    let screens = [CGSize(width: 1920, height: 1080), CGSize(width: 1440, height: 900)]

    #expect(fullScreenWindowExists(
        windowBounds: [CGRect(x: 0, y: 0, width: 1920, height: 1080)],
        screenSizes: screens
    ))
    #expect(!fullScreenWindowExists(
        windowBounds: [CGRect(x: 0, y: 0, width: 1918, height: 1080)],
        screenSizes: screens
    ))
}

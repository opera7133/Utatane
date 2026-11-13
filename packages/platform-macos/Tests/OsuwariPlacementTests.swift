import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test func `osuwari aligns corners and falls back to work area`() {
    let screen = PresentationScreenGeometry(frame: CGRect(x: -800, y: 0, width: 800, height: 600),
                                            visibleFrame: CGRect(x: -800, y: 40, width: 800, height: 540),
                                            bitsPerPixel: 32, scale: 2, isPrimary: false)
    let options = OsuwariPlacement(options: ["--origin=tr", "--x=-10", "--y=20", "--area=workarea"])
    let size = CGSize(width: 100, height: 150)
    let window = CGRect(x: -600, y: 100, width: 400, height: 400)
    #expect(options.origin(size: size, target: window, screen: screen, screens: [screen]) == CGPoint(x: -310, y: 330))
    let offscreen = window.offsetBy(dx: 900, dy: 0)
    #expect(options.origin(size: size, target: offscreen, screen: screen, screens: [screen]) == CGPoint(x: -110, y: 410))
}

import AppKit
import Testing
import UtataneBalloon
@testable import UtatanePlatformMacOS

@Test func `balloon text frame scales with a negatively anchored wrap point`() {
    let balloon = BalloonDefinition(
        directory: URL(filePath: "/tmp/balloon"),
        name: "test",
        originX: 20,
        originY: 12,
        wordWrapPointX: -14,
        wordWrapPointY: -10,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    let normal = balloonTextFrame(
        for: balloon,
        displayedImageSize: NSSize(width: 300, height: 200),
        displayScale: 1
    )
    let enlarged = balloonTextFrame(
        for: balloon,
        displayedImageSize: NSSize(width: 600, height: 400),
        displayScale: 2
    )

    #expect(enlarged.origin.x == normal.origin.x * 2)
    #expect(enlarged.origin.y == normal.origin.y * 2)
    #expect(enlarged.size.width == normal.size.width * 2)
    #expect(enlarged.size.height == normal.size.height * 2)
}

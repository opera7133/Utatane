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

@Test func `vertical balloon text frame spans left from origin and wraps at y point`() {
    let balloon = BalloonDefinition(
        directory: URL(filePath: "/tmp/balloon"),
        name: "vertical",
        originX: 280,
        originY: 20,
        wordWrapPointX: 0,
        wordWrapPointY: 180,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        validRectLeft: 20,
        validRectTop: 20,
        validRectRight: 280,
        validRectBottom: 180,
        isVertical: true
    )

    let frame = balloonTextFrame(
        for: balloon,
        displayedImageSize: NSSize(width: 300, height: 200),
        displayScale: 1
    )

    #expect(frame == NSRect(x: 20, y: 20, width: 260, height: 160))
}

@Test func `vertical balloon resolves negative right and bottom coordinates from image edges`() {
    let balloon = BalloonDefinition(
        directory: URL(filePath: "/tmp/balloon"),
        name: "vertical",
        originX: -48,
        originY: 14,
        wordWrapPointX: -48,
        wordWrapPointY: -24,
        fontHeight: 18,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        validRectLeft: 28,
        validRectTop: 14,
        validRectRight: -48,
        validRectBottom: -24,
        isVertical: true
    )

    let frame = balloonTextFrame(
        for: balloon,
        displayedImageSize: NSSize(width: 506, height: 236),
        displayScale: 1
    )

    #expect(frame == NSRect(x: 28, y: 14, width: 430, height: 198))
}

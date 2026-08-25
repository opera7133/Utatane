import CoreGraphics
import Testing
@testable import UtatanePlatformMacOS

@Test
func `window layout snapshot formats local and global states`() {
    let screens = [CGRect(x: 0, y: 0, width: 100, height: 100)]
    let snapshot = WindowLayoutSnapshot(entries: [
        .init(
            ownerID: "a", characterName: "Emily", scope: 0,
            frame: CGRect(x: 10, y: 10, width: 30, height: 30), visibleScreenFrames: screens
        ),
        .init(
            ownerID: "a", characterName: "Teddy", scope: 1,
            frame: CGRect(x: 20, y: 20, width: 30, height: 30), visibleScreenFrames: screens
        ),
        .init(
            ownerID: "b", characterName: "Mari", scope: 0,
            frame: CGRect(x: 90, y: 90, width: 20, height: 20), visibleScreenFrames: screens
        )
    ])
    #expect(snapshot.overlapsByOwner["a"] == "0-1")
    #expect(snapshot.offscreenByOwner["a"] == "")
    #expect(snapshot.offscreenByOwner["b"] == "0")
    #expect(snapshot.allOverlaps == "Emily/0-Teddy/1")
    #expect(snapshot.allOffscreen == "Mari/0")
}

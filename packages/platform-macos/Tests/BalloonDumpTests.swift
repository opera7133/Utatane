import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Test @MainActor
func `balloon dump preserves visible view and exports hidden balloons at native size`() throws {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try makeTopLeftKeyedPNG(width: 120, height: 80).write(to: root.appending(path: "balloons0.png"))
    let controller = BalloonWindowController(positionStore: positions)
    defer { controller.resetContent() }
    controller.setDisplayScale(2, textScale: 1)
    try controller.show(balloon: makeBalloon(directory: root), text: "HELLO", near: .zero)
    controller.setMarkerText("MARKER", scope: 0)
    controller.setNumber(file: "", current: "1", maximum: "2", scope: 0)
    let output = root.appending(path: "dump")
    #expect(try controller.dumpBalloonImage(to: output, scope: 0) == 1)
    let ordinary = try Data(contentsOf: output.appending(path: "balloon0.png"))
    let image = try #require(NSBitmapImageRep(data: ordinary))
    #expect(image.pixelsWide == 120)
    #expect(image.pixelsHigh == 80)
    #expect(bitmapContainsRedPixel(image))
    #expect(try controller.dumpBalloonImage(to: output, scope: 0, prefix: "hidden", hiddenItems: ["balloonmarker", "balloonnum"]) == 1)
    let hidden = try Data(contentsOf: output.appending(path: "hidden0.png"))
    #expect(hidden != ordinary)
    #expect(controller.displayedText(for: 0) == "HELLO")
    #expect(controller.markerText(scope: 0) == "MARKER")
    controller.hide(scope: 0)
    #expect(try controller.dumpBalloonImage(to: output, scope: 0, prefix: "again") == 1)
    #expect(try controller.dumpBalloonImage(to: output, scope: 5) == 0)
    #expect(throws: (any Error).self) { try controller.dumpBalloonImage(to: output, scope: 0, prefix: "../escape") }
    controller.setRepaintLocked(true, scope: 0)
    controller.updateContent(text: "NEW", links: [], styles: [], scope: 0)
    #expect(controller.displayedText(for: 0) == "HELLO")
    #expect(try controller.dumpBalloonImage(to: output, scope: 0, prefix: "redrawn", hiddenItems: ["balloonmarker"]) == 1)
    #expect(controller.displayedText(for: 0) == "HELLO")
}

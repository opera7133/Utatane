import Foundation
import Testing
@testable import UtataneNativeSaori

@Test func `wmove exposes positions desktop size and horizontal movement`() {
    let windows = RecordingWindowController()
    let registry = NativeSaoriRegistry(baseDirectoryURL: URL(filePath: "/ghost/master"), windowController: windows)
    registry.load("modules\\wmove.dll")
    #expect(registry.call("wmove.dll", arguments: ["GET_POSITION", "1"]) == "100\u{1}125\u{1}150")
    #expect(registry.call("wmove.dll", arguments: ["GET_DESKTOP_SIZE"]) == "1440\u{1}900")
    #expect(registry.call("wmove.dll", arguments: ["MOVETO", "1", "20", "5"]) == "")
    #expect(windows.moves == [.init(scope: 1, x: 20, speed: 5)])
}

private final class RecordingWindowController: NativeSaoriWindowControlling, @unchecked Sendable {
    struct Move: Equatable { var scope: Int; var x: Int; var speed: Int }
    var moves: [Move] = []
    func frame(scope: Int) -> NativeSaoriWindowFrame? {
        scope == 1 ? .init(x: 100, y: 200, width: 50, height: 80) : nil
    }

    func desktopSize() -> (width: Int, height: Int) {
        (1440, 900)
    }

    func move(scope: Int, x: Int, speed: Int) {
        moves.append(.init(scope: scope, x: x, speed: speed))
    }
}

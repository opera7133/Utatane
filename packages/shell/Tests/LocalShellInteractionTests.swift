import Foundation
import Testing
@testable import UtataneShell

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_SHELL"] != nil))
func `local CLDSP shell preserves EQ control collisions and spectrum animations`() throws {
    let root = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_CLDSP_SHELL"]))
    let shell = try ShellLoader().load(from: root)
    let surface = try #require(shell.surfaces[9])
    print("CLDSP9", surface.collisions.map { "\($0.id):\($0.name)" })
    #expect(surface.collisions.contains { $0.name == "mode_eq_on" })
    #expect(surface.collisions.contains { $0.name == "mode_eq_bank0" })
    #expect(surface.animations.contains { $0.id == 212 })
}

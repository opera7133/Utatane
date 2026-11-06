import Foundation
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

@Test @MainActor func `cancelled timer response cannot interrupt a newer playback after awaiting SHIORI`() async throws {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaces = SurfaceWindowController(positionStore: positions)
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    defer { player.configure(environmentVariables: [:]); player.cancel(); surfaces.resetContent(); balloons.resetContent() }
    let balloon = makeBalloon(directory: FileManager.default.temporaryDirectory)
    var pending: CheckedContinuation<SakuraScript?, Never>?
    player.onEmbeddedEvent = { _, _ in
        await withCheckedContinuation { pending = $0 }
    }
    var notices: [String] = []
    player.onEmbeddedNotification = { id, _ in notices.append(id) }
    await player.playAndWait(SakuraScript(rawValue: #"\![timerraise,20,1,OnTimer]\e"#), balloon: balloon)
    try await requireEventually { pending != nil }
    let playback = Task {
        await player.playAndWait(SakuraScript(rawValue: #"\![notify,Ready]\_w[100]\![notify,Complete]\e"#), balloon: balloon)
    }
    try await requireEventually { notices == ["Ready"] }
    // Reconfiguration cancels event timers while the old SHIORI callback is held.
    player.configure(environmentVariables: [:])
    pending?.resume(returning: SakuraScript(rawValue: #"\![notify,Stale]\e"#))
    await playback.value
    #expect(notices == ["Ready", "Complete"])
}

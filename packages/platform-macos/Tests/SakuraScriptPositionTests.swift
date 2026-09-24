import AppKit
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

@MainActor
private func withPositionPlayer(_ body: (SakuraScriptPlayer, BalloonWindowController, BalloonDefinition) async throws -> Void) async throws {
    let (defaults, positions) = makePositionStore()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        try? FileManager.default.removeItem(at: directory)
    }
    let image = try makePNG(width: 120, height: 80)
    for name in ["balloons0.png", "balloonk0.png", "balloonp2def0.png"] {
        try image.write(to: directory.appending(path: name))
    }
    let surfaces = SurfaceWindowController(positionStore: positions)
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    defer { player.cancel() }
    try await body(player, balloons, makeBalloon(directory: directory))
}

@Test @MainActor
func `balloon break reports translated source position within text`() async throws {
    try await withPositionPlayer { player, _, balloon in
        let prefix = #"\_q\0あ\\い\_q\1う"#
        let source = prefix + "えお"
        player.onTranslate = { _, _ in SakuraScript(rawValue: source) }
        var interrupted: SakuraScriptPlaybackPosition?
        player.onBalloonBreak = { interrupted = .init(script: $0, scope: $1, characterOffset: $2) }
        player.play(SakuraScript(rawValue: "before translation"), balloon: balloon, characterDelayMilliseconds: 30000)
        try await requireEventually { player.playbackPosition?.characterOffset == prefix.count }
        #expect(player.playbackPosition?.scope == 1)
        player.onTranslate = nil
        player.play(SakuraScript(rawValue: #"\x"#), balloon: balloon)
        #expect(interrupted == .init(script: source, scope: 1, characterOffset: prefix.count))
    }
}

@Test @MainActor
func `source tracking follows embedded replies and restores the parent source`() async throws {
    try await withPositionPlayer { player, _, balloon in
        let reply = #"\p[2]返答\x"#
        let prefix = #"\0前\![embed,OnReply]\0後\x"#
        let parent = prefix + #"続き\x"#
        player.onEmbeddedEvent = { _, _ in SakuraScript(rawValue: reply) }
        player.play(SakuraScript(rawValue: parent), balloon: balloon, characterDelayMilliseconds: 0)
        try await requireEventually { player.playbackPosition == .init(script: reply, scope: 2, characterOffset: reply.count) }
        player.advance()
        try await requireEventually { player.playbackPosition == .init(script: parent, scope: 0, characterOffset: prefix.count) }
        let interrupt = #"\1割込\x"#
        player.interrupt(with: SakuraScript(rawValue: interrupt), balloon: balloon)
        player.advance()
        try await requireEventually { player.playbackPosition == .init(script: interrupt, scope: 1, characterOffset: interrupt.count) }
        player.advance()
        try await requireEventually { player.playbackPosition == .init(script: parent, scope: 0, characterOffset: parent.count) }
    }
}

@Test @MainActor
func `SSTP break uses the playing script and queue cancels on replacement`() async throws {
    try await withPositionPlayer { player, _, balloon in
        let first = #"\1一つ目\x"#
        let second = #"\0二つ目\x"#
        let third = #"\p[2]三つ目\x"#
        player.play(SakuraScript(rawValue: first), balloon: balloon, characterDelayMilliseconds: 0, sstpMessage: "")
        player.enqueue(SakuraScript(rawValue: second), balloon: balloon, characterDelayMilliseconds: 0, sstpMessage: "sender")
        player.enqueue(SakuraScript(rawValue: third), balloon: balloon, characterDelayMilliseconds: 0, sstpMessage: "sender")
        try await requireEventually { player.playbackPosition?.characterOffset == first.count }
        #expect(player.sstpBreakEvent == .shiori(id: "OnSSTPBreak", references: [0: first, 1: "1", 2: String(first.count)]))
        player.advance()
        try await requireEventually { player.playbackPosition == .init(script: second, scope: 0, characterOffset: second.count) }
        #expect(player.sstpBreakEvent == .shiori(id: "OnSSTPBreak", references: [0: second, 1: "0", 2: String(second.count)]))
        player.enqueue(SakuraScript(rawValue: "四つ目"), balloon: balloon, characterDelayMilliseconds: 0, sstpMessage: "sender")
        var finished = false
        player.onPlaybackFinished = { finished = true }
        player.play(SakuraScript(rawValue: "通常会話"), balloon: balloon, characterDelayMilliseconds: 0)
        try await requireEventually { finished }
        #expect(player.sstpBreakEvent == nil)
        #expect(player.playbackPosition?.script == "通常会話")
        #expect(player.playbackPosition?.characterOffset == 4)
    }
}

@Test @MainActor
func `filtered commands and property expansion keep source offsets`() async throws {
    try await withPositionPlayer { player, _, balloon in
        let source = #"\![raise,Blocked]\1日本語\\\%\x"#
        player.onEmbeddedEvent = { _, _ in Issue.record("Filtered event executed"); return nil }
        player.play(SakuraScript(rawValue: source), balloon: balloon, characterDelayMilliseconds: 0, policy: .externalMessage)
        try await requireEventually { player.playbackPosition?.characterOffset == source.count }
        #expect(player.playbackPosition?.scope == 1)
        let propertySource = #"%property[test]\x"#
        player.onPropertyValue = { _ in "展開文字列" }
        player.play(SakuraScript(rawValue: propertySource), balloon: balloon, characterDelayMilliseconds: 0)
        try await requireEventually { player.playbackPosition?.characterOffset == propertySource.count }
        #expect(player.playbackPosition?.script == propertySource)
    }
}

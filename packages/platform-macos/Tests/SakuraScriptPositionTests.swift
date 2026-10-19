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
func `property only clock updates leave the player talkable every second`() async throws {
    try await withPositionPlayer { player, balloons, balloon in
        var seconds: [String] = []
        player.onGetProperties = { event, properties in
            #expect(event == "OnClock")
            #expect(properties == ["system.second"])
            seconds.append(String(seconds.count))
            return SakuraScript(rawValue: #"\e"#)
        }
        for _ in 0 ..< 3 {
            #expect(player.canTalk)
            await player.playAndWait(SakuraScript(rawValue: #"\t\0\![get,property,OnClock,system.second]\e"#), balloon: balloon)
            #expect(balloons.visibleScopes.isEmpty)
            #expect(player.canTalk)
            #expect(!player.isDialogueActive)
        }
        #expect(seconds == ["0", "1", "2"])
    }
}

@Test @MainActor
func `periodic clock updates queue the latest tick behind display work without interrupting it`() async throws {
    try await withPositionPlayer { player, _, balloon in
        var pending: CheckedContinuation<SakuraScript?, Never>?
        var events: [String] = []
        player.onGetProperties = { _, _ in
            await withCheckedContinuation { pending = $0 }
        }
        player.onEmbeddedNotification = { id, _ in events.append(id) }
        player.play(SakuraScript(rawValue: #"\![get,property,OnClock,system.second]\![notify,OnOriginalFinished]\e"#), balloon: balloon)
        try await requireEventually { pending != nil }
        #expect(player.canTalk)
        player.enqueuePeriodic(SakuraScript(rawValue: #"\![notify,OnStaleTick]\e"#), balloon: balloon, eventID: "OnSecondChange")
        player.enqueuePeriodic(SakuraScript(rawValue: #"\![notify,OnLatestTick]\e"#), balloon: balloon, eventID: "OnSecondChange")
        #expect(events.isEmpty)
        pending?.resume(returning: nil)
        try await requireEventually { events.contains("OnLatestTick") }
        #expect(events == ["OnOriginalFinished", "OnLatestTick"])
        var completed = false
        player.onPlaybackFinished = { completed = true }
        let dialogue = #"台詞\x"#
        player.play(SakuraScript(rawValue: dialogue), balloon: balloon, characterDelayMilliseconds: 0)
        try await requireEventually { player.playbackPosition?.characterOffset == dialogue.count }
        #expect(!player.canTalk)
        player.enqueuePeriodic(SakuraScript(rawValue: #"\![notify,MustNotRun]"#), balloon: balloon, eventID: "OnSecondChange")
        player.advance()
        try await requireEventually { completed }
        #expect(!events.contains("MustNotRun"))
    }
}

@Test @MainActor
func `terminal only translation keeps the original talk`() async throws {
    try await withPositionPlayer { player, _, balloon in
        let original = SakuraScript(rawValue: #"\0会話\e"#)
        player.onTranslate = { _, _ in SakuraScript(rawValue: #"\e"#) }
        var played: SakuraScript?
        player.onTalkPlayback = { phase, script, _ in
            if phase == .before {
                played = script
            }
        }
        await player.playAndWait(original, balloon: balloon, characterDelayMilliseconds: 0)
        #expect(played == original)
    }
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

@Test @MainActor
func `textarea playback keeps scope and routes close independently of ordinary input`() async throws {
    try await withPositionPlayer { player, _, balloon in
        var areaScopes: [Int] = []
        var ordinaryIDs: [String] = []
        var closedAreas: [String] = []
        var closedInputs: [String] = []
        player.onTextAreaBox = { command, scope in
            areaScopes.append(scope)
            #expect(command.placeholder == "memo")
            return SakuraScript(rawValue: #"\![close,textareabox,reply]"#)
        }
        player.onInputBox = { command in ordinaryIDs.append(command.id); return nil }
        player.onCloseTextAreaBox = { closedAreas.append($0) }
        player.onCloseInputBox = { closedInputs.append($0) }
        await player.playAndWait(SakuraScript(rawValue: #"\p[2]\![open,textareabox,area,--placeholder=memo]\![close,inputbox,__SYSTEM_ALL_INPUT__]\![close,textareabox,area]\![open,inputbox,name]"#), balloon: balloon, characterDelayMilliseconds: 0)
        #expect(areaScopes == [2])
        #expect(ordinaryIDs == ["name"])
        #expect(closedAreas == ["reply", "area"])
        #expect(closedInputs == ["__SYSTEM_ALL_INPUT__"])
    }
}

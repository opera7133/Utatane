import Foundation
import Testing
import UtataneCore
@testable import UtataneRuntime
import UtataneSakuraScript

@Test
func `catalog maps events and substitutes choice arguments`() async throws {
    let catalog = DialogueCatalog(
        boot: ["boot"],
        close: ["close"],
        ghostChanging: ["changing to {{ghostName}}"],
        randomTalk: ["random"],
        mouseClick: ["Head": ["head"], "*": ["other"]],
        choices: ["OnChoice": ["selected {{argument0}}"]]
    )
    let engine = DialoguePersonalityEngine(catalog: catalog)

    #expect(try await engine.handle(event: .boot)?.rawValue == "boot")
    #expect(try await engine.handle(event: .close)?.rawValue == "close")
    #expect(
        try await engine.handle(event: .ghostChanging(name: "Emily"))?.rawValue
            == "changing to Emily"
    )
    #expect(try await engine.handle(event: .mouseClick(scope: 0, region: "Head"))?.rawValue == "head")
    #expect(try await engine.handle(event: .mouseClick(scope: 0, region: nil))?.rawValue == "other")
    #expect(
        try await engine.handle(event: .choice(id: "OnChoice", arguments: ["B"]))?.rawValue
            == "selected B"
    )
}

@Test
func `session can start with a ghost call event`() async throws {
    let engine = RecordingPersonalityEngine()
    let session = GhostSession(personalityEngine: engine)

    _ = try await session.start(event: .shiori(id: "OnGhostCalled", references: [0: "caller"]))

    #expect(await engine.lastEvent == .shiori(id: "OnGhostCalled", references: [0: "caller"]))
}

private actor RecordingPersonalityEngine: PersonalityEngine {
    private(set) var lastEvent: GhostEvent?

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        lastEvent = event
        return nil
    }
}

@Test
func `session accepts events only while running`() async throws {
    let engine = DialoguePersonalityEngine(
        catalog: DialogueCatalog(boot: ["boot"], close: ["close"], randomTalk: ["talk"])
    )
    let session = GhostSession(personalityEngine: engine)

    #expect(try await session.handle(event: .randomTalk) == nil)
    #expect(try await session.start()?.rawValue == "boot")
    #expect(try await session.handle(event: .randomTalk)?.rawValue == "talk")
    #expect(try await session.stop(reason: .ghostChanging(name: "Emily"))?.rawValue == "close")
    #expect(try await session.handle(event: .randomTalk) == nil)
    #expect(await session.state == .stopped)
}

@Test
func `session sends detailed ghost changing references`() async throws {
    let engine = RecordingPersonalityEngine()
    let session = GhostSession(personalityEngine: engine)
    _ = try await session.start()
    _ = try await session.stop(reason: .ghostChangingDetailed(
        name: "Emily", mode: "manual", ghostName: "Emily/Phase4.5", path: "/ghost/emily"
    ))

    #expect(await engine.lastEvent == .shiori(id: "OnGhostChanging", references: [
        0: "Emily", 1: "manual", 2: "Emily/Phase4.5", 3: "/ghost/emily"
    ]))
}

@Test
func `decodes an older dialogue catalog without ghost changing scripts`() throws {
    let data = Data(#"{"boot":["boot"],"close":["close"]}"#.utf8)
    let catalog = try JSONDecoder().decode(DialogueCatalog.self, from: data)

    #expect(catalog.ghostChanging.isEmpty)
    #expect(catalog.scripts(for: .ghostChanging(name: nil)) == ["close"])
}

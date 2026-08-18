import Foundation
import Testing
import UtataneCore
@testable import UtataneRuntime

@Test
func `catalog maps events and substitutes choice arguments`() async throws {
    let catalog = DialogueCatalog(
        boot: ["boot"],
        randomTalk: ["random"],
        mouseClick: ["Head": ["head"], "*": ["other"]],
        choices: ["OnChoice": ["selected {{argument0}}"]]
    )
    let engine = DialoguePersonalityEngine(catalog: catalog)

    #expect(try await engine.handle(event: .boot)?.rawValue == "boot")
    #expect(try await engine.handle(event: .mouseClick(region: "Head"))?.rawValue == "head")
    #expect(try await engine.handle(event: .mouseClick(region: nil))?.rawValue == "other")
    #expect(
        try await engine.handle(event: .choice(id: "OnChoice", arguments: ["B"]))?.rawValue
            == "selected B"
    )
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
    #expect(try await session.stop()?.rawValue == "close")
    #expect(try await session.handle(event: .randomTalk) == nil)
    #expect(await session.state == .stopped)
}

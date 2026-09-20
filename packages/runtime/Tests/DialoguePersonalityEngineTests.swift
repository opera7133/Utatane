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

@Test func `session sends boot only when the primary lifecycle event has no script`() async throws {
    let fallbackEngine = LifecycleRecordingEngine(scripts: ["OnBoot": #"\0boot\e"#])
    let fallbackSession = GhostSession(personalityEngine: fallbackEngine)
    _ = try await fallbackSession.start(event: .shiori(id: "OnInitialize", references: [:]))
    let fallback = try await fallbackSession.handle(
        event: SHIORIEventFactory.firstBoot(vanishCount: 0),
        fallingBackTo: SHIORIEventFactory.boot(shellName: "master")
    )
    #expect(fallback?.rawValue == #"\0boot\e"#)
    #expect(await fallbackEngine.eventIDs == ["OnInitialize", "OnFirstBoot", "OnBoot"])

    let handledEngine = LifecycleRecordingEngine(scripts: ["OnGhostCalled": #"\0called\e"#])
    let handledSession = GhostSession(personalityEngine: handledEngine)
    _ = try await handledSession.start(event: .shiori(id: "OnInitialize", references: [:]))
    let handled = try await handledSession.handle(
        event: SHIORIEventFactory.ghostCalled(
            callerCharacterName: "Caller",
            callerScript: "",
            callerGhostName: "Caller Ghost",
            callerGhostPath: "/ghost/caller",
            shellName: "master"
        ),
        fallingBackTo: SHIORIEventFactory.boot(shellName: "master")
    )
    #expect(handled?.rawValue == #"\0called\e"#)
    #expect(await handledEngine.eventIDs == ["OnInitialize", "OnGhostCalled"])
}

@Test @MainActor
func `session records normalized SHIORI requests and responses`() async throws {
    let logStore = AppLogStore()
    let engine = DialoguePersonalityEngine(catalog: DialogueCatalog(boot: [#"\0hello\e"#]))
    let session = GhostSession(
        personalityEngine: engine,
        logStore: logStore,
        ghostName: "Test Ghost"
    )

    _ = try await session.start()
    let entries = logStore.snapshot()

    #expect(entries.map(\.message) == ["SHIORI request: OnBoot", "SHIORI response: OnBoot"])
    #expect(entries[0].details == "No Reference")
    #expect(entries[1].details == #"Value: \0hello\e"#)
    #expect(entries.allSatisfy { $0.category == "SHIORI" && $0.ghostName == "Test Ghost" })
}

private actor RecordingPersonalityEngine: PersonalityEngine {
    private(set) var lastEvent: GhostEvent?
    private let responseEventIDs: Set<String>

    init(responseEventIDs: Set<String> = []) {
        self.responseEventIDs = responseEventIDs
    }

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        lastEvent = event
        guard case let .shiori(id, _) = event, responseEventIDs.contains(id) else { return nil }
        return SakuraScript(rawValue: "handled")
    }
}

private actor LifecycleRecordingEngine: PersonalityEngine {
    private(set) var eventIDs: [String] = []
    private let scripts: [String: String]

    init(scripts: [String: String]) {
        self.scripts = scripts
    }

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        let eventID = switch event {
        case let .shiori(id, _): id
        default: "other"
        }
        eventIDs.append(eventID)
        return scripts[eventID].map(SakuraScript.init(rawValue:))
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
    let engine = RecordingPersonalityEngine(responseEventIDs: ["OnGhostChanging"])
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
func `session sends close references`() async throws {
    let engine = RecordingPersonalityEngine()
    let session = GhostSession(personalityEngine: engine)
    _ = try await session.start()
    _ = try await session.stop(reason: .closeDetailed(reason: "user", menuScope: 1, windowScope: 2))

    #expect(await engine.lastEvent == .shiori(id: "OnClose", references: [
        0: "user", 1: "1", 2: "2"
    ]))
}

@Test
func `session falls back from close all to close only for no content`() async throws {
    let fallbackEngine = LifecycleRecordingEngine(scripts: ["OnClose": #"\0close\e"#])
    let fallbackSession = GhostSession(personalityEngine: fallbackEngine)
    _ = try await fallbackSession.start()
    let fallback = try await fallbackSession.stop(reason: .closeAll(
        reason: "user", menuScope: 0, windowScope: 0
    ))
    #expect(fallback?.rawValue == #"\0close\e"#)
    #expect(await fallbackEngine.eventIDs == ["other", "OnCloseAll", "OnClose"])

    let handledEngine = LifecycleRecordingEngine(scripts: ["OnCloseAll": #"\0all\e"#])
    let handledSession = GhostSession(personalityEngine: handledEngine)
    _ = try await handledSession.start()
    let handled = try await handledSession.stop(reason: .closeAll(
        reason: "system", menuScope: 0, windowScope: 0
    ))
    #expect(handled?.rawValue == #"\0all\e"#)
    #expect(await handledEngine.eventIDs == ["other", "OnCloseAll"])
}

@Test
func `session falls back from ghost changing to close only for no content`() async throws {
    let engine = LifecycleRecordingEngine(scripts: ["OnClose": #"\0close\e"#])
    let session = GhostSession(personalityEngine: engine)
    _ = try await session.start()

    let fallback = try await session.stop(reason: .ghostChangingDetailed(
        name: "さくら",
        mode: "manual",
        ghostName: "次のゴースト",
        path: "/tmp/next"
    ))

    #expect(fallback?.rawValue == #"\0close\e"#)
    #expect(await engine.eventIDs == ["other", "OnGhostChanging", "OnClose"])
}

@Test
func `session sends vanish selected before shutdown`() async throws {
    let engine = RecordingPersonalityEngine()
    let session = GhostSession(personalityEngine: engine)
    _ = try await session.start()
    _ = try await session.stop(reason: .vanish)

    #expect(await engine.lastEvent == .shiori(id: "OnVanishSelected", references: [:]))
    #expect(await session.state == .stopped)
}

@Test
func `decodes an older dialogue catalog without ghost changing scripts`() throws {
    let data = Data(#"{"boot":["boot"],"close":["close"]}"#.utf8)
    let catalog = try JSONDecoder().decode(DialogueCatalog.self, from: data)

    #expect(catalog.ghostChanging.isEmpty)
    #expect(catalog.scripts(for: .ghostChanging(name: nil)) == ["close"])
}

import Testing
import UtataneCore
@testable import UtataneRuntime
import UtataneSakuraScript

private actor StatusProbe: PersonalityEngine {
    var status = ""
    var received: [String] = []
    func updateRequestStatus(_ status: String) async {
        self.status = status
    }

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        received.append(status); return nil
    }
}

private actor StatusSource {
    var status = ""
    func set(_ status: String) {
        self.status = status
    }
}

@Test func `session refreshes status for startup response fallback and close`() async throws {
    let engine = StatusProbe()
    let source = StatusSource()
    let session = GhostSession(personalityEngine: engine, requestStatus: { await source.status })
    _ = try await session.start()
    await source.set("talking,timecritical")
    _ = try await session.response(for: .randomTalk)
    _ = try await session.handle(event: .randomTalk, fallingBackTo: .boot)
    await source.set("passive")
    _ = try await session.stop()
    #expect(await engine.received == ["", "talking,timecritical", "talking,timecritical", "talking,timecritical", "passive"])
}

import Testing
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript

struct PersonalityShutdownTests {
    private actor Engine: PersonalityEngine {
        let fails: Bool
        var shutdowns = 0

        init(fails: Bool) {
            self.fails = fails
        }

        func handle(event: GhostEvent) async throws -> SakuraScript? {
            if case .close = event, fails {
                throw Failure.close
            }
            return nil
        }

        func shutdown() async {
            shutdowns += 1
        }
    }

    private enum Failure: Error { case close }

    @Test(arguments: [false, true])
    func `stop awaits shutdown even after close failure`(fails: Bool) async throws {
        let engine = Engine(fails: fails)
        let session = GhostSession(personalityEngine: engine)
        _ = try await session.start()
        if fails {
            await #expect(throws: Failure.self) { try await session.stop() }
        } else {
            _ = try await session.stop()
        }
        #expect(await engine.shutdowns == 1)
        _ = try await session.stop()
        #expect(await engine.shutdowns == 1)
    }

    @Test
    func `session can unload and load its personality engine while running`() async throws {
        let first = Engine(fails: false)
        let second = Engine(fails: false)
        let session = GhostSession(personalityEngine: first)
        _ = try await session.start()

        await session.unloadPersonalityEngine()
        #expect(await first.shutdowns == 1)
        #expect(await session.isPersonalityEngineLoaded == false)
        #expect(try await session.handle(event: .randomTalk) == nil)

        await session.loadPersonalityEngine(second)
        #expect(await session.isPersonalityEngineLoaded)
        _ = try await session.handle(event: .randomTalk)
        await session.shutdown()
        #expect(await second.shutdowns == 1)
    }
}

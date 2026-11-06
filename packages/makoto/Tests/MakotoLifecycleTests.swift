import Foundation
import Testing
import UtataneCore
import UtataneMakoto
import UtataneRuntime
import UtataneSakuraScript

struct MakotoLifecycleTests {
    private actor Engine: PersonalityEngine {
        var requests = 0
        var shutdowns = 0
        var statuses: [String] = []
        var pending: CheckedContinuation<SakuraScript?, Never>?
        var started: CheckedContinuation<Void, Never>?

        func handle(event: GhostEvent) async -> SakuraScript? {
            requests += 1
            if case .shiori(id: "Wait", references: _) = event {
                return await withCheckedContinuation { continuation in
                    pending = continuation
                    started?.resume()
                    started = nil
                }
            }
            return SakuraScript(rawValue: "A\(requests)")
        }

        func response(for event: GhostEvent) async -> PersonalityResponse {
            await PersonalityResponse(script: handle(event: event), references: [0: "A unchanged"])
        }

        func updateRequestStatus(_ status: String) {
            statuses.append(status)
        }

        func shutdown() {
            shutdowns += 1
        }

        func waitForRequest() async {
            guard pending == nil else { return }
            await withCheckedContinuation { started = $0 }
        }

        func finishRequest() {
            pending?.resume(returning: SakuraScript(rawValue: "A delayed"))
            pending = nil
        }
    }

    private final class Translator: SakuraScriptTranslator {
        let replacement: String
        init(_ replacement: String) {
            self.replacement = replacement
        }

        func translate(_ script: SakuraScript) -> SakuraScript {
            SakuraScript(rawValue: script.rawValue.replacingOccurrences(of: "A", with: replacement))
        }
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "makoto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func `changing MAKOTO preserves the same SHIORI state and forwards status`() async throws {
        let engine = Engine()
        let session = GhostSession(personalityEngine: engine, scriptTranslators: [Translator("B")], requestStatus: { "passive" })
        #expect(try await session.start()?.rawValue == "B1")
        await session.setScriptTranslators([])
        #expect(try await session.handle(event: .randomTalk)?.rawValue == "A2")
        await session.setScriptTranslators([Translator("C")])
        #expect(try await session.handle(event: .randomTalk)?.rawValue == "C3")
        #expect(await engine.shutdowns == 0)
        #expect(await engine.statuses == ["passive", "passive", "passive"])
        #expect(try await session.stop()?.rawValue == "C4")
        await session.shutdown()
        _ = try await session.stop()
        #expect(await engine.shutdowns == 1)
    }

    @Test func `SHIORI unload and replacement preserve independently configured MAKOTO`() async throws {
        let first = Engine()
        let second = Engine()
        let session = GhostSession(personalityEngine: first, scriptTranslators: [Translator("B")])
        _ = try await session.start()
        await session.unloadPersonalityEngine()
        await session.setScriptTranslators([Translator("C")])
        #expect(await session.isPersonalityEngineLoaded == false)
        #expect(try await session.handle(event: .randomTalk) == nil)
        await session.loadPersonalityEngine(second)
        #expect(try await session.handle(event: .randomTalk)?.rawValue == "C1")
        await session.unloadPersonalityEngine()
        await session.setScriptTranslators([])
        let third = Engine()
        await session.loadPersonalityEngine(third)
        #expect(try await session.handle(event: .randomTalk)?.rawValue == "A1")
        await session.shutdown()
        #expect(await first.shutdowns == 1)
        #expect(await second.shutdowns == 1)
        #expect(await third.shutdowns == 1)
    }

    @Test func `main and called sessions keep separate converter chains`() async throws {
        let first = GhostSession(personalityEngine: Engine(), scriptTranslators: [Translator("main")])
        let called = GhostSession(personalityEngine: Engine(), scriptTranslators: [Translator("called")])
        _ = try await first.start()
        _ = try await called.start()
        await called.setScriptTranslators([])
        #expect(try await called.handle(event: .randomTalk)?.rawValue == "A2")
        #expect(try await first.handle(event: .randomTalk)?.rawValue == "main2")
        await first.shutdown()
        await called.shutdown()
    }

    @Test func `response conversion preserves reference headers and notification suppression`() async throws {
        let engine = Engine()
        let session = GhostSession(personalityEngine: engine, scriptTranslators: [Translator("B"), Translator("C")])
        _ = try await session.start()
        let response = try await session.response(for: .randomTalk)
        #expect(response?.script?.rawValue == "B2")
        #expect(response?.references == [0: "A unchanged"])
        #expect(try await session.response(for: .notification(id: "probe", references: [:])) == nil)
        await session.shutdown()
    }

    @Test func `a pending SHIORI response uses the current MAKOTO chain without resetting SHIORI`() async throws {
        let engine = Engine()
        let session = GhostSession(personalityEngine: engine, scriptTranslators: [Translator("B")])
        _ = try await session.start()
        let response = Task { try await session.handle(event: .shiori(id: "Wait", references: [:])) }
        await engine.waitForRequest()
        await session.setScriptTranslators([Translator("C")])
        await engine.finishRequest()
        #expect(try await response.value?.rawValue == "C delayed")
        #expect(await engine.shutdowns == 0)
        await session.shutdown()
    }

    @Test func `reload reads fresh lists and failure leaves converters and SHIORI intact`() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "makoto.dll"))
        let rules = root.appending(path: "makoto0.lst")
        try Data("A,B\n".utf8).write(to: rules)
        let loader = MakotoTranslatorLoader()
        let engine = Engine()
        let session = try GhostSession(personalityEngine: engine, scriptTranslators: loader.load(from: root))
        #expect(try await session.start()?.rawValue == "B1")
        try Data("A,C\n".utf8).write(to: rules)
        try await session.setScriptTranslators(loader.load(from: root))
        #expect(try await session.handle(event: .randomTalk)?.rawValue == "C2")
        try FileManager.default.removeItem(at: rules)
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) {
            try await session.setScriptTranslators(loader.load(from: root))
        }
        #expect(try await session.handle(event: .randomTalk)?.rawValue == "C3")
        #expect(await engine.shutdowns == 0)
        await session.shutdown()
    }

    @Test func `unload and shutdown release converters and stopped sessions reject new ones`() async throws {
        let session = GhostSession(personalityEngine: Engine())
        weak var converter: Translator?
        do {
            let translator = Translator("B")
            converter = translator
            await session.setScriptTranslators([translator])
        }
        #expect(converter != nil)
        _ = try await session.start()
        await session.setScriptTranslators([])
        #expect(converter == nil)
        do {
            let translator = Translator("C")
            converter = translator
            await session.setScriptTranslators([translator])
        }
        await session.shutdown()
        #expect(converter == nil)
        do {
            let translator = Translator("D")
            converter = translator
            await session.setScriptTranslators([translator])
        }
        #expect(converter == nil)
    }

    @Test func `an empty MAKOTO installation leaves SHIORI responses unchanged`() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try GhostSession(personalityEngine: Engine(), scriptTranslators: MakotoTranslatorLoader().load(from: root))
        #expect(try await session.start()?.rawValue == "A1")
        await session.shutdown()
    }
}

import Foundation
import Testing
import UtataneAI
import UtataneCore

@Test func `AI engine sends boot and renders validated speech`() async throws {
    let client = RecordingAIClient(output: .init(speech: .init(text: "起きた。", surface: 9)))
    let engine = AIPersonalityEngine(
        manifest: .init(prompt: "りあ", allowedSurfaces: [0, 9]),
        client: client,
        now: { Date(timeIntervalSince1970: 0) }
    )
    #expect(try await engine.handle(event: .boot)?.rawValue == #"\0\s[9]起きた。\e"#)
    #expect(await client.lastInput()?.event == "OnBoot")
}

@Test func `AI engine rejects unavailable surfaces and escapes SakuraScript`() async throws {
    let client = RecordingAIClient(output: .init(speech: .init(text: #"\![execute,open] 100%"#, surface: 999)))
    let engine = AIPersonalityEngine(manifest: .init(prompt: "りあ", allowedSurfaces: [0], fallbackSurface: 0), client: client)
    #expect(try await engine.handle(event: .randomTalk)?.rawValue == #"\0\s[0]￥![execute,open] 100％\e"#)
}

@Test func `AI engine throttles continuous second events`() async throws {
    let clock = TestClock()
    let client = CountingAIClient()
    let engine = AIPersonalityEngine(
        manifest: .init(prompt: "りあ", allowedSurfaces: [0]),
        client: client,
        now: { clock.now() }
    )
    _ = try await engine.handle(event: .shiori(id: "OnSecondChange", references: [:]))
    _ = try await engine.handle(event: .shiori(id: "OnSecondChange", references: [:]))
    #expect(await client.count == 1)
    clock.advance(by: 61)
    _ = try await engine.handle(event: .shiori(id: "OnSecondChange", references: [:]))
    #expect(await client.count == 2)
}

private actor RecordingAIClient: AIProviderClient {
    let output: AIPersonalityOutput
    var input: AIPersonalityInput?
    init(output: AIPersonalityOutput) {
        self.output = output
    }

    func respond(systemPrompt: String, history: [AIConversationMessage], input: AIPersonalityInput) async throws -> AIPersonalityOutput {
        self.input = input
        return output
    }

    func lastInput() -> AIPersonalityInput? {
        input
    }
}

private actor CountingAIClient: AIProviderClient {
    var count = 0
    func respond(systemPrompt: String, history: [AIConversationMessage], input: AIPersonalityInput) async throws -> AIPersonalityOutput {
        count += 1
        return .init(speech: nil)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 0)
    func now() -> Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value.addTimeInterval(interval) }
    }
}

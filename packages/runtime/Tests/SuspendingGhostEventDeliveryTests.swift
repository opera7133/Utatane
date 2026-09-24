import Foundation
import Testing
import UtataneCore
@testable import UtataneRuntime
import UtataneSakuraScript

@MainActor
struct SuspendingGhostEventDeliveryTests {
    @Test func `requests and in flight responses wait for cache restoration`() async throws {
        let engine = ControlledEngine()
        let session = GhostSession(personalityEngine: engine)
        _ = try await session.start()
        let delivery = SuspendingGhostEventDelivery(session: session)
        delivery.setSuspended(true)
        var started = false
        var completed = false
        let request = Task {
            started = true
            let value = try await delivery.handle(event: .shiori(id: "queued", references: [:]))
            completed = true
            return value
        }
        try await until { started }
        #expect(engine.events.isEmpty)
        #expect(!completed)
        delivery.setSuspended(false)
        try await until { completed }
        #expect(try await request.value?.rawValue == "queued")
        #expect(engine.events == ["queued"])

        completed = false
        let inFlight = Task {
            let value = try await delivery.response(for: .shiori(id: "slow", references: [:]))
            completed = true
            return value
        }
        try await until { engine.continuation != nil }
        delivery.setSuspended(true)
        engine.release()
        #expect(!completed)
        // Lifecycle calls deliberately bypass the delivery gate.
        _ = try await session.handle(event: .shiori(id: "OnCacheRestore", references: [:]))
        #expect(!completed)
        delivery.setSuspended(false)
        try await until { completed }
        #expect(try await inFlight.value?.script?.rawValue == "slow")
        #expect(engine.events == ["queued", "slow", "OnCacheRestore"])
    }

    @Test func `discarding a suspended session releases work without delivering it`() async throws {
        let engine = ControlledEngine()
        let session = GhostSession(personalityEngine: engine)
        _ = try await session.start()
        let delivery = SuspendingGhostEventDelivery(session: session)
        var completed = false
        let inFlight = Task {
            let value = try await delivery.handle(event: .shiori(id: "slow", references: [:]))
            completed = true
            return value
        }
        try await until { engine.continuation != nil }
        delivery.setSuspended(true)
        engine.release()
        delivery.finish()
        try await until { completed }
        #expect(try await inFlight.value == nil)
        #expect(try await delivery.response(for: .shiori(id: "late", references: [:])) == nil)
        #expect(engine.events == ["slow"])
    }

    private func until(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(predicate())
    }
}

@MainActor
private final class ControlledEngine: PersonalityEngine {
    var events: [String] = []
    var continuation: CheckedContinuation<Void, Never>?

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        guard case let .shiori(id, _) = event else { return nil }
        events.append(id)
        if id == "slow" {
            await withCheckedContinuation { continuation = $0 }
        }
        return SakuraScript(rawValue: id)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

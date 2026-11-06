import UtataneCore
import UtataneSakuraScript

public struct PersonalityResponse: Sendable, Equatable {
    public let script: SakuraScript?
    public let references: [Int: String]

    public init(script: SakuraScript?, references: [Int: String] = [:]) {
        self.script = script
        self.references = references
    }
}

/// A session-owned script conversion stage, independent of the personality engine lifetime.
public protocol PersonalityScriptTranslator: Sendable {
    func translate(_ script: SakuraScript) -> SakuraScript
}

/// Produces SakuraScript for an event. Built-in dialogue, YAYA, and SHIORI are adapters of this API.
public protocol PersonalityEngine: Sendable {
    func handle(event: GhostEvent) async throws -> SakuraScript?
    func response(for event: GhostEvent) async throws -> PersonalityResponse
    func shutdown() async
    func updateRequestStatus(_ status: String) async
}

public extension PersonalityEngine {
    func shutdown() async {}

    func updateRequestStatus(_ status: String) async {}

    func response(for event: GhostEvent) async throws -> PersonalityResponse {
        try await PersonalityResponse(script: handle(event: event))
    }
}

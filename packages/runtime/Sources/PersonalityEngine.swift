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

/// Produces SakuraScript for an event. Built-in dialogue, YAYA, and SHIORI are adapters of this API.
public protocol PersonalityEngine: Sendable {
    func handle(event: GhostEvent) async throws -> SakuraScript?
    func response(for event: GhostEvent) async throws -> PersonalityResponse
}

public extension PersonalityEngine {
    func response(for event: GhostEvent) async throws -> PersonalityResponse {
        try await PersonalityResponse(script: handle(event: event))
    }
}

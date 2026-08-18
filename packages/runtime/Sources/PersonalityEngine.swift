import UtataneCore
import UtataneSakuraScript

/// Produces SakuraScript for an event. Built-in dialogue, YAYA, and SHIORI are adapters of this API.
public protocol PersonalityEngine: Sendable {
    func handle(event: GhostEvent) async throws -> SakuraScript?
}

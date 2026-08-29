import UtataneCore
import UtataneRuntime
import UtataneSakuraScript

public protocol SakuraScriptTranslator: Sendable {
    func translate(_ script: SakuraScript) -> SakuraScript
}

public struct TranslatingPersonalityEngine: PersonalityEngine {
    private let base: any PersonalityEngine
    private let translators: [any SakuraScriptTranslator]

    public init(base: any PersonalityEngine, translators: [any SakuraScriptTranslator]) {
        self.base = base
        self.translators = translators
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await base.handle(event: event).map(translate)
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let response = try await base.response(for: event)
        return PersonalityResponse(script: response.script.map(translate), references: response.references)
    }

    public func shutdown() async {
        await base.shutdown()
    }

    private func translate(_ script: SakuraScript) -> SakuraScript {
        translators.reduce(script) { result, translator in
            translator.translate(result)
        }
    }
}

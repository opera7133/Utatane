import Foundation

/// Builds a complete replacement before the session discards its current converters.
public struct MakotoTranslatorLoader: Sendable {
    public init() {}

    public func load(from masterDirectory: URL) throws -> [any SakuraScriptTranslator] {
        var translators: [any SakuraScriptTranslator] = []
        if ParticleMakotoTranslator.supports(masterDirectoryURL: masterDirectory) {
            translators.append(ParticleMakotoTranslator())
        }
        if BasicMakotoTranslator.supports(masterDirectoryURL: masterDirectory) {
            try translators.append(BasicMakotoTranslator(masterDirectoryURL: masterDirectory))
        }
        return translators
    }
}

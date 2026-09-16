import Foundation
import UtataneCore
import UtataneNetwork
import UtataneSakuraScript

@MainActor
final class SNTPEventCoordinator {
    typealias EventHandler = @MainActor (String, [Int: String]) async -> SakuraScript?
    typealias ClockCorrector = @Sendable (Date) async -> Bool

    private let client: SNTPClient
    private let server: URL
    private let handleEvent: EventHandler
    private let correctClock: ClockCorrector
    private var comparison: SNTPComparison?

    init(
        client: SNTPClient = SNTPClient(),
        server: URL = URL(string: "https://www.apple.com")!,
        correctClock: @escaping ClockCorrector = { _ in false },
        handleEvent: @escaping EventHandler
    ) {
        self.client = client
        self.server = server
        self.correctClock = correctClock
        self.handleEvent = handleEvent
    }

    func start() async -> SakuraScript? {
        let begin = await handle(SHIORIEventFactory.sntpBegin(server: server.absoluteString))
        do {
            let comparison = try await client.compare(server: server)
            self.comparison = comparison
            var compare = await handle(SHIORIEventFactory.sntpCompareExtended(
                references: comparison.extendedReferences
            ))
            if compare == nil {
                compare = await handle(SHIORIEventFactory.sntpCompare(
                    references: comparison.legacyReferences
                ))
            }
            return Self.join(begin, compare)
        } catch {
            comparison = nil
            let failure = await handle(SHIORIEventFactory.sntpFailure(server: server.absoluteString))
            return Self.join(begin, failure)
        }
    }

    func correct() async -> SakuraScript? {
        guard let comparison, await correctClock(comparison.serverDate) else { return nil }
        var corrected = await handleEvent("OnSNTPCorrectEx", comparison.extendedReferences)
        if corrected == nil {
            corrected = await handleEvent("OnSNTPCorrect", comparison.correctedLegacyReferences)
        }
        self.comparison = nil
        return corrected
    }

    private func handle(_ event: GhostEvent) async -> SakuraScript? {
        guard case let .shiori(id, references) = event else { return nil }
        return await handleEvent(id, references)
    }

    private static func join(_ first: SakuraScript?, _ second: SakuraScript?) -> SakuraScript? {
        var firstValue = first?.rawValue ?? ""
        if second != nil, firstValue.hasSuffix(#"\e"#) {
            firstValue.removeLast(2)
        }
        let value = firstValue + (second?.rawValue ?? "")
        return value.isEmpty ? nil : SakuraScript(rawValue: value)
    }
}

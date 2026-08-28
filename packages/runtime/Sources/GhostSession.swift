import UtataneCore
import UtataneSakuraScript

public actor GhostSession {
    public enum State: Sendable, Equatable {
        case inactive
        case running
        case stopped
    }

    private let personalityEngine: any PersonalityEngine
    private let variableStore: GhostVariableStore?
    private let logStore: AppLogStore?
    private let ghostName: String?
    public private(set) var state: State = .inactive

    public init(
        personalityEngine: any PersonalityEngine,
        variableStore: GhostVariableStore? = nil,
        logStore: AppLogStore? = nil,
        ghostName: String? = nil
    ) {
        self.personalityEngine = personalityEngine
        self.variableStore = variableStore
        self.logStore = logStore
        self.ghostName = ghostName
    }

    public func start(event: GhostEvent = .boot) async throws -> SakuraScript? {
        guard state == .inactive else { return nil }
        state = .running
        return try await handleLogged(event: event)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        guard state == .running else { return nil }
        return try await handleLogged(event: event)
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse? {
        guard state == .running else { return nil }
        logRequest(event)
        do {
            let response = try await personalityEngine.response(for: event)
            logResponse(event: event, response: response)
            return response
        } catch {
            logError(event: event, error: error)
            throw error
        }
    }

    public func stop(reason: GhostStopReason = .close) async throws -> SakuraScript? {
        guard state == .running else { return nil }
        state = .stopped
        let event: GhostEvent = switch reason {
        case .close:
            .close
        case let .ghostChanging(name):
            .ghostChanging(name: name)
        case let .ghostChangingDetailed(name, mode, ghostName, path):
            .shiori(id: "OnGhostChanging", references: [
                0: name ?? "", 1: mode, 2: ghostName, 3: path
            ])
        }
        do {
            let script = try await handleLogged(event: event)
            await personalityEngine.shutdown()
            return script
        } catch {
            await personalityEngine.shutdown()
            throw error
        }
    }

    public func variable(forKey key: String) async throws -> String? {
        try await variableStore?.value(forKey: key)
    }

    public func setVariable(_ value: String?, forKey key: String) async throws {
        try await variableStore?.setValue(value, forKey: key)
    }

    private func handleLogged(event: GhostEvent) async throws -> SakuraScript? {
        logRequest(event)
        do {
            let script = try await personalityEngine.handle(event: event)
            logResponse(event: event, response: PersonalityResponse(script: script))
            return script
        } catch {
            logError(event: event, error: error)
            throw error
        }
    }

    private func logRequest(_ event: GhostEvent) {
        logStore?.debug(
            "SHIORI request: \(event.logID)",
            category: "SHIORI",
            details: event.logReferences,
            ghostName: ghostName
        )
    }

    private func logResponse(event: GhostEvent, response: PersonalityResponse) {
        let references = response.references.keys.sorted().map {
            "Reference\($0): \(response.references[$0] ?? "")"
        }
        var detailLines = references
        if let script = response.script {
            detailLines.insert("Value: \(script.rawValue)", at: 0)
        }
        let details = detailLines.joined(separator: "\n")
        logStore?.debug(
            "SHIORI response: \(event.logID)",
            category: "SHIORI",
            details: details.isEmpty ? "No Content" : details,
            ghostName: ghostName
        )
    }

    private func logError(event: GhostEvent, error: Error) {
        logStore?.error(
            "SHIORI error: \(event.logID)",
            category: "SHIORI",
            details: error.localizedDescription,
            ghostName: ghostName
        )
    }
}

private extension GhostEvent {
    var logID: String {
        switch self {
        case .boot: "OnBoot"
        case .close: "OnClose"
        case .ghostChanging: "OnGhostChanging"
        case .mouseClick: "OnMouseClick"
        case let .mouse(event): String(describing: event.kind)
        case let .shiori(id, _): id
        case .randomTalk: "OnSecondChange/randomTalk"
        case .choice: "OnChoiceSelect"
        }
    }

    var logReferences: String {
        let references: [Int: String] = switch self {
        case let .ghostChanging(name): [0: name ?? ""]
        case let .mouseClick(scope, region): [0: String(scope), 1: region ?? ""]
        case let .mouse(event): [
                0: String(event.scope),
                1: event.region ?? "",
                2: String(event.x),
                3: String(event.y),
                4: String(event.button)
            ]
        case let .shiori(_, references): references
        case let .choice(id, arguments):
            [0: id].merging(Dictionary(uniqueKeysWithValues: arguments.enumerated().map { ($0.offset + 1, $0.element) })) { current, _ in current }
        case .boot, .close, .randomTalk: [:]
        }
        guard !references.isEmpty else { return "No Reference" }
        return references.keys.sorted().map { "Reference\($0): \(references[$0] ?? "")" }.joined(separator: "\n")
    }
}

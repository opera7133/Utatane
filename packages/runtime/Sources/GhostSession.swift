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
    public private(set) var state: State = .inactive

    public init(
        personalityEngine: any PersonalityEngine,
        variableStore: GhostVariableStore? = nil
    ) {
        self.personalityEngine = personalityEngine
        self.variableStore = variableStore
    }

    public func start() async throws -> SakuraScript? {
        guard state == .inactive else { return nil }
        state = .running
        return try await personalityEngine.handle(event: .boot)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        guard state == .running else { return nil }
        return try await personalityEngine.handle(event: event)
    }

    public func stop() async throws -> SakuraScript? {
        guard state == .running else { return nil }
        state = .stopped
        return try await personalityEngine.handle(event: .close)
    }

    public func variable(forKey key: String) async throws -> String? {
        try await variableStore?.value(forKey: key)
    }

    public func setVariable(_ value: String?, forKey key: String) async throws {
        try await variableStore?.setValue(value, forKey: key)
    }
}

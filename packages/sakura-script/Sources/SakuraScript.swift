/// A script produced by a personality engine.
public struct SakuraScript: RawRepresentable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

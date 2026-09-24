/// Offsets are source Character counts, not encoded bytes or rendered text counts.
public struct SakuraScriptSourceLocation: Equatable, Sendable {
    public let range: Range<Int>
    /// Source position after each displayed Character; nil for atomic commands.
    public let textCharacterEnds: [Int]?

    public init(range: Range<Int>, textCharacterEnds: [Int]? = nil) {
        self.range = range
        self.textCharacterEnds = textCharacterEnds
    }
}

public struct SakuraScriptLocatedToken: Equatable, Sendable {
    public let token: SakuraScriptToken
    public let location: SakuraScriptSourceLocation

    public init(token: SakuraScriptToken, location: SakuraScriptSourceLocation) {
        self.token = token
        self.location = location
    }
}

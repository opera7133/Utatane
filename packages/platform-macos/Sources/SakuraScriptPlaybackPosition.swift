public struct SakuraScriptPlaybackPosition: Equatable, Sendable {
    public let script: String
    public let scope: Int
    public let characterOffset: Int

    public var references: [Int: String] {
        [0: script, 1: String(scope), 2: String(characterOffset)]
    }
}

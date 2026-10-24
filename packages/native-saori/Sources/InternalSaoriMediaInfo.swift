import Foundation

public struct InternalSaoriMediaInfo: Sendable {
    public let kind: String
    public let values: [String: String]
    public init(kind: String = "", values: [String: String] = [:]) {
        self.kind = kind
        self.values = values
    }
}

public protocol InternalSaoriMediaReading: Sendable {
    func read(_ url: URL) throws -> InternalSaoriMediaInfo
}

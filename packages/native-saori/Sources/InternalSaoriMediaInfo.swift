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
    func imageInfo(_ url: URL) throws -> InternalSaoriMediaInfo
    func imageLoadability(_ url: URL) throws -> InternalSaoriLoadability
    func mediaLoadability(_ url: URL) throws -> InternalSaoriLoadability
}

public enum InternalSaoriLoadability: String, Sendable {
    case none, read, embed, write
}

public extension InternalSaoriMediaReading {
    func imageInfo(_ url: URL) throws -> InternalSaoriMediaInfo {
        let info = try read(url)
        return info.kind == "image" ? info : .init()
    }

    func imageLoadability(_: URL) throws -> InternalSaoriLoadability {
        .none
    }

    func mediaLoadability(_: URL) throws -> InternalSaoriLoadability {
        .none
    }
}

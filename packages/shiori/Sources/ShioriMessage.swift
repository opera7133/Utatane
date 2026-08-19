import Foundation

public struct ShioriHeader: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ShioriHeaders: Equatable, Sendable {
    public private(set) var entries: [ShioriHeader]

    public init(_ entries: [ShioriHeader] = []) {
        self.entries = entries
    }

    public subscript(name: String) -> String? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func values(named name: String) -> [String] {
        entries.compactMap {
            $0.name.caseInsensitiveCompare(name) == .orderedSame ? $0.value : nil
        }
    }

    public mutating func append(name: String, value: String) {
        entries.append(ShioriHeader(name: name, value: value))
    }
}

public struct ShioriRequest: Equatable, Sendable {
    public let method: String
    public let version: String
    public var headers: ShioriHeaders

    public init(method: String, version: String = "SHIORI/3.0", headers: ShioriHeaders = .init()) {
        self.method = method
        self.version = version
        self.headers = headers
    }

    public var id: String? {
        headers["ID"]
    }

    public func reference(_ index: Int) -> String? {
        headers["Reference\(index)"]
    }

    public func serialized() -> String {
        serialize(startLine: "\(method) \(version)", headers: headers)
    }
}

public struct ShioriResponse: Equatable, Sendable {
    public let version: String
    public let statusCode: Int
    public let reasonPhrase: String
    public var headers: ShioriHeaders

    public init(
        version: String = "SHIORI/3.0",
        statusCode: Int,
        reasonPhrase: String,
        headers: ShioriHeaders = .init()
    ) {
        self.version = version
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers
    }

    public var value: String? {
        headers["Value"]
    }

    public func serialized() -> String {
        serialize(startLine: "\(version) \(statusCode) \(reasonPhrase)", headers: headers)
    }
}

private func serialize(startLine: String, headers: ShioriHeaders) -> String {
    let lines = [startLine] + headers.entries.map { "\($0.name): \($0.value)" }
    return lines.joined(separator: "\r\n") + "\r\n\r\n"
}

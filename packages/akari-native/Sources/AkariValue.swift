import Foundation

enum AkariValue: Codable, Equatable, Sendable {
    case null
    case integer(Int)
    case double(Double)
    case string(String)
    case array([AkariValue])
    case dictionary([String: AkariValue])

    var stringValue: String {
        switch self {
        case .null: ""
        case let .integer(value): String(value)
        case let .double(value): String(value)
        case let .string(value): value
        case let .array(values): "{" + values.map(\.literal).joined(separator: ",") + "}"
        case let .dictionary(values):
            "${" + values.sorted(by: { $0.key < $1.key }).map { "$(\(Self.quote($0.key)),\($0.value.literal))" }.joined(separator: ",") + "}"
        }
    }

    var literal: String {
        switch self {
        case let .string(value): Self.quote(value)
        default: stringValue
        }
    }

    var integerValue: Int? {
        switch self {
        case let .integer(value): value
        case let .double(value): Int(value)
        case let .string(value): Int(value)
        default: nil
        }
    }

    var typeName: String {
        switch self {
        case .null: "nil"
        case .integer: "long"
        case .double: "double"
        case .string: "string"
        case .array: "array"
        case .dictionary: "dict"
        }
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

struct AkariValueParser {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func parse() -> AkariValue? {
        skipSpaces()
        guard let value = parseValue() else { return nil }
        skipSpaces()
        return index == characters.count ? value : nil
    }

    private mutating func parseValue() -> AkariValue? {
        skipSpaces()
        guard index < characters.count else { return .string("") }
        if characters[index] == "\"" {
            return parseString().map(AkariValue.string)
        }
        if characters[index] == "$", peek(1) == "{" {
            return parseDictionary()
        }
        if characters[index] == "{" {
            return parseArray()
        }
        let token = parseToken()
        if token == "nil" {
            return .null
        }
        if let value = Int(token) {
            return .integer(value)
        }
        if let value = Double(token), token.contains(".") {
            return .double(value)
        }
        return .string(token)
    }

    private mutating func parseArray() -> AkariValue? {
        index += 1
        var values: [AkariValue] = []
        while index < characters.count {
            skipSpaces()
            if characters[index] == "}" {
                index += 1; return .array(values)
            }
            guard let value = parseValue() else { return nil }
            values.append(value)
            skipSpaces()
            if index < characters.count, characters[index] == "," {
                index += 1; continue
            }
            if index < characters.count, characters[index] == "}" {
                index += 1; return .array(values)
            }
            return nil
        }
        return nil
    }

    private mutating func parseDictionary() -> AkariValue? {
        index += 2
        var values: [String: AkariValue] = [:]
        while index < characters.count {
            skipSpaces()
            if characters[index] == "}" {
                index += 1; return .dictionary(values)
            }
            guard characters[index] == "$", peek(1) == "(" else { return nil }
            index += 2
            guard let key = parseValue(), consumeComma(), let value = parseValue() else { return nil }
            skipSpaces()
            guard index < characters.count, characters[index] == ")" else { return nil }
            index += 1
            values[key.stringValue] = value
            skipSpaces()
            if index < characters.count, characters[index] == "," {
                index += 1; continue
            }
            if index < characters.count, characters[index] == "}" {
                index += 1; return .dictionary(values)
            }
            return nil
        }
        return nil
    }

    private mutating func parseString() -> String? {
        index += 1
        var result = ""
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == "\"" {
                return result
            }
            if character == "\\", index < characters.count, characters[index] == "\"" || characters[index] == "\\" {
                result.append(characters[index])
                index += 1
            } else {
                result.append(character)
            }
        }
        return nil
    }

    private mutating func parseToken() -> String {
        let start = index
        while index < characters.count, ![",", ")", "}"].contains(characters[index]) {
            index += 1
        }
        return String(characters[start ..< index]).trimmingCharacters(in: .whitespaces)
    }

    private mutating func consumeComma() -> Bool {
        skipSpaces()
        guard index < characters.count, characters[index] == "," else { return false }
        index += 1
        return true
    }

    private mutating func skipSpaces() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private func peek(_ offset: Int) -> Character? {
        let target = index + offset
        return target < characters.count ? characters[target] : nil
    }
}

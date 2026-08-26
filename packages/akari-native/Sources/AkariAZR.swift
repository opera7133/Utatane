import Foundation

struct AkariFunction: Sendable {
    let parameters: [String]
    let body: String
}

enum AkariStatement: Sendable {
    case simple(String)
    case conditional(condition: String, thenBody: String, elseBody: String?)
    case whileLoop(condition: String, body: String)
    case forLoop(initializer: String, condition: String, increment: String, body: String)
    case switchStatement(expression: String, body: String)
}

enum AkariAZRParser {
    static func globalDeclarations(in source: String) -> [(name: String, expression: String?)] {
        let source = removingComments(from: source)
        var declarations: [(String, String?)] = []
        var start = source.startIndex
        var braceDepth = 0
        var quoted = false
        var escaped = false
        for index in source.indices {
            let character = source[index]
            if escaped {
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if character == "{" {
                    braceDepth += 1
                }
                if character == "}" {
                    braceDepth -= 1
                }
                if character == ";", braceDepth == 0 {
                    declarations.append(contentsOf: trailingDeclarationList(String(source[start ..< index])))
                    start = source.index(after: index)
                }
            }
        }
        return declarations
    }

    private static func trailingDeclarationList(_ source: String) -> [(name: String, expression: String?)] {
        let pattern = #"(?:^|\s)(?:static\s+)?(?:string|int|long|double|array|dict)\s+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            let start = source[range].firstIndex(where: { $0.isLetter }) ?? range.lowerBound
            let result = declarationList(String(source[start...]))
            if !result.isEmpty {
                return result
            }
        }
        return []
    }

    static func declarationList(_ source: String) -> [(name: String, expression: String?)] {
        let types = ["string", "int", "long", "double", "array", "dict"]
        var source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("static ") {
            source = String(source.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard let type = types.first(where: { source.hasPrefix($0 + " ") || source.hasPrefix($0 + "\t") }) else { return [] }
        return splitTopLevelCommas(String(source.dropFirst(type.count))).compactMap { item in
            let item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if let separator = topLevelEquals(item) {
                let name = item[..<separator].trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : (name, String(item[item.index(after: separator)...]))
            }
            let defaultValue = switch type {
            case "array": "{}"
            case "dict": "${}"
            case "string": "\"\""
            default: "0"
            }
            return item.isEmpty ? nil : (item, defaultValue)
        }
    }

    static func functions(in source: String) -> [String: AkariFunction] {
        let pattern = #"(?m)^[ \t]*(?:(?:string|int|long|double|array|dict|void)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*\{"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(source.startIndex..., in: source)
        var functions: [String: AkariFunction] = [:]
        for match in expression.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let parametersRange = Range(match.range(at: 2), in: source),
                  let matchRange = Range(match.range, in: source),
                  let opening = source[..<matchRange.upperBound].lastIndex(of: "{"),
                  let closing = closingBrace(in: source, opening: opening)
            else { continue }
            let parameters = source[parametersRange].split(separator: ",").compactMap { parameter -> String? in
                let fields = parameter.split(whereSeparator: \Character.isWhitespace)
                return fields.last.map(String.init)
            }
            let body = String(source[source.index(after: opening) ..< closing])
            functions[String(source[nameRange])] = AkariFunction(parameters: parameters, body: body)
        }
        return functions
    }

    static func statements(in body: String) -> [String] {
        let body = removingComments(from: body)
        var statements: [String] = []
        var start = body.startIndex
        var parenthesisDepth = 0
        var braceDepth = 0
        var quoted = false
        var escaped = false
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if escaped {
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if character == "(" {
                    parenthesisDepth += 1
                }
                if character == ")" {
                    parenthesisDepth -= 1
                }
                if character == "{" {
                    braceDepth += 1
                }
                if character == "}" {
                    braceDepth -= 1
                }
                if character == ";", parenthesisDepth == 0, braceDepth == 0 {
                    statements.append(String(body[start ..< index]).trimmingCharacters(in: .whitespacesAndNewlines))
                    start = body.index(after: index)
                }
            }
            index = body.index(after: index)
        }
        let remainder = body[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            statements.append(remainder)
        }
        return statements.filter { !$0.isEmpty }
    }

    static func nodes(in body: String) -> [AkariStatement]? {
        var parser = AkariStatementParser(removingComments(from: body))
        return parser.parse()
    }

    private static func removingComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        var quoted = false
        var escaped = false
        while index < source.endIndex {
            let character = source[index]
            if escaped {
                result.append(character)
                escaped = false
                index = source.index(after: index)
                continue
            }
            if character == "\\", quoted {
                result.append(character)
                escaped = true
                index = source.index(after: index)
                continue
            }
            if character == "\"" {
                quoted.toggle()
                result.append(character)
                index = source.index(after: index)
                continue
            }
            if !quoted, source[index...].hasPrefix("//") {
                index = source[index...].firstIndex(where: \Character.isNewline) ?? source.endIndex
                continue
            }
            if !quoted, source[index...].hasPrefix("/*") {
                if let end = source[index...].range(of: "*/")?.upperBound {
                    result.append(contentsOf: source[index ..< end].filter(\.isNewline))
                    index = end
                } else {
                    break
                }
                continue
            }
            result.append(character)
            index = source.index(after: index)
        }
        return result
    }

    private static func splitTopLevelCommas(_ source: String) -> [String] {
        var result: [String] = []
        var start = source.startIndex
        var depths = (parenthesis: 0, brace: 0, bracket: 0)
        var quoted = false
        var escaped = false
        for index in source.indices {
            let character = source[index]
            if escaped {
                escaped = false; continue
            }
            if character == "\\", quoted {
                escaped = true; continue
            }
            if character == "\"" {
                quoted.toggle(); continue
            }
            guard !quoted else { continue }
            if character == "(" {
                depths.parenthesis += 1
            }
            if character == ")" {
                depths.parenthesis -= 1
            }
            if character == "{" {
                depths.brace += 1
            }
            if character == "}" {
                depths.brace -= 1
            }
            if character == "[" {
                depths.bracket += 1
            }
            if character == "]" {
                depths.bracket -= 1
            }
            if character == ",", depths == (0, 0, 0) {
                result.append(String(source[start ..< index]))
                start = source.index(after: index)
            }
        }
        result.append(String(source[start...]))
        return result
    }

    private static func topLevelEquals(_ source: String) -> String.Index? {
        var depths = (parenthesis: 0, brace: 0, bracket: 0)
        var quoted = false
        for index in source.indices {
            let character = source[index]
            if character == "\"" {
                quoted.toggle(); continue
            }
            guard !quoted else { continue }
            if character == "(" {
                depths.parenthesis += 1
            }
            if character == ")" {
                depths.parenthesis -= 1
            }
            if character == "{" {
                depths.brace += 1
            }
            if character == "}" {
                depths.brace -= 1
            }
            if character == "[" {
                depths.bracket += 1
            }
            if character == "]" {
                depths.bracket -= 1
            }
            if character == "=", depths == (0, 0, 0) {
                return index
            }
        }
        return nil
    }

    private static func closingBrace(in source: String, opening: String.Index) -> String.Index? {
        var depth = 0
        var quoted = false
        var escaped = false
        var index = opening
        while index < source.endIndex {
            let character = source[index]
            if escaped {
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if character == "{" {
                    depth += 1
                }
                if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}

private struct AkariStatementParser {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    mutating func parse() -> [AkariStatement]? {
        var result: [AkariStatement] = []
        while true {
            skipSpaces()
            guard index < characters.count else { return result }
            if consumeKeyword("if") {
                guard let condition = balanced(open: "(", close: ")"), let thenBody = statementBody() else { return nil }
                skipSpaces()
                var elseBody: String?
                if consumeKeyword("else") {
                    skipSpaces()
                    if startsKeyword("if") {
                        elseBody = String(characters[index...])
                        index = characters.count
                    } else {
                        elseBody = statementBody()
                    }
                }
                result.append(.conditional(condition: condition, thenBody: thenBody, elseBody: elseBody))
            } else if consumeKeyword("while") {
                guard let condition = balanced(open: "(", close: ")"), let body = statementBody() else { return nil }
                result.append(.whileLoop(condition: condition, body: body))
            } else if consumeKeyword("for") {
                guard let header = balanced(open: "(", close: ")"), let body = statementBody() else { return nil }
                let fields = splitHeader(header)
                guard fields.count == 3 else { return nil }
                result.append(.forLoop(initializer: fields[0], condition: fields[1], increment: fields[2], body: body))
            } else if consumeKeyword("switch") {
                guard let expression = balanced(open: "(", close: ")"), let body = balanced(open: "{", close: "}") else { return nil }
                result.append(.switchStatement(expression: expression, body: body))
            } else {
                guard let statement = simpleStatement() else { return nil }
                if !statement.isEmpty {
                    result.append(.simple(statement))
                }
            }
        }
    }

    private mutating func statementBody() -> String? {
        skipSpaces()
        if index < characters.count, characters[index] == "{" {
            return balanced(open: "{", close: "}")
        }
        return simpleStatement()
    }

    private mutating func balanced(open: Character, close: Character) -> String? {
        skipSpaces()
        guard index < characters.count, characters[index] == open else { return nil }
        index += 1
        let start = index
        var depth = 1
        var quoted = false
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if character == open {
                    depth += 1
                }
                if character == close {
                    depth -= 1
                    if depth == 0 {
                        let result = String(characters[start ..< index])
                        index += 1
                        return result
                    }
                }
            }
            index += 1
        }
        return nil
    }

    private mutating func simpleStatement() -> String? {
        let start = index
        var parenthesisDepth = 0
        var bracketDepth = 0
        var quoted = false
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if character == "(" {
                    parenthesisDepth += 1
                }
                if character == ")" {
                    parenthesisDepth -= 1
                }
                if character == "[" {
                    bracketDepth += 1
                }
                if character == "]" {
                    bracketDepth -= 1
                }
                if character == ";", parenthesisDepth == 0, bracketDepth == 0 {
                    let result = String(characters[start ..< index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    index += 1
                    return result
                }
            }
            index += 1
        }
        let result = String(characters[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "" : result
    }

    private func splitHeader(_ source: String) -> [String] {
        source.split(separator: ";", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private mutating func consumeKeyword(_ keyword: String) -> Bool {
        guard startsKeyword(keyword) else { return false }
        index += keyword.count
        return true
    }

    private func startsKeyword(_ keyword: String) -> Bool {
        let token = Array(keyword)
        guard index + token.count <= characters.count,
              Array(characters[index ..< index + token.count]) == token
        else { return false }
        let end = index + token.count
        return end == characters.count || !(characters[end].isLetter || characters[end].isNumber || characters[end] == "_")
    }

    private mutating func skipSpaces() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }
}

import Foundation
import UtataneNativeSaori
import UtataneShiori

struct MisakaEvaluator: Sendable {
    var dictionary: MisakaDictionary
    var variables: [String: [String]] = [:]
    var references: [Int: String] = [:]
    var sequenceIndexes: [String: Int] = [:]
    var nonoverlapIndexes: [String: [Int]] = [:]
    var mouseMoveCounts: [String: Int] = [:]
    var extraHeaders: [ShioriHeader] = []
    var backupRequested = false
    var handlingPropertyChange = false
    var saoriDebugEntries: [String] = []
    var saoriCaller: (any NativeSaoriCalling)?
    var recursionDepth = 0

    mutating func evaluate(symbol name: String) -> String {
        guard recursionDepth < 64, let candidates = dictionary.symbols[name] else { return "" }
        recursionDepth += 1
        defer { recursionDepth -= 1 }
        var selectedCandidate: MisakaCandidate?
        for candidate in candidates {
            var matches = true
            for condition in candidate.conditions where !evaluateCondition(condition) {
                matches = false
                break
            }
            if matches {
                selectedCandidate = candidate
                break
            }
        }
        guard let candidate = selectedCandidate else { return "" }
        let index = selectedIndex(for: name, candidate: candidate)
        return expand(candidate.values[index])
    }

    mutating func expand(_ source: String) -> String {
        var output = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard let open = source[cursor...].range(of: "{$")?.lowerBound else {
                output += source[cursor...]
                break
            }
            output += source[cursor ..< open]
            guard let close = matchingBrace(in: source, from: open) else {
                output += source[open...]
                break
            }
            let contentStart = source.index(open, offsetBy: 2)
            output += evaluateExpression(String(source[contentStart ..< close]))
            cursor = source.index(after: close)
        }
        return output.trimmingCharacters(in: .newlines)
    }

    private func matchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var index = start
        while index < text.endIndex {
            if text[index...].hasPrefix("{") {
                depth += 1
            }
            if text[index...].hasPrefix("}") {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private mutating func evaluateExpression(_ raw: String) -> String {
        let expression = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if expression.hasPrefix("if") {
            return evaluateIf(expression)
        }
        if let assignment = assignmentParts(expression) {
            return assign(name: assignment.name, operation: assignment.operation, value: assignment.value)
        }
        if expression.hasSuffix("++") {
            return increment(String(expression.dropLast(2)), by: 1)
        }
        if expression.hasSuffix("--") {
            return increment(String(expression.dropLast(2)), by: -1)
        }
        if let call = functionCall(expression) {
            return callFunction(call.name, arguments: call.arguments)
        }
        let name = expression.hasPrefix("$") ? String(expression.dropFirst()) : expression
        if let indexed = indexedVariable(name) {
            if let values = variables[indexed.name] {
                return values.indices.contains(indexed.index) ? values[indexed.index] : ""
            }
            if let candidate = dictionary.symbols["$" + indexed.name]?.first {
                return candidate.values.indices.contains(indexed.index) ? expand(candidate.values[indexed.index]) : ""
            }
            return ""
        }
        if let values = variables[name] {
            return values.randomElement() ?? ""
        }
        return evaluate(symbol: "$" + name)
    }

    private mutating func evaluateIf(_ expression: String) -> String {
        guard let range = parenthesizedRange(in: expression) else { return "" }
        let condition = String(expression[range])
        let remainder = expression[expression.index(after: range.upperBound)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard remainder.hasPrefix("{") else { return boolString(evaluateBoolean(condition)) }
        let text = String(remainder)
        guard let trueEnd = matchingBrace(in: text, from: text.startIndex) else { return "" }
        let trueStart = text.index(after: text.startIndex)
        let trueValue = String(text[trueStart ..< trueEnd])
        let after = text[text.index(after: trueEnd)...].trimmingCharacters(in: .whitespacesAndNewlines)
        var falseValue = ""
        if after.hasPrefix("else") {
            let block = after.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            if block.hasPrefix("{") {
                let blockText = String(block)
                if let end = matchingBrace(in: blockText, from: blockText.startIndex) {
                    falseValue = String(blockText[blockText.index(after: blockText.startIndex) ..< end])
                }
            }
        }
        return expand(evaluateBoolean(condition) ? trueValue : falseValue)
    }

    private mutating func evaluateCondition(_ condition: String) -> Bool {
        var expression = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if expression.hasPrefix("{$if") {
            expression.removeFirst(4)
            if expression.hasSuffix("}") {
                expression.removeLast()
            }
        }
        expression = expression.trimmingCharacters(in: CharacterSet(charactersIn: "; \t"))
        return evaluateBoolean(expression)
    }

    private mutating func evaluateBoolean(_ raw: String) -> Bool {
        let value = expand(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = topLevelOperator("||", in: value) {
            return evaluateBoolean(String(value[..<range.lowerBound])) || evaluateBoolean(String(value[range.upperBound...]))
        }
        if let range = topLevelOperator("&&", in: value) {
            return evaluateBoolean(String(value[..<range.lowerBound])) && evaluateBoolean(String(value[range.upperBound...]))
        }
        let stripped = stripParentheses(value)
        for operation in ["!=", "<=", ">=", "==", "<", ">"] {
            if let range = stripped.range(of: operation) {
                let lhs = unquote(String(stripped[..<range.lowerBound]).trimmingCharacters(in: .whitespaces))
                let rhs = unquote(String(stripped[range.upperBound...]).trimmingCharacters(in: .whitespaces))
                if let left = Int(lhs), let right = Int(rhs) {
                    switch operation { case "!=": return left != right; case "<=": return left <= right; case ">=": return left >= right; case "==": return left == right; case "<": return left < right; default: return left > right }
                }
                return operation == "!=" ? lhs != rhs : operation == "==" && lhs == rhs
            }
        }
        return stripped == "true" || (Int(stripped) ?? 0) != 0
    }

    private func topLevelOperator(_ operation: String, in text: String) -> Range<String.Index>? {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "(" {
                depth += 1
            }
            if text[index] == ")" {
                depth -= 1
            }
            if depth == 0, text[index...].hasPrefix(operation) {
                return index ..< text.index(index, offsetBy: operation.count)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private mutating func callFunction(_ name: String, arguments: [String]) -> String {
        let values = arguments.map { unquote(expand($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
        switch name.lowercased() {
        case "reference": return values.first.flatMap(Int.init).flatMap { references[$0] } ?? ""
        case "random": return values.first.flatMap(Int.init).map { String(Int.random(in: 0 ..< max($0, 1))) } ?? "0"
        case "choice": return values.randomElement() ?? ""
        case "length": return String(values.first?.lengthOfBytes(using: .shiftJIS) ?? 0)
        case "substring", "substringw": return substring(values, wide: name.lowercased().hasSuffix("w"))
        case "substringl", "substringwl": return substringEdge(values, left: true, wide: name.lowercased().hasSuffix("w"))
        case "substringr", "substringwr": return substringEdge(values, left: false, wide: name.lowercased().hasSuffix("w"))
        case "substringfirst": return values.first?.first.map(String.init) ?? ""
        case "substringlast": return values.first?.last.map(String.init) ?? ""
        case "index": return byteIndex(values)
        case "getvalue": return splitValue(values, separator: ",")
        case "getvalueex": return splitValue(values, separator: "\u{1}")
        case "insentence": return values.dropFirst().allSatisfy { values.first?.contains($0) == true } ? "true" : "false"
        case "inlastsentence": return values.allSatisfy { variables["lastsentence"]?.first?.contains($0) == true } ? "true" : "false"
        case "isequallastandfirst": return values.count >= 2 && values[0].last == values[1].first ? "true" : "false"
        case "extractfilename": return values.first.map(extractFilename) ?? ""
        case "hiraganacase": return values.first.map(hiraganaCase) ?? ""
        case "getmousemovecount": return String(mouseMoveCounts[values.joined(separator: ":"), default: 0])
        case "resetmousemovecount": mouseMoveCounts[values.joined(separator: ":")] = 0; return ""
        case "loadsaori":
            if let path = values.first {
                saoriDebugEntries.append("LOAD \(path)")
                saoriCaller?.load(path)
            }
            return ""
        case "unloadsaori":
            if let path = values.first {
                saoriDebugEntries.append("UNLOAD \(path)")
                saoriCaller?.unload(path)
            }
            return ""
        case "saori":
            guard let path = values.first else { return "" }
            let arguments = Array(values.dropFirst())
            let response = saoriCaller?.call(path, arguments: arguments) ?? ""
            saoriDebugEntries.append("CALL \(path) \(arguments) -> \(response)")
            return response
        case "backup": backupRequested = true; return ""
        case "appendheader":
            guard let header = values.first,
                  let separator = header.firstIndex(of: ":")
            else { return "" }
            extraHeaders.append(ShioriHeader(
                name: String(header[..<separator]),
                value: String(header[header.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            ))
            return ""
        case "append":
            guard let first = arguments.first else { return "" }
            let variable = first.trimmingCharacters(in: CharacterSet(charactersIn: "$ \t"))
            if values.count > 1 {
                variables[variable, default: []].append(values[1])
            }
            return ""
        case "copy": return copyVariable(arguments)
        case "pop": return popVariable(arguments, matchingPrefix: nil)
        case "popmatchl": return popVariable(arguments, matchingPrefix: values.dropFirst().first)
        case "stringexists": return containsVariable(arguments, value: values.dropFirst().first)
        case "count": return arguments.first.map { String(variables[$0.trimmingCharacters(in: CharacterSet(charactersIn: "$ \t"))]?.count ?? -1) } ?? "-1"
        case "calc": return String(integerExpression(values.first ?? "0"))
        case "search": return search(values)
        case "isghostexists": return ghostExists(values.first)
        default: return ""
        }
    }

    private mutating func assign(name: String, operation: String, value: String) -> String {
        let key = name.trimmingCharacters(in: CharacterSet(charactersIn: "$ \t"))
        let evaluated = unquote(expand(value).trimmingCharacters(in: .whitespacesAndNewlines))
        if operation == "=" {
            variables[key] = evaluated.isEmpty
                ? []
                : [looksArithmetic(evaluated) ? String(integerExpression(evaluated)) : evaluated]
        } else {
            let old = Int(variables[key]?.first ?? "0") ?? 0
            let rhs = Int(evaluated) ?? integerExpression(evaluated)
            let result = switch operation { case "+=": old + rhs; case "-=": old - rhs; case "*=": old * rhs; default: rhs == 0 ? 0 : old / rhs }
            variables[key] = [String(result)]
        }
        notifyPropertyChanged(key)
        return ""
    }

    private mutating func increment(_ raw: String, by amount: Int) -> String {
        let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "$ \t"))
        variables[name] = [String((Int(variables[name]?.first ?? "0") ?? 0) + amount)]
        notifyPropertyChanged(name)
        return ""
    }

    private mutating func notifyPropertyChanged(_ name: String) {
        guard dictionary.propertyHandlerEnabled, !handlingPropertyChange else { return }
        handlingPropertyChange = true
        variables["name"] = ["$" + name]
        _ = evaluate(symbol: "$__OnPropertyChanged")
        handlingPropertyChange = false
    }

    private func assignmentParts(_ expression: String) -> (name: String, operation: String, value: String)? {
        for operation in ["+=", "-=", "*=", "/=", "="] {
            guard let range = expression.range(of: operation), !expression.contains("==") else { continue }
            return (String(expression[..<range.lowerBound]), operation, String(expression[range.upperBound...]))
        }
        return nil
    }

    private func functionCall(_ expression: String) -> (name: String, arguments: [String])? {
        guard let open = expression.firstIndex(of: "("), expression.hasSuffix(")") else { return nil }
        let name = String(expression[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: "$ \t"))
        return (name, splitArguments(String(expression[expression.index(after: open) ..< expression.index(before: expression.endIndex)])))
    }

    private func splitArguments(_ text: String) -> [String] {
        var result: [String] = [], current = "", depth = 0, quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
            }
            if !quoted, character == "(" {
                depth += 1
            }
            if !quoted, character == ")" {
                depth -= 1
            }
            if !quoted, depth == 0, character == "," {
                result.append(current); current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private mutating func selectedIndex(for name: String, candidate: MisakaCandidate) -> Int {
        guard candidate.values.count > 1 else { return 0 }
        switch candidate.selection {
        case .sequential:
            let index = sequenceIndexes[name, default: 0] % candidate.values.count
            sequenceIndexes[name] = index + 1
            return index
        case .nonoverlap:
            var remaining = nonoverlapIndexes[name] ?? []
            if remaining.isEmpty {
                remaining = Array(candidate.values.indices).shuffled()
            }
            let index = remaining.removeFirst()
            nonoverlapIndexes[name] = remaining
            return index
        case .random: return Int.random(in: 0 ..< candidate.values.count)
        }
    }

    private func substring(_ values: [String], wide: Bool) -> String {
        guard values.count >= 3, let offset = Int(values[1]), let count = Int(values[2]) else { return "" }
        if wide {
            let characters = Array(values[0])
            guard offset < characters.count else { return "" }
            return String(characters.dropFirst(max(offset, 0)).prefix(max(count, 0)))
        }
        return shiftJISSubstring(values[0], offset: offset, count: count)
    }

    private func substringEdge(_ values: [String], left: Bool, wide: Bool) -> String {
        guard values.count >= 2, let count = Int(values[1]) else { return "" }
        if wide {
            let characters = Array(values[0])
            return String(left ? characters.prefix(count) : characters.suffix(count))
        }
        let byteCount = values[0].data(using: .shiftJIS)?.count ?? 0
        return shiftJISSubstring(
            values[0],
            offset: left ? 0 : max(byteCount - count, 0),
            count: count
        )
    }

    private func shiftJISSubstring(_ value: String, offset: Int, count: Int) -> String {
        guard let data = value.data(using: .shiftJIS), offset >= 0, count >= 0, offset < data.count else {
            return ""
        }
        return String(data: data[offset ..< min(offset + count, data.count)], encoding: .shiftJIS) ?? ""
    }

    private func byteIndex(_ values: [String]) -> String {
        guard values.count >= 2,
              let needle = values[0].data(using: .shiftJIS),
              let haystack = values[1].data(using: .shiftJIS),
              let range = haystack.range(of: needle)
        else { return "-1" }
        return String(range.lowerBound)
    }

    private func hiraganaCase(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar -> Character in
            let converted = (0x30A1 ... 0x30F6).contains(scalar.value)
                ? UnicodeScalar(scalar.value - 0x60) ?? scalar
                : scalar
            return Character(String(converted))
        })
    }

    private func extractFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
            .last.map(String.init) ?? ""
    }

    private mutating func copyVariable(_ arguments: [String]) -> String {
        guard arguments.count >= 2 else { return "" }
        let source = variableName(arguments[0])
        variables[variableName(arguments[1])] = variables[source]
            ?? dictionary.symbols["$" + source]?.first?.values
            ?? []
        return ""
    }

    private func indexedVariable(_ value: String) -> (name: String, index: Int)? {
        guard value.hasSuffix("]"), let open = value.lastIndex(of: "[") else { return nil }
        let indexStart = value.index(after: open)
        guard let index = Int(value[indexStart ..< value.index(before: value.endIndex)]) else { return nil }
        return (String(value[..<open]), index)
    }

    private mutating func popVariable(_ arguments: [String], matchingPrefix: String?) -> String {
        guard let argument = arguments.first else { return "" }
        let name = variableName(argument)
        guard var values = variables[name], !values.isEmpty else { return "" }
        let matches = values.indices.filter { index in
            matchingPrefix.map { values[index].hasPrefix($0) } ?? true
        }
        guard let index = matches.randomElement() else { return "" }
        let result = values.remove(at: index)
        variables[name] = values
        return result
    }

    private func containsVariable(_ arguments: [String], value: String?) -> String {
        guard let argument = arguments.first, let value else { return "false" }
        return variables[variableName(argument)]?.contains(value) == true ? "true" : "false"
    }

    private mutating func search(_ values: [String]) -> String {
        let matches = dictionary.symbols.keys.filter { name in
            values.allSatisfy { name.contains($0) }
        }
        return matches.randomElement().map { evaluate(symbol: $0) } ?? ""
    }

    private func ghostExists(_ name: String?) -> String {
        guard let name else { return "false" }
        return variables["otherghostlist"]?.contains(name) == true ? "true" : "false"
    }

    private func variableName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "$ \t"))
    }

    private func splitValue(_ values: [String], separator: Character) -> String {
        guard values.count >= 2, let index = Int(values[1]) else { return "" }
        let parts = values[0].split(separator: separator, omittingEmptySubsequences: false)
        return parts.indices.contains(index) ? String(parts[index]) : ""
    }

    private func parenthesizedRange(in text: String) -> ClosedRange<String.Index>? {
        guard let open = text.firstIndex(of: "(") else { return nil }; var depth = 0; var index = open
        while index < text.endIndex {
            if text[index] == "(" {
                depth += 1
            }; if text[index] == ")" {
                depth -= 1; if depth == 0 {
                    return text.index(after: open) ... text.index(before: index)
                }
            }; index = text.index(after: index)
        }
        return nil
    }

    private func stripParentheses(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines); while result.hasPrefix("("), result.hasSuffix(")") {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }; return result
    }

    private func unquote(_ value: String) -> String {
        value.hasPrefix("\"") && value.hasSuffix("\"") ? String(value.dropFirst().dropLast()) : value
    }

    private func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func looksArithmetic(_ value: String) -> Bool {
        value.range(of: #"^[0-9+*/%^() -]+$"#, options: .regularExpression) != nil
    }

    private func integerExpression(_ value: String) -> Int {
        var parser = IntegerExpressionParser(value)
        return parser.parse()
    }
}

private struct IntegerExpressionParser {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) {
        characters = Array(expression.filter { !$0.isWhitespace })
    }

    mutating func parse() -> Int {
        parseAddition()
    }

    private mutating func parseAddition() -> Int {
        var value = parseMultiplication()
        while let operation = peek(), operation == "+" || operation == "-" {
            index += 1
            let right = parseMultiplication()
            value = operation == "+" ? value + right : value - right
        }
        return value
    }

    private mutating func parseMultiplication() -> Int {
        var value = parsePower()
        while let operation = peek(), operation == "*" || operation == "/" || operation == "%" {
            index += 1
            let right = parsePower()
            switch operation {
            case "*": value *= right
            case "/": value = right == 0 ? 0 : value / right
            default: value = right == 0 ? 0 : value % right
            }
        }
        return value
    }

    private mutating func parsePower() -> Int {
        let value = parseUnary()
        guard peek() == "^" else { return value }
        index += 1
        let exponent = parsePower()
        guard exponent >= 0 else { return 0 }
        return (0 ..< exponent).reduce(1) { result, _ in result * value }
    }

    private mutating func parseUnary() -> Int {
        if peek() == "-" {
            index += 1
            return -parseUnary()
        }
        if peek() == "+" {
            index += 1
            return parseUnary()
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Int {
        if peek() == "(" {
            index += 1
            let value = parseAddition()
            if peek() == ")" {
                index += 1
            }
            return value
        }
        var digits = ""
        while let character = peek(), character.isNumber {
            digits.append(character)
            index += 1
        }
        return Int(digits) ?? 0
    }

    private func peek() -> Character? {
        characters.indices.contains(index) ? characters[index] : nil
    }
}

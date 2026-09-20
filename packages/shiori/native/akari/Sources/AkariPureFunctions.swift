import CryptoKit
import Foundation

enum AkariPureFunctions {
    static func evaluate(_ name: String, arguments: [AkariValue]) -> AkariValue? {
        switch name.uppercased() {
        case "_URLENCODE": return arguments.first.flatMap { encodeURL($0.stringValue) }.map(AkariValue.string)
        case "_URLDECODE": return arguments.first?.stringValue.removingPercentEncoding.map(AkariValue.string)
        case "_BASE64ENCODE": return arguments.first.map { .string(Data($0.stringValue.utf8).base64EncodedString()) }
        case "_BASE64DECODE":
            return arguments.first.flatMap { Data(base64Encoded: $0.stringValue) }.flatMap { String(data: $0, encoding: .utf8) }.map(AkariValue.string)
        case "_MD5":
            guard let value = arguments.first else { return nil }
            return .string(Insecure.MD5.hash(data: Data(value.stringValue.utf8)).map { String(format: "%02x", $0) }.joined())
        case "_JSON2AZV": return arguments.first.flatMap(jsonToValue)
        case "_AZV2JSON": return arguments.first.flatMap(valueToJSON).map(AkariValue.string)
        case "_DICV":
            guard arguments.count >= 2 else { return nil }
            return .dictionary([arguments[0].stringValue: arguments[1]])
        case "_STRLEN", "STRLEN": return arguments.first.map { .integer($0.stringValue.count) }
        case "_STRSTR": return stringPosition(arguments)
        case "_SUBSTR", "SUBSTR": return substring(arguments)
        case "_STRSPLIT":
            guard arguments.count >= 2 else { return nil }
            return .array(arguments[0].stringValue.components(separatedBy: arguments[1].stringValue).map(AkariValue.string))
        case "_STRREPLACE", "STRREPLACE":
            guard arguments.count >= 3 else { return nil }
            return .string(arguments[0].stringValue.replacingOccurrences(of: arguments[1].stringValue, with: arguments[2].stringValue))
        case "_REGEX_MATCH": return regexMatch(arguments)
        case "_REGEX_SEARCH": return regexSearch(arguments)
        case "_REGEX_REPLACE": return regexReplace(arguments)
        case "_RAND": return .integer(Int.random(in: 0 ... 9999))
        case "_BYTECHAR":
            guard let value = arguments.first?.integerValue, (0 ... 255).contains(value) else { return nil }
            return .string(String(decoding: [UInt8(value)], as: UTF8.self))
        case "_ZEN2HAN": return arguments.first.map { .string($0.stringValue.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? $0.stringValue) }
        case "_HAN2ZEN": return arguments.first.map { .string(halfwidthToFullwidth($0.stringValue)) }
        case "_SPRINTF": return formatted(arguments)
        case "_STRTOKENIZE": return arguments.first.map { .array(tokenize($0.stringValue).map(AkariValue.string)) }
        case "_GETTIME": return currentTime()
        case "_ETIME": return elapsedTime(arguments)
        case "_VERSION": return .string("2.003-utatane")
        case "_POW": return binaryDouble(arguments, pow)
        case "_FABS": return unaryDouble(arguments, abs)
        case "_SQRT": return unaryDouble(arguments, sqrt)
        case "_HYPOT": return binaryDouble(arguments, hypot)
        case "_SIN": return unaryDouble(arguments, sin)
        case "_COS": return unaryDouble(arguments, cos)
        case "_TAN": return unaryDouble(arguments, tan)
        case "_ASIN": return unaryDouble(arguments, asin)
        case "_ACOS": return unaryDouble(arguments, acos)
        case "_ATAN": return unaryDouble(arguments, atan)
        case "_ATAN2": return binaryDouble(arguments, atan2)
        case "_SINH": return unaryDouble(arguments, sinh)
        case "_COSH": return unaryDouble(arguments, cosh)
        case "_TANH": return unaryDouble(arguments, tanh)
        case "_EXP": return unaryDouble(arguments, exp)
        case "_LOG": return unaryDouble(arguments, log)
        case "_LOG10": return unaryDouble(arguments, log10)
        case "_FLOOR": return unaryDouble(arguments, floor)
        default: return nil
        }
    }

    private static func encodeURL(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }

    static func tokenize(_ source: String) -> [String] {
        var tokens: [String] = []
        var index = source.startIndex
        let pairs = ["==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=", "<<", ">>"]
        while index < source.endIndex {
            if source[index].isWhitespace {
                index = source.index(after: index)
                continue
            }
            if source[index...].hasPrefix("//") {
                index = source[index...].firstIndex(where: \Character.isNewline) ?? source.endIndex
                continue
            }
            if source[index...].hasPrefix("/*"), let end = source[index...].range(of: "*/")?.upperBound {
                index = end
                continue
            }
            if source[index] == "\"" {
                let start = index
                index = source.index(after: index)
                var escaped = false
                while index < source.endIndex {
                    let character = source[index]
                    index = source.index(after: index)
                    if escaped {
                        escaped = false; continue
                    }
                    if character == "\\" {
                        escaped = true; continue
                    }
                    if character == "\"" {
                        break
                    }
                }
                tokens.append(String(source[start ..< index]))
                continue
            }
            if let pair = pairs.first(where: { source[index...].hasPrefix($0) }) {
                tokens.append(pair)
                index = source.index(index, offsetBy: pair.count)
                continue
            }
            if source[index].isLetter || source[index].isNumber || source[index] == "_" {
                let start = index
                while index < source.endIndex, source[index].isLetter || source[index].isNumber || source[index] == "_" || source[index] == "." {
                    index = source.index(after: index)
                }
                tokens.append(String(source[start ..< index]))
                continue
            }
            tokens.append(String(source[index]))
            index = source.index(after: index)
        }
        return tokens
    }

    private static func halfwidthToFullwidth(_ source: String) -> String {
        String(source.map { character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return character }
            if scalar.value == 0x20 {
                return "　"
            }
            guard (0x21 ... 0x7E).contains(scalar.value), let converted = UnicodeScalar(scalar.value + 0xFEE0) else { return character }
            return Character(converted)
        })
    }

    private static func formatted(_ arguments: [AkariValue]) -> AkariValue? {
        guard let format = arguments.first else { return nil }
        var valueIndex = 1
        func render(_ source: String) -> String {
            let pattern = #"%(?:(\d+)\$)?([sdf%])"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
            var output = ""
            var cursor = source.startIndex
            for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source), let typeRange = Range(match.range(at: 2), in: source) else { continue }
                output += source[cursor ..< range.lowerBound]
                cursor = range.upperBound
                let type = source[typeRange]
                if type == "%" {
                    output += "%"; continue
                }
                let selected: Int
                if let positionRange = Range(match.range(at: 1), in: source), let position = Int(source[positionRange]) {
                    selected = position
                } else {
                    selected = valueIndex
                    valueIndex += 1
                }
                guard arguments.indices.contains(selected) else { output += source[range]; continue }
                let replacement = type == "d" ? String(arguments[selected].integerValue ?? 0) : arguments[selected].stringValue
                output += replacement
            }
            output += source[cursor...]
            return output
        }
        if case let .array(lines) = format {
            return .array(lines.map { .string(render($0.stringValue)) })
        }
        return .string(render(format.stringValue))
    }

    private static func jsonToValue(_ input: AkariValue) -> AkariValue? {
        let text: String = if case let .array(lines) = input {
            lines.map(\.stringValue).joined()
        } else {
            input.stringValue
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
        return value(from: object)
    }

    private static func valueToJSON(_ value: AkariValue) -> String? {
        guard JSONSerialization.isValidJSONObject(object(from: value)),
              let data = try? JSONSerialization.data(withJSONObject: object(from: value), options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func object(from value: AkariValue) -> Any {
        switch value {
        case .null: NSNull()
        case let .integer(value): value
        case let .double(value): value
        case let .string(value): value
        case let .array(values): values.map(object)
        case let .dictionary(values): values.mapValues(object)
        }
    }

    private static func value(from object: Any) -> AkariValue? {
        switch object {
        case is NSNull: .null
        case let value as String: .string(value)
        case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID(): .integer(value.boolValue ? 1 : 0)
        case let value as NSNumber where value.doubleValue.rounded() == value.doubleValue: .integer(value.intValue)
        case let value as NSNumber: .double(value.doubleValue)
        case let values as [Any]: .array(values.compactMap(value))
        case let values as [String: Any]: .dictionary(values.compactMapValues(value))
        default: nil
        }
    }

    private static func stringPosition(_ arguments: [AkariValue]) -> AkariValue? {
        guard arguments.count >= 2 else { return nil }
        let source = arguments[0].stringValue
        let offset = max(0, arguments.count > 2 ? arguments[2].integerValue ?? 0 : 0)
        guard offset <= source.count else { return .integer(-1) }
        let start = source.index(source.startIndex, offsetBy: offset)
        guard let range = source.range(of: arguments[1].stringValue, range: start ..< source.endIndex) else { return .integer(-1) }
        return .integer(source.distance(from: source.startIndex, to: range.lowerBound))
    }

    private static func substring(_ arguments: [AkariValue]) -> AkariValue? {
        guard arguments.count >= 2, let offset = arguments[1].integerValue else { return nil }
        let source = arguments[0].stringValue
        let startOffset = max(0, min(offset, source.count))
        let start = source.index(source.startIndex, offsetBy: startOffset)
        let length = arguments.count > 2 ? arguments[2].integerValue ?? source.count : source.count
        let end = source.index(start, offsetBy: length < 0 ? source.distance(from: start, to: source.endIndex) : min(length, source.distance(from: start, to: source.endIndex)))
        return .string(String(source[start ..< end]))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func regexMatch(_ arguments: [AkariValue]) -> AkariValue? {
        guard arguments.count >= 2, let expression = regex(arguments[1].stringValue) else { return nil }
        let source = arguments[0].stringValue
        let range = NSRange(source.startIndex..., in: source)
        return .integer(expression.firstMatch(in: source, range: range)?.range == range ? 1 : 0)
    }

    private static func regexSearch(_ arguments: [AkariValue]) -> AkariValue? {
        guard arguments.count >= 2, let expression = regex(arguments[1].stringValue) else { return nil }
        let source = arguments[0].stringValue
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let index = arguments.count > 2 ? arguments[2].integerValue ?? 0 : 0
        guard matches.indices.contains(index) else { return .array([]) }
        return .array((0 ..< matches[index].numberOfRanges).map { rangeIndex in
            Range(matches[index].range(at: rangeIndex), in: source).map { .string(String(source[$0])) } ?? .string("")
        })
    }

    private static func regexReplace(_ arguments: [AkariValue]) -> AkariValue? {
        guard arguments.count >= 3, let expression = regex(arguments[1].stringValue) else { return nil }
        let source = arguments[0].stringValue
        return .string(expression.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: arguments[2].stringValue))
    }

    private static func currentTime() -> AkariValue {
        let calendar = Calendar.current
        let now = Date()
        let values = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday], from: now)
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        return .dictionary(["年": .integer(values.year ?? 0), "月": .integer(values.month ?? 0), "日": .integer(values.day ?? 0),
                            "時": .integer(values.hour ?? 0), "分": .integer(values.minute ?? 0), "秒": .integer(values.second ?? 0),
                            "ミリ秒": .integer((values.nanosecond ?? 0) / 1_000_000), "週": .string(weekdays[(values.weekday ?? 1) - 1])])
    }

    private static func elapsedTime(_ arguments: [AkariValue]) -> AkariValue? {
        if arguments.isEmpty {
            return .integer(Int(Date().timeIntervalSince1970))
        }
        guard arguments.count >= 6 else { return nil }
        var components = DateComponents()
        components.year = arguments[0].integerValue
        components.month = arguments[1].integerValue
        components.day = arguments[2].integerValue
        components.hour = arguments[3].integerValue
        components.minute = arguments[4].integerValue
        components.second = arguments[5].integerValue
        return Calendar.current.date(from: components).map { .integer(Int($0.timeIntervalSince1970)) }
    }

    private static func unaryDouble(_ arguments: [AkariValue], _ operation: (Double) -> Double) -> AkariValue? {
        arguments.first.flatMap { Double($0.stringValue) }.map { .double(operation($0)) }
    }

    private static func binaryDouble(_ arguments: [AkariValue], _ operation: (Double, Double) -> Double) -> AkariValue? {
        guard arguments.count >= 2, let lhs = Double(arguments[0].stringValue), let rhs = Double(arguments[1].stringValue) else { return nil }
        return .double(operation(lhs, rhs))
    }
}

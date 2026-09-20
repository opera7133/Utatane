import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

private struct HisuiEntry: Sendable {
    let token: String
    let condition: String?
    let fallback: String?
    let emotionLimiter: Int?
    let scripts: [String]
}

private struct HisuiState: Codable, Sendable {
    var variables: [String: String] = [:]
}

private struct HisuiConfiguration: Sendable {
    var talkInterval = 120
    var emotionBorder = 50
    var birthday: String?
    var dictionaryDirectories = ["hisui_base"]
    var learningDirectories = ["hisui_lern"]
    var defaultCategories: [String: String] = [:]
}

public final class NativeHisuiPersonalityEngine: PersonalityEngine, @unchecked Sendable {
    private let adapter = GhostEventShioriAdapter()
    private let stateStoreURL: URL
    private let configuration: HisuiConfiguration
    private var entries: [String: [HisuiEntry]] = [:]
    private var wordCategories: [String: [String]] = [:]
    private var variables: [String: String]
    private var selfName = ""
    private var keroName = ""

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "hisui-state.json")
        configuration = Self.loadConfiguration(masterDirectoryURL)
        variables = [
            "talk_sw": "0",
            "__TalkInterval": String(configuration.talkInterval),
            "__Emotion": "0",
            "__EmotionBorder": String(configuration.emotionBorder),
            "__GhostBirthday": configuration.birthday ?? ""
        ]
        if let data = try? Data(contentsOf: self.stateStoreURL),
           let state = try? JSONDecoder().decode(HisuiState.self, from: data)
        {
            variables.merge(state.variables) { _, saved in saved }
        }
        variables["__EmotionBorder"] = String(configuration.emotionBorder)
        variables["__GhostBirthday"] = configuration.birthday ?? ""
        if let emotion = Int(variables["__Emotion", default: "0"]) {
            variables["__Emotion"] = String(max(-configuration.emotionBorder, min(configuration.emotionBorder, emotion)))
        }
        try loadDescription(masterDirectoryURL)
        let urls = try dictionaryURLs(masterDirectoryURL)
        for url in urls {
            guard let source = try decodeHisuiText(Data(contentsOf: url)) else { continue }
            // Foundation decodes CP932 byte 0x5C as a yen sign. Hisui TLK files
            // use that byte for SakuraScript and formula backslashes.
            parse(source.replacingOccurrences(of: "¥", with: "\\"))
        }
        try loadWordDictionaries(masterDirectoryURL)
    }

    public static func supports(shioriFilename: String?) -> Bool {
        shioriFilename?.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?
            .caseInsensitiveCompare("hisui.dll") == .orderedSame
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        let request = adapter.request(for: event)
        let requestID = request.id ?? ""
        let start: String = if event == .randomTalk {
            "OnHisuiFreeTalk"
        } else if entries.keys.contains(where: { $0.caseInsensitiveCompare(requestID) == .orderedSame }) {
            requestID
        } else {
            "OnHisuiGetResource"
        }
        guard let value = evaluate(token: start, request: request, visited: []) else { return nil }
        try save()
        return value.isEmpty ? nil : SakuraScript(rawValue: value)
    }

    public func shutdown() async {
        try? save()
    }

    private func evaluate(token: String, request: ShioriRequest, visited: Set<String>) -> String? {
        guard visited.count < 32, !visited.contains(token.lowercased()) else { return nil }
        var visited = visited
        visited.insert(token.lowercased())
        guard let candidates = entries.first(where: { $0.key.caseInsensitiveCompare(token) == .orderedSame })?.value else { return nil }
        for entry in candidates {
            if let limiter = entry.emotionLimiter,
               abs(Int(variables["__Emotion", default: "0"]) ?? 0) > abs(limiter)
            {
                continue
            }
            if let condition = entry.condition, !matches(condition, request: request) {
                if let fallback = entry.fallback, let value = evaluate(token: fallback, request: request, visited: visited) {
                    return value
                }
                continue
            }
            guard let script = entry.scripts.randomElement() else { continue }
            return expand(script, request: request, visited: visited)
        }
        return nil
    }

    private func expand(_ source: String, request: ShioriRequest, visited: Set<String>) -> String {
        var value = replaceReferenceFunctions(in: source, request: request)
        for index in 0 ... 31 {
            if let reference = request.reference(index) {
                value = value.replacingOccurrences(of: "%ref\(index)", with: reference)
            }
        }
        value = value.replacingOccurrences(of: "%selfname", with: selfName)
        value = value.replacingOccurrences(of: "%keroname", with: keroName)
        value = replacing(pattern: #"%([0-9]+)ref"#, in: value) { index in
            request.reference(Int(index) ?? 0) ?? ""
        }
        value = replacing(pattern: #"%\[([^]]+)\]"#, in: value) { name in
            name == "__ID" ? request.id ?? "" : variables[name, default: "0"]
        }
        value = replacing(pattern: #"%hour\[([^]]+)\]"#, in: value) { _ in
            wordForTime(category: "時間感覚_時", value: Calendar.current.component(.hour, from: Date()))
                ?? hourCategory(Calendar.current.component(.hour, from: Date()))
        }
        value = replacingFunctions(named: "%rand", in: value) { arguments in
            guard let upper = Int(arguments.first ?? ""), upper > 0 else { return "0" }
            return String(Int.random(in: 0 ..< upper))
        }
        value = replacingFunctions(named: "%strcmp", in: value) { arguments in
            guard arguments.count >= 2 else { return "1" }
            return arguments[0] == arguments[1] ? "0" : "1"
        }
        value = replacing(pattern: #"%BYTE\[(\d+)\]"#, in: value) { capture in
            UnicodeScalar(Int(capture) ?? 0).map(String.init) ?? ""
        }
        value = replaceWordFunctions(in: value)
        value = expandControlFlow(value, request: request, visited: visited)
        value = replacing(pattern: #"%token\[([^]]+)\]"#, in: value) { token in
            evaluate(token: token, request: request, visited: visited) ?? ""
        }
        value = applyFormulae(value, request: request)
        updateTalkInterval(from: value)
        value = value.replacingOccurrences(of: #"\\ti\[[^]]+\]"#, with: "", options: .regularExpression)
        return value
    }

    private func updateTalkInterval(from script: String) {
        guard let regex = try? NSRegularExpression(pattern: #"\\ti\[([0-9]+)\]"#),
              let match = regex.matches(in: script, range: NSRange(script.startIndex..., in: script)).last,
              let range = Range(match.range(at: 1), in: script)
        else { return }
        variables["__TalkInterval"] = String(script[range])
    }

    private func expandControlFlow(_ source: String, request: ShioriRequest, visited: Set<String>) -> String {
        var value = source
        while let marker = value.range(of: "%if(") {
            guard let conditionEnd = matchingDelimiter(in: value, openingAt: value.index(marker.upperBound, offsetBy: -1), open: "(", close: ")") else { break }
            let conditionStart = marker.upperBound
            let condition = String(value[conditionStart ..< conditionEnd])
            var cursor = value.index(after: conditionEnd)
            skipWhitespace(in: value, cursor: &cursor)
            guard cursor < value.endIndex, value[cursor] == "{",
                  let bodyEnd = matchingDelimiter(in: value, openingAt: cursor, open: "{", close: "}")
            else { break }

            var selected = expressionBoolean(condition) ? String(value[value.index(after: cursor) ..< bodyEnd]) : nil
            var end = value.index(after: bodyEnd)
            while true {
                var branch = end
                skipWhitespace(in: value, cursor: &branch)
                if value[branch...].hasPrefix("elseif(") {
                    let open = value.index(branch, offsetBy: 6)
                    guard let close = matchingDelimiter(in: value, openingAt: open, open: "(", close: ")") else { break }
                    let branchCondition = String(value[value.index(after: open) ..< close])
                    var bodyStart = value.index(after: close)
                    skipWhitespace(in: value, cursor: &bodyStart)
                    guard bodyStart < value.endIndex, value[bodyStart] == "{",
                          let branchEnd = matchingDelimiter(in: value, openingAt: bodyStart, open: "{", close: "}")
                    else { break }
                    if selected == nil, expressionBoolean(branchCondition) {
                        selected = String(value[value.index(after: bodyStart) ..< branchEnd])
                    }
                    end = value.index(after: branchEnd)
                } else if value[branch...].hasPrefix("else") {
                    var bodyStart = value.index(branch, offsetBy: 4)
                    skipWhitespace(in: value, cursor: &bodyStart)
                    guard bodyStart < value.endIndex, value[bodyStart] == "{",
                          let branchEnd = matchingDelimiter(in: value, openingAt: bodyStart, open: "{", close: "}")
                    else { break }
                    if selected == nil {
                        selected = String(value[value.index(after: bodyStart) ..< branchEnd])
                    }
                    end = value.index(after: branchEnd)
                } else {
                    break
                }
            }
            let replacement = selected.map { expand($0, request: request, visited: visited) } ?? ""
            value.replaceSubrange(marker.lowerBound ..< end, with: replacement)
        }
        return value
    }

    private func applyFormulae(_ source: String, request: ShioriRequest) -> String {
        var value = source
        while let marker = value.range(of: "\\formula[") {
            let opening = value.index(before: marker.upperBound)
            guard let closing = matchingDelimiter(in: value, openingAt: opening, open: "[", close: "]") else { break }
            let formula = String(value[marker.upperBound ..< closing])
            if let equals = formula.firstIndex(of: "=") {
                let name = formula[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
                let expression = String(formula[formula.index(after: equals)...])
                let result = expressionValue(conditionValue(expression, request: request))
                if name == "__Emotion", let emotion = Int(result) {
                    variables[name] = String(max(-configuration.emotionBorder, min(configuration.emotionBorder, emotion)))
                } else {
                    variables[name] = result
                }
            }
            value.removeSubrange(marker.lowerBound ... closing)
        }
        return value
    }

    private func expressionBoolean(_ source: String) -> Bool {
        var expression = source.trimmingCharacters(in: .whitespacesAndNewlines)
        while expression.first == "(", expression.last == ")",
              matchingDelimiter(in: expression, openingAt: expression.startIndex, open: "(", close: ")") == expression.index(before: expression.endIndex)
        {
            expression = String(expression.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = splitTopLevel(expression, separator: "||"), parts.count > 1 {
            return parts.contains(where: expressionBoolean)
        }
        if let parts = splitTopLevel(expression, separator: "&&"), parts.count > 1 {
            return parts.allSatisfy(expressionBoolean)
        }
        if expression.hasPrefix("!") {
            return !expressionBoolean(String(expression.dropFirst()))
        }
        for op in ["==", "!=", ">=", "<=", ">", "<"] {
            guard let parts = splitTopLevel(expression, separator: op), parts.count == 2 else { continue }
            let lhs = expressionValue(parts[0])
            let rhs = expressionValue(parts[1])
            if let left = Double(lhs), let right = Double(rhs) {
                return ["==": left == right, "!=": left != right, ">=": left >= right,
                        "<=": left <= right, ">": left > right, "<": left < right][op] ?? false
            }
            return op == "==" ? lhs == rhs : op == "!=" ? lhs != rhs : false
        }
        let result = unquoted(expression)
        return !result.isEmpty && result != "0"
    }

    private func expressionValue(_ source: String) -> String {
        var expression = source.trimmingCharacters(in: .whitespacesAndNewlines)
        while expression.first == "(", expression.last == ")",
              matchingDelimiter(in: expression, openingAt: expression.startIndex, open: "(", close: ")") == expression.index(before: expression.endIndex)
        {
            expression = String(expression.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for operators in [Set<Character>(["+", "-"]), Set<Character>(["*", "/"])] {
            if let operation = lastTopLevelOperation(in: expression, operators: operators) {
                let lhs = expressionValue(String(expression[..<operation.index]))
                let rhsStart = expression.index(after: operation.index)
                let rhs = expressionValue(String(expression[rhsStart...]))
                if operation.operator == "+", Double(lhs) == nil || Double(rhs) == nil {
                    return lhs + rhs
                }
                guard let left = Double(lhs), let right = Double(rhs) else { return unquoted(expression) }
                let result: Double = switch operation.operator {
                case "+": left + right
                case "-": left - right
                case "*": left * right
                default: right == 0 ? 0 : left / right
                }
                return result.rounded() == result ? String(Int(result)) : String(result)
            }
        }
        return unquoted(expression)
    }

    private func lastTopLevelOperation(
        in source: String,
        operators: Set<Character>
    ) -> (index: String.Index, operator: Character)? {
        var depth = 0
        var quoted = false
        var result: (String.Index, Character)?
        var previousSignificant: Character?
        for index in source.indices {
            let character = source[index]
            if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if "([".contains(character) {
                    depth += 1
                } else if ")]".contains(character) {
                    depth -= 1
                } else if depth == 0, operators.contains(character) {
                    let unary = (character == "+" || character == "-") &&
                        (previousSignificant == nil || "(+-*/".contains(previousSignificant!))
                    if !unary {
                        result = (index, character)
                    }
                }
            }
            if !character.isWhitespace {
                previousSignificant = character
            }
        }
        return result
    }

    private func replacingFunctions(
        named name: String,
        in source: String,
        transform: ([String]) -> String
    ) -> String {
        var value = source
        while let marker = value.range(of: name + "[") {
            let opening = value.index(before: marker.upperBound)
            guard let closing = matchingDelimiter(in: value, openingAt: opening, open: "[", close: "]") else { break }
            let body = String(value[marker.upperBound ..< closing])
            value.replaceSubrange(marker.lowerBound ... closing, with: transform(splitArguments(body)))
        }
        return value
    }

    private func splitArguments(_ source: String) -> [String] {
        var result: [String] = []
        var start = source.startIndex
        var depth = 0
        var quoted = false
        for index in source.indices {
            if source[index] == "\"" {
                quoted.toggle()
            }
            if !quoted {
                if "([".contains(source[index]) {
                    depth += 1
                }
                if ")]".contains(source[index]) {
                    depth -= 1
                }
                if source[index] == ",", depth == 0 {
                    result.append(unquoted(String(source[start ..< index])))
                    start = source.index(after: index)
                }
            }
        }
        result.append(unquoted(String(source[start...])))
        return result
    }

    private func splitTopLevel(_ source: String, separator: String) -> [String]? {
        var result: [String] = []
        var start = source.startIndex
        var index = source.startIndex
        var depth = 0
        var quoted = false
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                quoted.toggle()
            }
            if !quoted {
                if "([".contains(character) {
                    depth += 1
                }
                if ")]".contains(character) {
                    depth -= 1
                }
                if depth == 0, source[index...].hasPrefix(separator) {
                    result.append(String(source[start ..< index]))
                    index = source.index(index, offsetBy: separator.count)
                    start = index
                    continue
                }
            }
            index = source.index(after: index)
        }
        guard !result.isEmpty else { return nil }
        result.append(String(source[start...]))
        return result
    }

    private func matchingDelimiter(
        in source: String,
        openingAt opening: String.Index,
        open: Character,
        close: Character
    ) -> String.Index? {
        var depth = 0
        var quoted = false
        var index = opening
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                quoted.toggle()
            }
            if !quoted {
                if character == open {
                    depth += 1
                }
                if character == close {
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

    private func skipWhitespace(in source: String, cursor: inout String.Index) {
        while cursor < source.endIndex, source[cursor].isWhitespace {
            cursor = source.index(after: cursor)
        }
    }

    private func unquoted(_ source: String) -> String {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private func hourCategory(_ hour: Int) -> String {
        switch hour {
        case 0 ... 3: "深夜"
        case 4 ... 6: "早朝"
        case 7 ... 10: "朝"
        case 11 ... 13: "昼間"
        case 14 ... 16: "おやつ"
        case 17 ... 18: "夕方"
        case 19 ... 22: "夜"
        default: "テレホ"
        }
    }

    private func matches(_ source: String, request: ShioriRequest) -> Bool {
        expressionBoolean(conditionValue(source, request: request))
    }

    private func conditionValue(_ source: String, request: ShioriRequest) -> String {
        var value = source
        for index in 0 ... 31 {
            if let reference = request.reference(index) {
                value = value.replacingOccurrences(of: "%ref\(index)", with: reference)
            }
        }
        if value.contains("%[__ID]") {
            value = value.replacingOccurrences(of: "%[__ID]", with: request.id ?? "")
        }
        value = replacing(pattern: #"%\[([^]]+)\]"#, in: value) { variables[$0, default: "0"] }
        value = replacingFunctions(named: "%rand", in: value) { arguments in
            guard let upper = Int(arguments.first ?? ""), upper > 0 else { return "0" }
            return String(Int.random(in: 0 ..< upper))
        }
        value = replacingFunctions(named: "%strcmp", in: value) { arguments in
            guard arguments.count >= 2 else { return "1" }
            return arguments[0] == arguments[1] ? "0" : "1"
        }
        return value
    }

    private func parse(_ source: String) {
        let withoutComments = source.components(separatedBy: .newlines).map(stripLineComment).joined(separator: "\n")
        for body in topLevelBlocks(in: withoutComments) {
            let fields = fields(in: body)
            guard let token = fields["token"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { continue }
            let entry = HisuiEntry(
                token: token,
                condition: fields["conditional"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                fallback: fields["conditionalelse"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                emotionLimiter: fields["emotionlimiter"]?.first.flatMap {
                    Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                },
                scripts: fields["script", default: []].map(normalizeScript).filter { !$0.isEmpty }
            )
            entries[token, default: []].append(entry)
        }
    }

    private func topLevelBlocks(in source: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var blockStart: String.Index?
        for index in source.indices {
            switch source[index] {
            case "{":
                if depth == 0 {
                    blockStart = source.index(after: index)
                }
                depth += 1
            case "}" where depth > 0:
                depth -= 1
                if depth == 0 {
                    if let start = blockStart {
                        result.append(String(source[start ..< index]))
                    }
                    blockStart = nil
                }
            default:
                break
            }
        }
        return result
    }

    private func fields(in body: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var key: String?
        var value = ""
        func finish() {
            guard let key else { return }
            result[key, default: []].append(value)
        }
        for line in body.components(separatedBy: .newlines) {
            if let colon = line.firstIndex(of: ":") {
                let candidate = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if ["token", "conditional", "conditionalelse", "emotionlimiter", "script"].contains(candidate) {
                    finish()
                    key = candidate
                    value = String(line[line.index(after: colon)...])
                    continue
                }
            }
            if key != nil {
                value += "\n" + line
            }
        }
        finish()
        return result
    }

    private func normalizeScript(_ source: String) -> String {
        // Physical newlines and indentation in TLK files format the dictionary;
        // visible line breaks are expressed explicitly with SakuraScript \n.
        source.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: stateStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(HisuiState(variables: variables)).write(to: stateStoreURL, options: .atomic)
    }

    private func dictionaryURLs(_ master: URL) throws -> [URL] {
        let manager = FileManager.default
        let configured = configuration.dictionaryDirectories + configuration.learningDirectories
        let directories = configured.map { master.appending(path: $0, directoryHint: .isDirectory) }
            .filter { manager.fileExists(atPath: $0.path) }
        return try directories.flatMap { directory in
            try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "tlk" }
        }
    }

    private func loadWordDictionaries(_ master: URL) throws {
        for directory in configuration.dictionaryDirectories + configuration.learningDirectories {
            let root = master.appending(path: directory, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                where url.pathExtension.lowercased() == "mem"
            {
                guard let source = try decodeHisuiText(Data(contentsOf: url)) else { continue }
                parseWordDictionary(source)
            }
        }
    }

    private func parseWordDictionary(_ source: String) {
        var category: String?
        for rawLine in source.components(separatedBy: .newlines) {
            let line = stripLineComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line != "[HISUI DICTIONARY]" else { continue }
            if line.first == "[", line.last == "]" {
                category = String(line.dropFirst().dropLast())
            } else if let category {
                wordCategories[category, default: []].append(line)
            }
        }
    }

    private func replaceWordFunctions(in source: String) -> String {
        var value = source
        for (name, category) in configuration.defaultCategories.sorted(by: { $0.key.count > $1.key.count }) {
            guard let regex = try? NSRegularExpression(
                pattern: "%" + NSRegularExpression.escapedPattern(for: name) + #"(?:\[([^]]*)\])?"#
            ) else { continue }
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let whole = Range(match.range, in: value) else { continue }
                let requested = Range(match.range(at: 1), in: value).map { String(value[$0]) } ?? ""
                value.replaceSubrange(whole, with: randomWord(in: requested.isEmpty ? category : requested) ?? "")
            }
        }
        return value
    }

    private func randomWord(in category: String, visited: Set<String> = []) -> String? {
        guard !visited.contains(category), let candidate = wordCategories[category]?.randomElement() else { return nil }
        if wordCategories[candidate] != nil {
            var visited = visited
            visited.insert(category)
            return randomWord(in: candidate, visited: visited)
        }
        return candidate.split(separator: "\t", maxSplits: 1).first.map(String.init)
    }

    private func wordForTime(category: String, value: Int) -> String? {
        wordCategories[category]?.first { line in
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            return fields.dropFirst().contains { field in
                Int(field) == value || value == 0 && Int(field) == 24
            }
        }.flatMap { $0.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init) }
    }

    private func replaceReferenceFunctions(in source: String, request: ShioriRequest) -> String {
        replacing(pattern: #"%ref(\d+)Byte"#, in: source) { index in
            let value = request.reference(Int(index) ?? 0) ?? ""
            return String(value.lengthOfBytes(using: .shiftJIS))
        }
    }

    private static func loadConfiguration(_ master: URL) -> HisuiConfiguration {
        var configuration = HisuiConfiguration()
        let preferenceURL = master.appending(path: "hisui_preference.def")
        if let data = try? Data(contentsOf: preferenceURL), let source = decodeHisuiText(data) {
            var values: [String: String] = [:]
            for rawLine in source.components(separatedBy: .newlines) {
                let line = stripLineComment(rawLine)
                guard let equals = line.firstIndex(of: "=") else { continue }
                let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                values[key] = unquoteConfigurationValue(value)
            }
            configuration.talkInterval = Int(values["talk_interval"] ?? "") ?? configuration.talkInterval
            configuration.emotionBorder = Int(values["emotion_border"] ?? "") ?? configuration.emotionBorder
            configuration.birthday = values["emotion_ghost_birthday"]
            if let vendor = values["dir_venderdic"], let directory = normalizedDirectory(vendor) {
                configuration.dictionaryDirectories = [directory]
            }
            if let learning = values["dir_lerndic"], let directory = normalizedDirectory(learning) {
                configuration.learningDirectories = [directory]
            }
            for (key, value) in values where key.hasPrefix("dic_") {
                configuration.defaultCategories[String(key.dropFirst(4))] = value
            }
        }

        let url = master.appending(path: "hisuiconf.xml")
        guard let data = try? Data(contentsOf: url), let source = decodeHisuiText(data) else {
            return configuration
        }

        let profile = attributes(of: "GhostProfile", in: source)
        configuration.talkInterval = Int(profile["talk_interval"] ?? "") ?? configuration.talkInterval
        configuration.emotionBorder = Int(profile["emotion_border"] ?? "") ?? configuration.emotionBorder
        configuration.birthday = profile["birthday"]

        if let regex = try? NSRegularExpression(pattern: #"<Directory\s+([^>]+)/?>"#, options: [.caseInsensitive]) {
            var vendor: [String] = []
            var learning: [String] = []
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                let values = parseAttributes(String(source[range]))
                guard let rawName = values["name"], let name = normalizedDirectory(rawName) else { continue }
                if values["type"]?.caseInsensitiveCompare("vender") == .orderedSame {
                    vendor.append(name)
                } else if values["type"]?.caseInsensitiveCompare("learning") == .orderedSame {
                    learning.append(name)
                }
            }
            if !vendor.isEmpty {
                configuration.dictionaryDirectories = vendor
            }
            if !learning.isEmpty {
                configuration.learningDirectories = learning
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"<Define\s+([^>]+)/?>"#, options: [.caseInsensitive]) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                let values = parseAttributes(String(source[range]))
                if let type = values["type"], let category = values["category"] {
                    configuration.defaultCategories[type] = category
                }
            }
        }
        return configuration
    }

    private func loadDescription(_ directory: URL) throws {
        let url = directory.appending(path: "descript.txt")
        guard let source = try LegacyTextDecoder.decode(Data(contentsOf: url)) else { return }
        for line in source.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "sakura.name" {
                selfName = parts[1]
            }
            if parts[0] == "kero.name" {
                keroName = parts[1]
            }
        }
    }
}

private func decodeHisuiText(_ data: Data) -> String? {
    if data.starts(with: [0xFF, 0xFE]) {
        return String(data: data, encoding: .utf16LittleEndian)
    }
    if data.starts(with: [0xFE, 0xFF]) {
        return String(data: data, encoding: .utf16BigEndian)
    }
    return LegacyTextDecoder.decode(data)
}

private func unquoteConfigurationValue(_ source: String) -> String {
    guard source.count >= 2, source.first == "\"", source.last == "\"" else { return source }
    return String(source.dropFirst().dropLast())
}

private func normalizedDirectory(_ source: String) -> String? {
    let value = source.replacingOccurrences(of: "\\", with: "/")
    guard !value.hasPrefix("/"), !value.contains(":") else { return nil }
    let components = value.split(separator: "/", omittingEmptySubsequences: true)
    guard !components.isEmpty, !components.contains("."), !components.contains("..") else { return nil }
    return components.joined(separator: "/")
}

private func attributes(of element: String, in source: String) -> [String: String] {
    guard let regex = try? NSRegularExpression(
        pattern: "<" + NSRegularExpression.escapedPattern(for: element) + #"\s+([^>]+)/?>"#,
        options: [.caseInsensitive]
    ), let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
    let range = Range(match.range(at: 1), in: source)
    else { return [:] }
    return parseAttributes(String(source[range]))
}

private func parseAttributes(_ source: String) -> [String: String] {
    guard let regex = try? NSRegularExpression(
        pattern: #"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[\"']([^\"']*)[\"']"#
    ) else { return [:] }
    return Dictionary(uniqueKeysWithValues: regex.matches(
        in: source,
        range: NSRange(source.startIndex..., in: source)
    ).compactMap { match in
        guard let key = Range(match.range(at: 1), in: source),
              let value = Range(match.range(at: 2), in: source)
        else { return nil }
        return (String(source[key]).lowercased(), String(source[value]))
    })
}

private func replacing(pattern: String, in source: String, transform: (String) -> String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
    var value = source
    for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
        guard let whole = Range(match.range, in: value), let capture = Range(match.range(at: 1), in: value) else { continue }
        value.replaceSubrange(whole, with: transform(String(value[capture])))
    }
    return value
}

private func stripLineComment(_ line: String) -> String {
    var quoted = false
    var index = line.startIndex
    while index < line.endIndex {
        if line[index] == "\"" {
            quoted.toggle()
        } else if !quoted, line[index...].hasPrefix("//") {
            return String(line[..<index])
        }
        index = line.index(after: index)
    }
    return line
}

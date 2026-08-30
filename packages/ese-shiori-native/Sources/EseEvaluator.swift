import Foundation
import UtataneShiori

struct EseEvaluator: Sendable {
    var dictionary: EseDictionary
    var storage: [Int: String] = [:]
    var variables: [String: String] = [:]
    var learnedEntries: [String: [String]] = [:]
    var request: ShioriRequest?
    var recursionDepth = 0
    var talkInterval: Int?
    var talkSeconds = 0
    var otherGhosts: [String] = []
    var selectedGhost: String?
    var reflectedTarget: String?
    var pendingFileWrites: [String: String] = [:]
    var fileContents: [String: String] = [:]

    mutating func response(for request: ShioriRequest) -> String {
        self.request = request
        reflectedTarget = nil
        guard let requestedID = request.id else { return "" }
        if requestedID.caseInsensitiveCompare("otherghostname") == .orderedSame {
            otherGhosts = request.headers.entries.compactMap { header -> (Int, String)? in
                guard header.name.lowercased().hasPrefix("reference"),
                      let index = Int(header.name.dropFirst("Reference".count))
                else { return nil }
                return (index, header.value)
            }.sorted { $0.0 < $1.0 }.map(\.1)
                .map { $0.components(separatedBy: "\u{1}").first ?? $0 }
                .filter { !$0.isEmpty }
            return ""
        }
        var id = requestedID.caseInsensitiveCompare("OnAITalk") == .orderedSame ? "OnRandomTalk" : requestedID
        if id.caseInsensitiveCompare("OnSecondChange") == .orderedSame, request.reference(3) == "1" {
            talkSeconds += 1
            if let talkInterval, talkInterval > 0, talkSeconds >= talkInterval {
                id = "OnRandomTalk"
            }
        }
        if id.caseInsensitiveCompare("OnChoiceSelect") == .orderedSame,
           let target = request.reference(0), target.hasPrefix("#")
        {
            return expand("%" + target.dropFirst())
        }
        let kind: EseRule.Kind = id == "OnCommunicate" ? .response : (id == "version" ? .resource : .event)
        let matchingRules = dictionary.rules.filter { $0.kind == kind && matches($0, id: id) }
        let specificity = matchingRules.map(\.conditions.count).max()
        let rules = matchingRules.filter { $0.conditions.count == specificity }
        guard let rule = rules.randomElement() else { return "" }
        let value = expand(rule.values.joined())
        if !value.isEmpty {
            talkSeconds = 0
        }
        return value
    }

    private func matches(_ rule: EseRule, id: String) -> Bool {
        switch rule.kind {
        case .event:
            guard rule.conditions.first?.caseInsensitiveCompare(id) == .orderedSame else { return false }
            return rule.conditions.dropFirst().allSatisfy(matchHeaderCondition)
        case .response:
            let sentence = request?.reference(0) ?? request?.reference(1) ?? ""
            return rule.conditions.allSatisfy { sentence.localizedCaseInsensitiveContains($0) }
        case .resource:
            return rule.conditions.isEmpty || rule.conditions.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
        }
    }

    private func matchHeaderCondition(_ condition: String) -> Bool {
        guard let colon = condition.firstIndex(of: ":") else { return contextText.contains(condition) }
        let name = String(condition[..<colon]).trimmingCharacters(in: .whitespaces)
        let expected = String(condition[condition.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        let actual = request?.headers[name] ?? ""
        if expected.hasPrefix("%") {
            let marker = expected.dropFirst().prefix { $0.isLetter || $0.isNumber || "._@".contains($0) }
            if !marker.isEmpty, let values = dictionary.entries[String(marker)] {
                return values.contains { Self.weightedValue($0) == actual }
            }
        }
        return actual == expected
    }

    private var contextText: String {
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let fields = ["HOUR=\(String(format: "%02d", now.hour ?? 0))", "MINUTE=\(String(format: "%02d", now.minute ?? 0))", "SECOND=\(String(format: "%02d", now.second ?? 0))", "MODE=0"]
        let headers = request?.headers.entries.map { "\($0.name): \($0.value)" } ?? []
        return (fields + headers).joined(separator: ",")
    }

    mutating func expand(_ source: String) -> String {
        guard recursionDepth < 80 else { return "" }
        recursionDepth += 1
        defer { recursionDepth -= 1 }
        let controlled = evaluateControlFlow(source)
        var result = evaluateFunctions(controlled)
        result = expandVariables(result)
        result = expandEntries(result)
        return result
    }

    private mutating func evaluateControlFlow(_ source: String) -> String {
        var output = "", cursor = source.startIndex
        var frames: [(parent: Bool, matched: Bool, active: Bool)] = []
        func active() -> Bool {
            frames.last?.active ?? true
        }
        while cursor < source.endIndex {
            guard source[cursor] == "$", let call = functionCall(in: source, at: cursor) else {
                if active() {
                    output.append(source[cursor])
                }
                cursor = source.index(after: cursor); continue
            }
            guard ["IF", "_IF", "ELSEIF", "ELSE", "ENDIF", "_ENDIF"].contains(call.name) else {
                if active() {
                    output.append(callFunction(call.name, call.arguments))
                }
                cursor = call.end
                continue
            }
            switch call.name {
            case "IF", "_IF":
                let parent = active(), condition = parent && evaluateCondition(call.arguments.first ?? "")
                frames.append((parent, condition, condition))
            case "ELSEIF":
                if var frame = frames.popLast() {
                    let condition = frame.parent && !frame.matched && evaluateCondition(call.arguments.first ?? "")
                    frame.active = condition; frame.matched = frame.matched || condition; frames.append(frame)
                }
            case "ELSE":
                if var frame = frames.popLast() {
                    frame.active = frame.parent && !frame.matched; frame.matched = true; frames.append(frame)
                }
            default: _ = frames.popLast()
            }
            cursor = call.end
        }
        return output
    }

    private mutating func evaluateFunctions(_ source: String) -> String {
        var result = source, searches = 0
        while searches < 512, let start = result.firstIndex(of: "$"), let call = nextFunctionCall(in: result, from: start) {
            let replacement = callFunction(call.name, call.arguments)
            result.replaceSubrange(call.start ..< call.end, with: replacement)
            searches += 1
        }
        return result
    }

    private mutating func callFunction(_ rawName: String, _ rawArguments: [String]) -> String {
        let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "_")).uppercased()
        let args = rawArguments.map { unquote(evaluateExpression(expand($0)).trimmingCharacters(in: .whitespaces)) }
        var value = ""
        switch name {
        case "PUSH":
            if args.count > 1, let index = Int(args[1]) {
                storage[index] = args[0]
            }
            if args.count > 2, args[2] == "1" {
                value = args[0]
            }
        case "POP", "POPSTR", "POPNUM": value = args.first.flatMap(Int.init).flatMap { storage[$0] } ?? ""
        case "RAND":
            let upper = max(Int(args.first ?? "0") ?? 0, 1), offset = args.dropFirst().first.flatMap(Int.init) ?? 0
            value = String(Int.random(in: 0 ..< upper) + offset)
        case "THROUGH", "GURONGI": value = args.first ?? ""
        case "GETSENTRES":
            let begin = args.first ?? "", end = args.dropFirst().first ?? "[13][10]"
            let requestText = requestLines + contextText
            let headerName = begin.trimmingCharacters(in: .whitespaces).hasSuffix(":")
                ? String(begin.trimmingCharacters(in: .whitespaces).dropLast()) : nil
            let output = args.count < 3 || Int(args[2]) == nil || args.last == "1"
            if let headerName, let found = request?.headers[headerName] {
                if args.count > 2, let index = Int(args[2]) {
                    storage[index] = found
                }
                value = output ? found : ""
            } else if let range = requestText.range(of: begin, options: .caseInsensitive) {
                let tail = requestText[range.upperBound...]
                let terminator = end.replacingOccurrences(of: "[13]", with: "\r").replacingOccurrences(of: "[10]", with: "\n")
                let found = terminator.isEmpty ? String(tail) : (tail.range(of: terminator).map { String(tail[..<$0.lowerBound]) } ?? String(tail))
                if args.count > 2, let index = Int(args[2]) {
                    storage[index] = found
                }
                value = output ? found : ""
            }
        case "GETENTRY":
            let sought = args.first ?? ""
            let key = dictionary.entries.first { $0.value.contains(sought) }?.key ?? sought
            if args.count > 1, let index = Int(args[1]) {
                storage[index] = key
            }
            value = args.last == "1" || args.count < 2 ? key : ""
        case "SETENTRY":
            if args.count > 1, !args[0].isEmpty {
                dictionary.entries[args[0], default: []].append(args[1])
                learnedEntries[args[0], default: []].append(args[1])
            }
        case "DELENTRY":
            if args.count > 1 {
                let key = args[0], sought = args[1]
                if key.isEmpty {
                    for entry in Array(dictionary.entries.keys) {
                        dictionary.entries[entry]?.removeAll { Self.weightedValue($0) == sought }
                        learnedEntries[entry]?.removeAll { Self.weightedValue($0) == sought }
                    }
                } else {
                    dictionary.entries[key]?.removeAll { Self.weightedValue($0) == sought }
                    learnedEntries[key]?.removeAll { Self.weightedValue($0) == sought }
                }
            }
        case "GETPOP":
            if let index = args.first.flatMap(Int.init) {
                value = (args.count > 1 ? args[1] : "") + (storage[index] ?? "") + (args.count > 2 ? args[2] : "")
                if args.last != "1" {
                    value = ""
                }
            }
        case "TALK_INTERVAL": talkInterval = args.first.flatMap(Int.init)
        case "MODE": value = "0"
        case "SELFEVENT":
            if let event = args.first {
                value = "\\![raise,\(event)]"
            }
        case "GETGHOST":
            let sought = args.first ?? ""
            let ghost = sought.isEmpty
                ? otherGhosts.randomElement()
                : otherGhosts.first { $0.localizedCaseInsensitiveContains(sought) }
            selectedGhost = ghost
            if args.count > 1, let index = Int(args[1]) {
                storage[index] = ghost ?? ""
            }
            value = args.count < 3 || args[2] == "1" ? (ghost ?? "") : ""
        case "READNEWS": value = ""
        case "REFLECT":
            reflectedTarget = args.first.flatMap { $0.isEmpty ? nil : $0 } ?? selectedGhost
        case "GETSENTSTR", "GETSENTSTR_LL", "GETSENTSTR_LR", "GETSENTSTR_RL", "GETSENTSTR_RR": value = args.first ?? ""
        case "GETSTRLEFT": value = args.first.map { String($0.prefix(Int(args.dropFirst().first ?? "0") ?? 0)) } ?? ""
        case "GETSTRRIGHT": value = args.first.map { String($0.suffix(Int(args.dropFirst().first ?? "0") ?? 0)) } ?? ""
        case "GETSTRMID":
            if args.count > 2 {
                value = substring(args[0], start: Int(args[1]) ?? 0, length: Int(args[2]) ?? 0)
            }
        case "STRLENGTH": value = String(args.first?.count ?? 0)
        case "READFILE":
            if let filename = args.first {
                let stored = fileContents[filename] ?? ""
                if args.count > 1, let index = Int(args[1]) {
                    storage[index] = stored
                }
                value = args.count < 3 || args[2] == "1" ? stored : ""
            }
        case "WRITEFILEAP":
            if let filename = args.first, let index = args.dropFirst().first.flatMap(Int.init) {
                let appended = (fileContents[filename] ?? "") + (storage[index] ?? "") + "\r\n"
                fileContents[filename] = appended
                pendingFileWrites[filename] = appended
            }
        case "WRITEFILE":
            if let filename = args.first, let index = args.dropFirst().first.flatMap(Int.init) {
                let written = (storage[index] ?? "") + "\r\n"
                fileContents[filename] = written
                pendingFileWrites[filename] = written
            }
        default: break
        }
        return value
    }

    private mutating func expandVariables(_ source: String) -> String {
        var result = source
        let system: [String: String] = [
            "username": variables["username"] ?? "ユーザ", "Username": variables["username"] ?? "ユーザ",
            "selfname": variables["selfname"] ?? "", "keroname": variables["keroname"] ?? "",
            "ref0": request?.reference(0) ?? "", "ref1": request?.reference(1) ?? "",
            "hour": String(Calendar.current.component(.hour, from: Date())),
            "minute": String(Calendar.current.component(.minute, from: Date())),
            "month": String(Calendar.current.component(.month, from: Date())),
            "day": String(Calendar.current.component(.day, from: Date()))
        ]
        for (key, value) in variables.merging(system, uniquingKeysWith: { current, _ in current }) {
            result = result.replacingOccurrences(of: "%%\(key)", with: value)
            result = result.replacingOccurrences(of: "%\(key)", with: value)
        }
        for index in 0 ... 7 {
            result = result.replacingOccurrences(of: "%$ref\(index)", with: request?.reference(index) ?? "", options: .caseInsensitive)
        }
        return result
    }

    private mutating func expandEntries(_ source: String) -> String {
        var result = source, count = 0
        while count < 256, let marker = nextEntryMarker(in: result) {
            let candidates: [String]
            if marker.wildcards > 0 {
                candidates = dictionary.entries.filter { $0.key.hasPrefix(marker.name) && $0.key.count == marker.name.count + marker.wildcards }.flatMap(\.value)
            } else {
                var lookup = marker.name
                while dictionary.entries[lookup] == nil, let dot = lookup.lastIndex(of: ".") {
                    lookup = String(lookup[..<dot])
                }
                candidates = dictionary.entries[lookup] ?? []
            }
            let replacement: String = if let candidate = selectWeighted(candidates) {
                expand(Self.weightedValue(candidate))
            } else {
                ""
            }
            result.replaceSubrange(marker.range, with: replacement)
            count += 1
        }
        return result
    }

    private static func weightedValue(_ value: String) -> String {
        guard let comma = value.firstIndex(of: ","), Int(value[..<comma].trimmingCharacters(in: .whitespaces)) != nil else { return value }
        return String(value[value.index(after: comma)...])
    }

    private func selectWeighted(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        let weighted = values.map { value -> (String, Int) in
            guard let comma = value.firstIndex(of: ","),
                  let weight = Int(value[..<comma].trimmingCharacters(in: .whitespaces))
            else { return (value, 1) }
            return (value, max(0, weight))
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return values.randomElement() }
        var roll = Int.random(in: 0 ..< total)
        for (value, weight) in weighted {
            if roll < weight {
                return value
            }
            roll -= weight
        }
        return weighted.last?.0
    }

    private func nextEntryMarker(in text: String) -> (range: Range<String.Index>, name: String, wildcards: Int)? {
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "%" else { index = text.index(after: index); continue }
            let start = index; index = text.index(after: index)
            if index < text.endIndex, text[index] == "%" {
                index = text.index(after: index); continue
            }
            if index < text.endIndex, text[index] == "!" || text[index] == "#" {
                index = text.index(after: index)
            }
            let nameStart = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber || "._@".contains(text[index]) {
                index = text.index(after: index)
            }
            let name = String(text[nameStart ..< index])
            var stars = 0
            while index < text.endIndex, text[index] == "*" {
                stars += 1; index = text.index(after: index)
            }
            if !name.isEmpty {
                return (start ..< index, name, stars)
            }
        }
        return nil
    }

    private struct Call { let start: String.Index; let end: String.Index; let name: String; let arguments: [String] }
    private func nextFunctionCall(in text: String, from start: String.Index) -> Call? {
        var index = start
        while index < text.endIndex {
            if text[index] == "$", let call = functionCall(in: text, at: index) {
                return call
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func functionCall(in text: String, at start: String.Index) -> Call? {
        var index = text.index(after: start), name = ""
        while index < text.endIndex, text[index].isLetter || text[index] == "_" {
            name.append(text[index]); index = text.index(after: index)
        }
        guard !name.isEmpty, index < text.endIndex, text[index] == "(" else { return nil }
        let contentStart = text.index(after: index); var depth = 1, quoted = false, cursor = contentStart
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\"" {
                quoted.toggle()
            } else if !quoted, character == "(" {
                depth += 1
            } else if !quoted, character == ")" {
                depth -= 1; if depth == 0 {
                    return Call(start: start, end: text.index(after: cursor), name: name.uppercased(), arguments: splitArguments(String(text[contentStart ..< cursor])))
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private func splitArguments(_ text: String) -> [String] {
        var result: [String] = [], current = "", depth = 0, quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle(); current.append(character)
            } else if !quoted, character == "(" {
                depth += 1; current.append(character)
            } else if !quoted, character == ")" {
                depth -= 1; current.append(character)
            } else if !quoted, depth == 0, character == "," {
                result.append(current); current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty || !text.isEmpty {
            result.append(current)
        }
        return result
    }

    private mutating func evaluateCondition(_ raw: String) -> Bool {
        let text = evaluateExpression(raw).trimmingCharacters(in: .whitespaces)
        for op in ["><", "<>", ">=", "=>", "<=", "=<", "=", ">", "<"] where text.contains(op) {
            let parts = text.components(separatedBy: op); guard parts.count >= 2 else { continue }
            let lhs = unquote(parts[0].trimmingCharacters(in: .whitespaces)), rhs = unquote(parts[1].trimmingCharacters(in: .whitespaces))
            if let l = Double(lhs), let r = Double(rhs) {
                switch op { case "><", "<>": return l != r; case ">=", "=>": return l >= r; case "<=", "=<": return l <= r; case "=": return l == r; case ">": return l > r; default: return l < r }
            }
            return ["><", "<>"].contains(op) ? lhs != rhs : op == "=" && lhs == rhs
        }
        return !text.isEmpty && text != "0"
    }

    private var requestLines: String {
        guard let request else { return contextText }
        return request.headers.entries.map { "\($0.name): \($0.value)\r\n" }.joined()
    }

    private mutating func evaluateExpression(_ source: String) -> String {
        var result = expandVariables(source)
        for name in ["POPSTR", "POPNUM", "POP"] {
            let pattern = #"\b"# + name + #"\s*\(\s*(-?\d+)\s*\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
                  let range = Range(match.range, in: result), let indexRange = Range(match.range(at: 1), in: result)
            {
                result.replaceSubrange(range, with: storage[Int(result[indexRange]) ?? 0] ?? "")
            }
        }
        let pieces = splitConcatenation(result)
        return pieces.count > 1 ? pieces.map { unquote($0.trimmingCharacters(in: .whitespaces)) }.joined() : result
    }

    private func splitConcatenation(_ text: String) -> [String] {
        var result: [String] = [], current = "", quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle(); current.append(character)
            } else if character == "~", !quoted {
                result.append(current); current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    private func unquote(_ text: String) -> String {
        text.count >= 2 && text.first == "\"" && text.last == "\"" ? String(text.dropFirst().dropLast()) : text
    }

    private func substring(_ text: String, start: Int, length: Int) -> String {
        let lower = text.index(text.startIndex, offsetBy: max(0, start), limitedBy: text.endIndex) ?? text.endIndex; return String(text[lower...].prefix(max(0, length)))
    }
}

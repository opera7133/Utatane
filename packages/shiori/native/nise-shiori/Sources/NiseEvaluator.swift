import Foundation
import UtataneShiori

struct NisePersistedState: Codable, Sendable {
    var username = ""
    var variables: [String: String] = [:]
    var learnedWords: [String: [String]] = [:]
    var talkInterval = 180
    var newsIndex = 0
}

struct NiseEvaluator: Sendable {
    var dictionary: NiseDictionary
    var state: NisePersistedState
    var talkCount = 0
    var surface0 = 0
    var surface1 = 10
    var moveCount = 0
    var mikireCount = 0
    var kasanariCount = 0
    var otherGhosts: [String] = []
    var communicateTarget: String?
    let selfName: String
    let keroName: String

    mutating func response(for request: ShioriRequest, now: Date = Date()) -> String? {
        guard let id = request.id else { return nil }
        if let resource = dictionary.resources[id] {
            return expand(resource, request: request, now: now)
        }
        switch id.lowercased() {
        case "onaitalk":
            return randomTalk(request: request, now: now)
        case "otherghostname":
            otherGhosts = (0 ... 127).compactMap { request.reference($0)?.components(separatedBy: "\u{1}").first }.filter { !$0.isEmpty }
            return nil
        case "onsecondchange":
            return secondChange(request: request, now: now)
        case "onsurfacechange":
            surface0 = Int(request.reference(0) ?? "") ?? surface0
            surface1 = Int(request.reference(1) ?? "") ?? surface1
        case "onmousemove":
            moveCount += 5
        case "onuserinput":
            if ["niseshiori.username", "ninix.niseshiori.username"].contains(request.reference(0)?.lowercased() ?? "") {
                state.username = request.reference(1) ?? ""
                return "\\e"
            }
        case "oncommunicate":
            return communicate(request: request, now: now)
        default:
            break
        }
        return event(id, request: request, now: now)
    }

    private mutating func secondChange(request: ShioriRequest, now: Date) -> String? {
        let isMikire = request.reference(1) == "1"
        let isKasanari = request.reference(2) == "1"
        if isMikire {
            mikireCount += 1
            if mikireCount == 1, let script = event("OnNSMikireHappen", request: request, now: now) {
                return script
            }
        } else if mikireCount > 0 {
            mikireCount = 0
            if let script = event("OnNSMikireSolve", request: request, now: now) {
                return script
            }
        }
        if isKasanari {
            kasanariCount += 1
            if kasanariCount == 1, let script = event("OnNSKasanariHappen", request: request, now: now) {
                return script
            }
        } else if kasanariCount > 0 {
            kasanariCount = 0
            if let script = event("OnNSKasanariSolve", request: request, now: now) {
                return script
            }
        }
        if let explicit = event("OnSecondChange", request: request, now: now) {
            return explicit
        }
        guard state.talkInterval > 0 else { return nil }
        talkCount += 1
        guard talkCount >= state.talkInterval else { return nil }
        talkCount = 0
        return randomTalk(request: request, now: now)
    }

    private mutating func randomTalk(request: ShioriRequest, now: Date) -> String? {
        event("OnNSRandomTalk", request: request, now: now)
            ?? select(dictionary.words["\\e"]).map { expand($0, request: request, now: now) }
    }

    private mutating func communicate(request: ShioriRequest, now: Date) -> String? {
        let sender = request.reference(0) ?? ""
        let message = request.reference(1) ?? ""
        let candidates = dictionary.responses.filter {
            matches($0.condition, event: "", references: [message], request: request, now: now)
        }
        guard let selected = mostSpecific(candidates) else { return nil }
        communicateTarget = sender
        return expand(selected.script, request: request, now: now, sender: sender)
    }

    private mutating func event(_ id: String, request: ShioriRequest, now: Date) -> String? {
        let references = (0 ... 7).map { request.reference($0) ?? "" }
        let candidates = dictionary.events.filter {
            matches($0.condition, event: id, references: references, request: request, now: now)
        }
        guard let selected = mostSpecific(candidates) else { return nil }
        talkCount = 0
        return expand(selected.script, request: request, now: now)
    }

    private func mostSpecific(_ candidates: [NiseConditionalScript]) -> NiseConditionalScript? {
        let maximum = candidates.map(\.condition.terms.count).max()
        return candidates.first { $0.condition.terms.count == maximum }
    }

    private func matches(
        _ condition: NiseCondition,
        event: String,
        references: [String],
        request: ShioriRequest,
        now: Date
    ) -> Bool {
        condition.terms.allSatisfy { term in
            switch term {
            case let .contains(value):
                return value.isEmpty || event.contains(value) || references.contains { $0.contains(value) }
            case let .comparison(lhs, operation, rhs):
                let left = metaValue(lhs, request: request, now: now)
                let right = metaValue(rhs, request: request, now: now)
                if let leftNumber = Int(left), let rightNumber = Int(right) {
                    return compare(leftNumber, rightNumber, operation: operation)
                }
                return compare(left, right, operation: operation)
            }
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T, operation: String) -> Bool {
        switch operation {
        case "=": lhs == rhs
        case "<>": lhs != rhs
        case ">": lhs > rhs
        case "<": lhs < rhs
        case ">=": lhs >= rhs
        case "<=": lhs <= rhs
        default: false
        }
    }

    private mutating func expand(
        _ source: String,
        request: ShioriRequest,
        now: Date,
        sender: String = ""
    ) -> String {
        var result = replaceMetas(in: source, request: request, now: now, sender: sender)
        var iterations = 0
        while let range = result.range(of: #"\\(?:ns_(?:st(?:\[[0-9]+\])?|cr|hl|ce|tc\[[^\]]+\]|tn(?:\[[^\]]*\])?|jp\[[^\]]+\]|rf\[[^\]]*\]|rt|nw|nr)|set\[[^\]]+\])"#, options: .regularExpression), iterations < 64 {
            let tag = String(result[range])
            let replacement = evaluateTag(tag, request: request, now: now)
            result.replaceSubrange(range, with: replacement)
            iterations += 1
        }
        return result
    }

    private mutating func replaceMetas(in source: String, request: ShioriRequest, now: Date, sender: String) -> String {
        let pattern = #"%(?:rand(?:[1-9]|\[[0-9]+\])|selfname2?|sakuraname|keroname|username|friendname|year|month|day|hour|minute|second|week|ghostname|sender|ref[0-7]|surf[01]|word|ns_st|get\[[^\]]+\]|jpentry|plathome|platform|move|mikire|kasanari|ver|(?:dms|m[szlchtep?]|[dk])(?:\[[^\]]*\])?[2-9]?|\[[^\]]*\][2-9]?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        var result = source
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed()
        var chosenWords: [String: String] = [:]
        for match in matches {
            guard let range = Range(match.range, in: source) else { continue }
            let meta = String(source[range])
            let key = meta.replacingOccurrences(of: #"[2-9]$"#, with: "", options: .regularExpression)
            let value: String
            if Self.isWordMeta(meta) {
                if let existing = chosenWords[meta] {
                    value = existing
                } else {
                    let dictionaryKey = key == "%m?"
                        ? ["\\ms", "\\mz", "\\ml", "\\mc", "\\mh", "\\mt", "\\me", "\\mp"].randomElement()!
                        : "\\" + String(key.dropFirst())
                    let chained = dictionary.typeChains[dictionaryKey]?
                        .filter { source.contains($0.keyword) }
                        .map(\.word)
                    value = select(chained?.isEmpty == false ? chained : dictionary.words[dictionaryKey]) ?? ""
                    chosenWords[meta] = value
                }
            } else {
                value = metaValue(meta, request: request, now: now, sender: sender)
            }
            if let resultRange = Range(match.range, in: result) {
                result.replaceSubrange(resultRange, with: value)
            }
        }
        return result
    }

    private static func isWordMeta(_ value: String) -> Bool {
        value.range(of: #"^%(?:dms|m[szlchtep?]|[dk]|\[)"#, options: .regularExpression) != nil
    }

    private func metaValue(_ name: String, request: ShioriRequest, now: Date, sender: String = "") -> String {
        if name.hasPrefix("%get["), name.hasSuffix("]") {
            return state.variables[String(name.dropFirst(5).dropLast())] ?? "?"
        }
        if name.hasPrefix("%rand["), name.hasSuffix("]"), let maximum = Int(name.dropFirst(6).dropLast()), maximum > 0 {
            return String(Int.random(in: 1 ... maximum))
        }
        if name.range(of: #"^%rand[1-9]$"#, options: .regularExpression) != nil, let digits = Int(name.suffix(1)) {
            let minimum = digits == 1 ? 0 : Self.power10(digits - 1)
            return String(Int.random(in: minimum ..< Self.power10(digits)))
        }
        if name.hasPrefix("%ref"), let index = Int(name.dropFirst(4)) {
            return request.reference(index) ?? ""
        }
        let calendar = Calendar(identifier: .gregorian)
        return switch name {
        case "%selfname", "%selfname2", "%sakuraname": selfName
        case "%keroname", "%friendname": keroName
        case "%username": state.username
        case "%year": String(calendar.component(.year, from: now))
        case "%month": String(calendar.component(.month, from: now))
        case "%day": String(calendar.component(.day, from: now))
        case "%hour": String(calendar.component(.hour, from: now))
        case "%minute": String(calendar.component(.minute, from: now))
        case "%second": String(calendar.component(.second, from: now))
        case "%week": ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][calendar.component(.weekday, from: now) - 1]
        case "%ghostname": otherGhosts.first ?? ""
        case "%sender": sender
        case "%surf0": String(surface0)
        case "%surf1": String(surface1)
        case "%word": request.reference(0) ?? ""
        case "%ns_st": String(state.talkInterval)
        case "%platform", "%plathome": "Utatane"
        case "%move": String(moveCount)
        case "%mikire": String(mikireCount)
        case "%kasanari": String(kasanariCount)
        case "%ver": "偽栞 compatible for Utatane"
        default: name
        }
    }

    private mutating func evaluateTag(_ tag: String, request: ShioriRequest, now: Date) -> String {
        switch tag {
        case "\\ns_cr": talkCount = 0
        case "\\ns_ce": communicateTarget = nil
        case "\\ns_hl": communicateTarget = otherGhosts.first
        case "\\ns_tn": return "\\![open,inputbox,niseshiori.username,-1]"
        case "\\ns_rt": return "\\a"
        case "\\ns_nw": return nextNews(request: request, now: now) ?? ""
        case "\\ns_nr": state.newsIndex = 0
        default:
            if tag.hasPrefix("\\ns_st["), let number = Int(tag.dropFirst(7).dropLast()) {
                state.talkInterval = switch number { case 0: 0; case 1: 420; case 2: 180; case 3: 60; default: min(max(number, 4), 999) }
                talkCount = 0
            } else if tag.hasPrefix("\\ns_tn[") {
                state.username = String(tag.dropFirst(7).dropLast())
            } else if tag.hasPrefix("\\ns_tc[") {
                let type = "\\" + String(tag.dropFirst(7).dropLast())
                let word = request.reference(0) ?? ""
                if !word.isEmpty {
                    state.learnedWords[type, default: []].append(word)
                    dictionary.words[type, default: []].append(word)
                }
            } else if tag.hasPrefix("\\ns_jp[") {
                var jumpRequest = request
                jumpRequest.headers.append(name: "Reference0", value: String(tag.dropFirst(7).dropLast()))
                return event("OnNSJumpEntry", request: jumpRequest, now: now) ?? ""
            } else if tag.hasPrefix("\\set[") {
                let statement = String(tag.dropFirst(5).dropLast())
                if let separator = statement.firstIndex(of: "=") {
                    let name = statement[..<separator].trimmingCharacters(in: .whitespaces)
                    let expression = String(statement[statement.index(after: separator)...])
                    let snapshot = self
                    state.variables[name] = NiseExpression.evaluate(expression) { token in
                        if token.hasPrefix("%") {
                            return snapshot.metaValue(token, request: request, now: now)
                        }
                        return snapshot.state.variables[token] ?? "?"
                    }
                }
            }
        }
        return ""
    }

    private mutating func nextNews(request: ShioriRequest, now: Date) -> String? {
        guard state.newsIndex < dictionary.news.count else { return nil }
        defer { state.newsIndex += 1 }
        return expand(dictionary.news[state.newsIndex], request: request, now: now)
    }

    private func select<T>(_ values: [T]?) -> T? {
        values?.randomElement()
    }

    private static func power10(_ exponent: Int) -> Int {
        (0 ..< exponent).reduce(1) { value, _ in value * 10 }
    }
}

private enum NiseExpression {
    static func evaluate(_ source: String, resolve: @escaping (String) -> String) -> String {
        var parser = Parser(source: source, resolve: resolve)
        return parser.parseExpression()
    }

    private struct Parser {
        let tokens: [String]
        let resolve: (String) -> String
        var index = 0

        init(source: String, resolve: @escaping (String) -> String) {
            self.resolve = resolve
            var tokens: [String] = []
            var current = ""
            for character in source where !character.isWhitespace {
                if "()+-*/\\".contains(character) {
                    if !current.isEmpty {
                        tokens.append(current); current = ""
                    }
                    tokens.append(String(character))
                } else {
                    current.append(character)
                }
            }
            if !current.isEmpty {
                tokens.append(current)
            }
            self.tokens = tokens
        }

        mutating func parseExpression() -> String {
            var value = parseTerm()
            while let operation = peek(), ["+", "-"].contains(operation) {
                index += 1
                value = apply(value, parseTerm(), operation)
            }
            return value
        }

        private mutating func parseTerm() -> String {
            var value = parsePrimary()
            while let operation = peek(), ["*", "/", "\\"].contains(operation) {
                index += 1
                value = apply(value, parsePrimary(), operation)
            }
            return value
        }

        private mutating func parsePrimary() -> String {
            guard let token = peek() else { return "?" }
            index += 1
            if token == "(" {
                let value = parseExpression()
                if peek() == ")" {
                    index += 1
                }
                return value
            }
            if ["+", "-"].contains(token) {
                let value = parsePrimary()
                guard token == "-", let number = Int(value) else { return value }
                return String(-number)
            }
            return Int(token).map(String.init) ?? resolve(token)
        }

        private func peek() -> String? {
            index < tokens.count ? tokens[index] : nil
        }

        private func apply(_ lhs: String, _ rhs: String, _ operation: String) -> String {
            guard let left = Int(lhs), let right = Int(rhs) else { return lhs + operation + rhs }
            return switch operation {
            case "+": String(left + right)
            case "-": String(left - right)
            case "*": String(left * right)
            case "/": right == 0 ? lhs + operation + rhs : String(left / right)
            case "\\": right == 0 ? lhs + operation + rhs : String(left % right)
            default: lhs
            }
        }
    }
}

import Foundation
import UtataneCore
import UtataneNativeSaori
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

private struct ShinoEntry: Sendable {
    let condition: String?
    let values: [String]
}

private struct ShinoState: Codable, Sendable {
    var variables: [String: String] = [:]
}

public final class NativeShinoPersonalityEngine: PersonalityEngine, @unchecked Sendable {
    private let adapter = GhostEventShioriAdapter()
    private let stateStoreURL: URL
    private let saoriCaller: any NativeSaoriCalling
    private var events: [String: [ShinoEntry]] = [:]
    private var jumps: [String: [ShinoEntry]] = [:]
    private var resources: [String: [ShinoEntry]] = [:]
    private var functions: [String: [ShinoEntry]] = [:]
    private var words: [String: [String]] = [:]
    private var state: ShinoState
    private var selfName = ""
    private var keroName = ""
    private let startedAt = Date()
    private var lastSaoriValues: [String] = []
    public private(set) var loadedDictionaryFileCount = 0

    public var loadedEventEntryCount: Int {
        events.values.reduce(0) { $0 + $1.count }
    }

    public var loadedJumpEntryCount: Int {
        jumps.values.reduce(0) { $0 + $1.count }
    }

    public init(
        masterDirectoryURL: URL,
        stateStoreURL: URL? = nil,
        saoriCaller: (any NativeSaoriCalling)? = nil
    ) throws {
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "shino-state.json")
        self.saoriCaller = saoriCaller ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        state = (try? Data(contentsOf: self.stateStoreURL)).flatMap {
            try? JSONDecoder().decode(ShinoState.self, from: $0)
        } ?? ShinoState()
        try loadDescription(masterDirectoryURL)
        try loadInitialVariables(masterDirectoryURL)
        try loadDictionaries(masterDirectoryURL)
    }

    public static func supports(shioriFilename: String?) -> Bool {
        shioriFilename?.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?
            .caseInsensitiveCompare("shino.dll") == .orderedSame
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        let request = adapter.request(for: event)
        let requestID = request.id ?? ""
        let key = requestID.caseInsensitiveCompare("OnChoiceSelect") == .orderedSame
            ? request.reference(0) ?? requestID : requestID
        let source = requestID.caseInsensitiveCompare("OnChoiceSelect") == .orderedSame ? jumps : events
        guard let value = evaluate(entries: lookup(key, in: source), request: request, depth: 0) else {
            return fallbackScript(for: requestID)
        }
        try save()
        return value.isEmpty ? nil : SakuraScript(rawValue: value)
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let request = adapter.request(for: event)
        let requestID = request.id ?? ""
        if let value = evaluate(entries: lookup(requestID, in: resources), request: request, depth: 0) {
            return PersonalityResponse(script: value.isEmpty ? nil : SakuraScript(rawValue: value))
        }
        return try await PersonalityResponse(script: handle(event: event))
    }

    public func shutdown() async {
        try? save()
    }

    private func fallbackScript(for requestID: String) -> SakuraScript? {
        switch requestID.lowercased() {
        case "onboot", "onwindowstaterestore":
            SakuraScript(rawValue: #"\1\s[10]\0\s[0]\e"#)
        case "onclose", "onmauprequireclose":
            SakuraScript(rawValue: #"\-\e"#)
        default:
            nil
        }
    }

    private func lookup(_ key: String, in table: [String: [ShinoEntry]]) -> [ShinoEntry] {
        table.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value ?? []
    }

    private func evaluate(entries: [ShinoEntry], request: ShioriRequest, depth: Int) -> String? {
        guard depth < 32 else { return nil }
        let matching = entries.filter { $0.condition.map { condition($0, request: request) } ?? true }
        let conditional = matching.filter { $0.condition != nil }
        let candidates: [ShinoEntry] = if conditional.isEmpty {
            matching
        } else {
            conditional.filter { entry in
                entry.condition?.count == conditional.compactMap { $0.condition?.count }.max()
            }
        }
        guard let entry = candidates.randomElement(),
              let raw = entry.values.randomElement()
        else { return nil }
        return expand(raw, request: request, depth: depth)
    }

    private func expand(_ raw: String, request: ShioriRequest, depth: Int) -> String {
        guard depth < 32 else { return "" }
        var output = raw
        let assignment = try? NSRegularExpression(pattern: #"\{\s*\$(?:\{([^}]+)\}|([^\s=+*/%^-]+))\s*(=|\+=|-=|\*=|/=|%=|\^=)\s*(.+)\}"#)
        if let assignment {
            for match in assignment.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed() {
                guard let nameRange = Range(match.range(at: match.range(at: 1).location != NSNotFound ? 1 : 2), in: output),
                      let operatorRange = Range(match.range(at: 3), in: output),
                      let valueRange = Range(match.range(at: 4), in: output),
                      let whole = Range(match.range, in: output) else { continue }
                let name = String(output[nameRange])
                let operation = String(output[operatorRange])
                let rhs = scalar(String(output[valueRange]), request: request)
                state.variables[name] = assignedValue(current: state.variables[name] ?? "0", operation: operation, rhs: rhs)
                output.removeSubrange(whole)
            }
        }
        output = replaceCalls(in: output, prefix: #"\s_jmp["#) { target in
            evaluate(entries: lookup(target, in: jumps), request: request, depth: depth + 1) ?? ""
        }
        output = replaceCalls(in: output, prefix: #"\s_sub["#) { target in
            evaluate(entries: lookup(target, in: jumps), request: request, depth: depth + 1) ?? ""
        }
        output = replaceCalls(in: output, prefix: #"\s_set_talk["#) { seconds in
            state.variables["talk"] = scalar(seconds, request: request)
            return ""
        }
        if output.contains(#"\s_randomtalk"#) {
            let talk = evaluate(entries: lookup("OnAITalk", in: events), request: request, depth: depth + 1) ?? ""
            output = output.replacingOccurrences(of: #"\s_randomtalk"#, with: talk)
        }
        output = replaceCalls(in: output, prefix: "%init[") { arguments in
            let values = arguments.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return "\\1\\s[\(values.count > 1 ? values[1] : "10")]\\0\\s[\(values.first ?? "0")]"
        }
        output = replaceCalls(in: output, prefix: "%randsel[") { arguments in
            splitArguments(arguments).randomElement() ?? ""
        }
        output = replaceCalls(in: output, prefix: "%if[") { arguments in
            let values = splitArguments(arguments)
            guard !values.isEmpty else { return "" }
            if condition(values[0], request: request) {
                return values.count > 1 ? values[1] : ""
            }
            return values.count > 2 ? values[2] : ""
        }
        output = replaceCalls(in: output, prefix: "%sel[") { arguments in
            let values = splitArguments(arguments)
            var index = 0
            while index + 1 < values.count {
                if condition(values[index], request: request) {
                    return values[index + 1]
                }
                index += 2
            }
            return index < values.count ? values[index] : ""
        }
        output = replaceCalls(in: output, prefix: "%for[") { arguments in
            let values = splitArguments(arguments)
            guard values.count > 3 else { return "" }
            _ = expand("{\(values[0])}", request: request, depth: depth + 1)
            var result = ""
            for _ in 0 ..< 1024 {
                guard condition(values[1], request: request) else { break }
                result += expand(values[3], request: request, depth: depth + 1)
                _ = expand("{\(values[2])}", request: request, depth: depth + 1)
            }
            return result
        }
        output = expandFunctions(in: output, request: request, depth: depth)
        output = replacePattern(#"%\{([^}]+)\}"#, in: output) { name in
            if ["year", "month", "week", "day", "hour", "minute", "second"].contains(name) {
                return "%{\(name)}"
            }
            return pickWord(name, request: request, depth: depth)
        }
        for index in 0 ... 31 {
            if let value = request.reference(index) {
                output = output.replacingOccurrences(of: "%ref\(index)", with: value)
            }
        }
        let now = Calendar.current.dateComponents([.year, .month, .weekday, .day, .hour, .minute, .second], from: Date())
        let system: [String: String] = [
            "selfname": selfName, "keroname": keroName,
            "username": state.variables["username"] ?? "ユーザ",
            "year": String(now.year ?? 0), "month": String(now.month ?? 0),
            "week": String((now.weekday ?? 1) - 1), "day": String(now.day ?? 0),
            "hour": String(now.hour ?? 0), "minute": String(now.minute ?? 0), "second": String(now.second ?? 0),
            "talk": state.variables["talk"] ?? "0",
            "exh": numericString(Date().timeIntervalSince(startedAt) / 3600),
            "et": elapsedTimeString(),
            "siover": "0.8.0-native", "ver": "忍 0.8.0-compatible (Utatane)",
            "matver": "0", "plathome": "ssp.exe", "ghostname": ""
        ]
        for (name, value) in system.sorted(by: { $0.key.count > $1.key.count }) {
            output = output.replacingOccurrences(of: "%{\(name)}", with: value)
            output = output.replacingOccurrences(of: "%\(name)", with: value)
        }
        for (name, value) in state.variables.sorted(by: { $0.key.count > $1.key.count }) {
            output = output.replacingOccurrences(of: "${\(name)}", with: value)
            output = output.replacingOccurrences(of: "$\(name)", with: value)
        }
        var selectedWords: [String: [Int: String]] = [:]
        for kind in ["dms", "ms", "mz", "ml", "mc", "mh", "mt", "me", "mp", "m", "d", "k"] {
            output = replaceCalls(in: output, prefix: "%\(kind)[") { arguments in
                let values = splitArguments(arguments)
                let category = values.first ?? ""
                let ordinal = values.count > 1 ? (Int(values[1]) ?? 1) : 1
                return selectedWord(
                    kind: kind,
                    category: category,
                    ordinal: ordinal,
                    selectedWords: &selectedWords,
                    request: request,
                    depth: depth
                )
            }
            output = replacePattern("%\(kind)([0-9]+)", in: output) { ordinal in
                selectedWord(
                    kind: kind,
                    category: "",
                    ordinal: Int(ordinal) ?? 1,
                    selectedWords: &selectedWords,
                    request: request,
                    depth: depth
                )
            }
            output = replacePattern("%\(kind)(?![A-Za-z0-9_])", in: output) { _ in
                selectedWord(
                    kind: kind,
                    category: "",
                    ordinal: 1,
                    selectedWords: &selectedWords,
                    request: request,
                    depth: depth
                )
            }
        }
        output = replacePattern(#"\{([^{}]+)\}"#, in: output) { expression in
            let expanded = scalar(expression, request: request)
            return evaluateArithmetic(expanded).map(numericString) ?? expanded
        }
        return output
    }

    private func expandFunctions(in source: String, request: ShioriRequest, depth: Int) -> String {
        var output = source
        output = replaceCalls(in: output, prefix: "%rand[") { argument in
            guard let upper = Int(scalar(argument, request: request)), upper > 0 else { return "0" }
            return String(Int.random(in: 0 ..< upper))
        }
        output = replaceCalls(in: output, prefix: "%len[") { String(shiftJISData(scalar($0, request: request)).count) }
        output = replaceCalls(in: output, prefix: "%left[") { arguments in
            let values = splitArguments(arguments)
            guard values.count > 1 else { return "" }
            return shiftJISSubstring(
                scalar(values[0], request: request),
                offset: 0,
                count: Int(scalar(values[1], request: request)) ?? 0
            )
        }
        output = replaceCalls(in: output, prefix: "%right[") { arguments in
            let values = splitArguments(arguments)
            guard values.count > 1 else { return "" }
            let data = shiftJISData(scalar(values[0], request: request))
            let count = max(0, Int(scalar(values[1], request: request)) ?? 0)
            return String(data: data.suffix(count), encoding: .shiftJIS) ?? ""
        }
        output = replaceCalls(in: output, prefix: "%substr[") { arguments in
            let values = splitArguments(arguments)
            guard values.count > 2 else { return "" }
            let start = max(0, Int(scalar(values[1], request: request)) ?? 0)
            let count = max(0, Int(scalar(values[2], request: request)) ?? 0)
            return shiftJISSubstring(scalar(values[0], request: request), offset: start, count: count)
        }
        output = replaceCalls(in: output, prefix: "%trim[") { scalar($0, request: request).trimmingCharacters(in: .whitespacesAndNewlines) }
        output = replaceCalls(in: output, prefix: "%replace[") { arguments in
            let values = splitArguments(arguments)
            guard values.count > 2 else { return "" }
            return scalar(values[0], request: request).replacingOccurrences(
                of: scalar(values[1], request: request),
                with: scalar(values[2], request: request)
            )
        }
        output = replaceCalls(in: output, prefix: "%instr[") { arguments in
            let values = splitArguments(arguments)
            guard values.count > 1 else { return "-1" }
            let source = shiftJISData(scalar(values[0], request: request))
            let needle = shiftJISData(scalar(values[1], request: request))
            guard let range = source.range(of: needle) else { return "-1" }
            return String(source.distance(from: source.startIndex, to: range.lowerBound))
        }
        output = replaceCalls(in: output, prefix: "%toupper[") { scalar($0, request: request).uppercased() }
        output = replaceCalls(in: output, prefix: "%tolower[") { scalar($0, request: request).lowercased() }
        output = replaceCalls(in: output, prefix: "%tozenkaku[") {
            scalar($0, request: request).applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? scalar($0, request: request)
        }
        output = replaceCalls(in: output, prefix: "%tohankaku[") {
            scalar($0, request: request).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? scalar($0, request: request)
        }
        output = replaceCalls(in: output, prefix: "%asc[") { argument in
            scalar(argument, request: request).unicodeScalars.first.map { String($0.value) } ?? "0"
        }
        output = replaceCalls(in: output, prefix: "%chr[") { argument in
            UnicodeScalar(Int(scalar(argument, request: request)) ?? 0).map(String.init) ?? ""
        }
        output = replaceCalls(in: output, prefix: "%isalpha[") { scalar($0, request: request).allSatisfy(\.isLetter) ? "1" : "0" }
        output = replaceCalls(in: output, prefix: "%isupper[") {
            let value = scalar($0, request: request)
            return !value.isEmpty && value.allSatisfy { !$0.isLetter || $0.isUppercase } ? "1" : "0"
        }
        output = replaceCalls(in: output, prefix: "%islower[") {
            let value = scalar($0, request: request)
            return !value.isEmpty && value.allSatisfy { !$0.isLetter || $0.isLowercase } ? "1" : "0"
        }
        output = replaceCalls(in: output, prefix: "%isnumber[") { scalar($0, request: request).allSatisfy(\.isNumber) ? "1" : "0" }
        output = replaceCalls(in: output, prefix: "%isalnum[") { scalar($0, request: request).allSatisfy { $0.isLetter || $0.isNumber } ? "1" : "0" }
        output = replaceCalls(in: output, prefix: "%isinteger[") { Int(scalar($0, request: request)) != nil ? "1" : "0" }
        output = replaceCalls(in: output, prefix: "%isdecimal[") { Double(scalar($0, request: request)) != nil ? "1" : "0" }
        output = replaceCalls(in: output, prefix: "%abs[") { numericString(abs(evaluateArithmetic(scalar($0, request: request)) ?? 0)) }
        output = replaceCalls(in: output, prefix: "%ceil[") { numericString(ceil(evaluateArithmetic(scalar($0, request: request)) ?? 0)) }
        output = replaceCalls(in: output, prefix: "%floor[") { numericString(floor(evaluateArithmetic(scalar($0, request: request)) ?? 0)) }
        output = replaceCalls(in: output, prefix: "%round[") { numericString((evaluateArithmetic(scalar($0, request: request)) ?? 0).rounded()) }
        output = replaceCalls(in: output, prefix: "%argv[") { request.reference(Int(scalar($0, request: request)) ?? -1) ?? "" }
        let argumentCount = (0 ... 31).prefix { request.reference($0) != nil }.count
        output = output.replacingOccurrences(of: "%argc", with: String(argumentCount))
        output = replaceCalls(in: output, prefix: "%val[") { numericString(evaluateArithmetic(scalar($0, request: request)) ?? 0) }
        output = replaceCalls(in: output, prefix: "%sizeformat[") { argument in
            sizeFormatted(Int64(evaluateArithmetic(scalar(argument, request: request)) ?? 0))
        }
        output = replaceCalls(in: output, prefix: "%saori[") { arguments in
            let values = splitArguments(arguments).map { scalar($0, request: request) }
            guard let module = values.first, !module.isEmpty else {
                lastSaoriValues = []
                return ""
            }
            saoriCaller.load(module)
            lastSaoriValues = saoriCaller.call(module, arguments: Array(values.dropFirst()))
                .split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
            return lastSaoriValues.first ?? ""
        }
        output = replaceCalls(in: output, prefix: "%saoriresult[") { argument in
            let index = Int(scalar(argument, request: request)) ?? 0
            return lastSaoriValues.indices.contains(index) ? lastSaoriValues[index] : ""
        }
        for (name, entries) in functions {
            output = replaceCalls(in: output, prefix: "%\(name)[") { arguments in
                var functionRequest = ShioriRequest(
                    method: request.method,
                    version: request.version,
                    headers: ShioriHeaders(request.headers.entries.filter {
                        !$0.name.lowercased().hasPrefix("reference")
                    })
                )
                for (index, argument) in splitArguments(arguments).enumerated() {
                    functionRequest.headers.append(name: "Reference\(index)", value: scalar(argument, request: request))
                }
                return evaluate(entries: entries, request: functionRequest, depth: depth + 1) ?? ""
            }
            output = replacePattern("%\(NSRegularExpression.escapedPattern(for: name))(?![A-Za-z0-9_])", in: output) { _ in
                evaluate(entries: entries, request: request, depth: depth + 1) ?? ""
            }
        }
        return output
    }

    private func pickWord(_ name: String, request: ShioriRequest, depth: Int) -> String {
        guard let value = words[name]?.randomElement() else { return "" }
        return expand(value, request: request, depth: depth + 1)
    }

    private func selectedWord(
        kind: String,
        category: String,
        ordinal: Int,
        selectedWords: inout [String: [Int: String]],
        request: ShioriRequest,
        depth: Int
    ) -> String {
        let key = kind + category
        let index = max(1, ordinal)
        if let selected = selectedWords[key]?[index] {
            return selected
        }
        let candidates: [String]
        if kind == "m", words[key] == nil {
            let nounPrefixes = ["ms", "mz", "ml", "mc", "mh", "mt", "me", "mp"]
            candidates = words.flatMap { name, values in
                nounPrefixes.contains(where: name.hasPrefix) ? values : []
            }
        } else {
            candidates = words[key] ?? []
        }
        guard let raw = candidates.randomElement() else { return "" }
        let value = expand(raw, request: request, depth: depth + 1)
        selectedWords[key, default: [:]][index] = value
        return value
    }

    private func elapsedTimeString() -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func condition(_ source: String, request: ShioriRequest) -> Bool {
        let expanded = scalar(source, request: request)
        return booleanValue(
            expanded
                .replacingOccurrences(of: "<>", with: "!=")
                .replacingOccurrences(of: "=>", with: ">=")
                .replacingOccurrences(of: "=<", with: "<=")
        )
    }

    private func scalar(_ source: String, request: ShioriRequest) -> String {
        var value = source.trimmingCharacters(in: .whitespaces)
        for index in 0 ... 31 {
            if let reference = request.reference(index) {
                value = value.replacingOccurrences(of: "%ref\(index)", with: reference)
            }
        }
        let now = Calendar.current.dateComponents([.hour, .minute, .second, .day, .month, .year], from: Date())
        for (name, number) in ["hour": now.hour, "minute": now.minute, "second": now.second, "day": now.day, "month": now.month, "year": now.year] {
            value = value.replacingOccurrences(of: "%{\(name)}", with: String(number ?? 0))
            value = value.replacingOccurrences(of: "%\(name)", with: String(number ?? 0))
        }
        for (name, stored) in state.variables {
            value = value.replacingOccurrences(of: "${\(name)}", with: stored); value = value.replacingOccurrences(of: "$\(name)", with: stored)
        }
        value = expandFunctions(in: value, request: request, depth: 0)
        return evaluateArithmetic(value).map(numericString) ?? value.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }

    private func assignedValue(current: String, operation: String, rhs: String) -> String {
        if operation == "=" {
            return evaluateArithmetic(rhs).map(numericString) ?? rhs
        }
        guard let lhsNumber = evaluateArithmetic(current), let rhsNumber = evaluateArithmetic(rhs) else { return rhs }
        let result: Double = switch operation {
        case "+=": lhsNumber + rhsNumber
        case "-=": lhsNumber - rhsNumber
        case "*=": lhsNumber * rhsNumber
        case "/=": rhsNumber == 0 ? lhsNumber : lhsNumber / rhsNumber
        case "%=": rhsNumber == 0 ? lhsNumber : lhsNumber.truncatingRemainder(dividingBy: rhsNumber)
        case "^=": pow(lhsNumber, rhsNumber)
        default: rhsNumber
        }
        return numericString(result)
    }

    private func loadDictionaries(_ directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.lowercased().hasPrefix("ai") && $0.pathExtension.lowercased() == "txt" }
        for url in urls {
            guard let source = try LegacyTextDecoder.decode(Data(contentsOf: url)) else { continue }
            // Foundation's Shift_JIS decoder may represent the 0x5C command byte
            // as a yen sign. Shino dictionaries use that byte as a backslash.
            parse(source.replacingOccurrences(of: "¥", with: "\\"))
            loadedDictionaryFileCount += 1
        }
    }

    private func parse(_ source: String) {
        var current: (kind: String, name: String, condition: String?, values: [String])?
        func finish() {
            guard let entry = current else { return }
            let values = entry.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !values.isEmpty else { current = nil; return }
            let item = ShinoEntry(condition: entry.condition, values: values)
            switch entry.kind {
            case "ev": events[entry.name, default: []].append(item)
            case "e": events["OnAITalk", default: []].append(item)
            case "jp": jumps[entry.name, default: []].append(item)
            case "id": resources[entry.name, default: []].append(item)
            case "fn": functions[entry.name, default: []].append(item)
            default: words[entry.name, default: []].append(contentsOf: values)
            }
            current = nil
        }
        var inBlockComment = false
        for rawLine in source.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if inBlockComment {
                if trimmed.contains("*/") {
                    inBlockComment = false
                }; continue
            }
            if trimmed.hasPrefix("/*") {
                inBlockComment = !trimmed.contains("*/"); continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("\\"), let comma = commaOutsideBrackets(in: trimmed) {
                finish()
                let header = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< comma])
                let value = String(trimmed[trimmed.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
                let open = header.firstIndex(of: "[")
                let kind = String(header[..<(open ?? header.endIndex)])
                let args = open.map { String(header[header.index(after: $0) ..< header.index(before: header.endIndex)]) } ?? ""
                let parts = splitArguments(args)
                let wordKinds = ["ms", "mz", "ml", "mc", "mh", "mt", "me", "mp", "dms", "m", "d", "k"]
                let rawName: String = if ["ev", "jp", "id", "fn"].contains(kind) {
                    parts.first ?? ""
                } else if wordKinds.contains(kind), parts.first?.isEmpty == false {
                    kind + parts[0]
                } else {
                    parts.first?.isEmpty == false ? parts[0] : kind
                }
                let name = rawName.hasPrefix("{") && rawName.hasSuffix("}")
                    ? String(rawName.dropFirst().dropLast()) : rawName
                let condition = ["ev", "jp", "id", "fn"].contains(kind) && parts.count > 1 ? parts[1] : nil
                current = (kind, name, condition, value.isEmpty ? [] : splitArguments(value))
            } else if current != nil {
                if current!.values.isEmpty {
                    current!.values.append(trimmed)
                } else {
                    current!.values[current!.values.index(before: current!.values.endIndex)].append("\n" + trimmed)
                }
            }
        }
        finish()
    }

    private func loadInitialVariables(_ directory: URL) throws {
        let url = directory.appending(path: "s_vars.txt")
        guard FileManager.default.fileExists(atPath: url.path), let source = try LegacyTextDecoder.decode(Data(contentsOf: url)) else { return }
        for line in source.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2, state.variables[parts[0]] == nil {
                state.variables[parts[0]] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
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

    private func save() throws {
        try FileManager.default.createDirectory(at: stateStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stateStoreURL, options: .atomic)
    }
}

private func commaOutsideBrackets(in value: String) -> String.Index? {
    var depth = 0
    for index in value.indices {
        if value[index] == "[" {
            depth += 1
        }
        if value[index] == "]" {
            depth -= 1
        }
        if value[index] == ",", depth == 0 {
            return index
        }
    }
    return nil
}

private func splitArguments(_ source: String) -> [String] {
    var result: [String] = [], current = "", depth = 0
    for character in source {
        if character == "[" {
            depth += 1
        }
        if character == "]" {
            depth -= 1
        }
        if character == ",", depth == 0 {
            result.append(current.trimmingCharacters(in: .whitespaces)); current = ""
        } else {
            current.append(character)
        }
    }
    result.append(current.trimmingCharacters(in: .whitespaces))
    return result
}

private func replaceCalls(in source: String, prefix: String, transform: (String) -> String) -> String {
    var value = source
    var replacements = 0
    while replacements < 256, let start = value.range(of: prefix) {
        var depth = 1, index = start.upperBound
        while index < value.endIndex, depth > 0 {
            if value[index] == "[" {
                depth += 1
            }
            if value[index] == "]" {
                depth -= 1
            }
            index = value.index(after: index)
        }
        guard depth == 0 else { break }
        let end = value.index(before: index)
        value.replaceSubrange(start.lowerBound ..< index, with: transform(String(value[start.upperBound ..< end])))
        replacements += 1
    }
    return value
}

private func replacePattern(_ pattern: String, in source: String, transform: (String) -> String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
    var value = source
    for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
        guard let whole = Range(match.range, in: value) else { continue }
        let capture = match.numberOfRanges > 1 ? Range(match.range(at: 1), in: value).map { String(value[$0]) } ?? "" : ""
        value.replaceSubrange(whole, with: transform(capture))
    }
    return value
}

private func numericString(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}

private func shiftJISData(_ value: String) -> Data {
    value.data(using: .shiftJIS) ?? Data(value.utf8)
}

private func shiftJISSubstring(_ value: String, offset: Int, count: Int) -> String {
    let data = shiftJISData(value)
    guard offset >= 0, count >= 0, offset < data.count else { return "" }
    return String(data: data[offset ..< min(offset + count, data.count)], encoding: .shiftJIS) ?? ""
}

private func sizeFormatted(_ bytes: Int64) -> String {
    let units = ["Bytes", "KB", "MB", "GB", "TB"]
    var value = Double(max(0, bytes))
    var index = 0
    while value >= 1024, index < units.count - 1 {
        value /= 1024
        index += 1
    }
    return index == 0 ? "\(Int(value)) \(units[index])" : String(format: "%.2f %@", value, units[index])
}

private func booleanValue(_ source: String) -> Bool {
    let value = removingOuterParentheses(source.trimmingCharacters(in: .whitespaces))
    if let parts = splitTopLevel(value, operators: ["||", "|"]) {
        return parts.values.contains(where: booleanValue)
    }
    if let parts = splitTopLevel(value, operators: ["&&", "&"]) {
        return parts.values.allSatisfy(booleanValue)
    }
    for operation in ["==", "!=", ">=", "<=", ">", "<"] {
        guard let comparison = splitTopLevel(value, operators: [operation]), comparison.values.count == 2 else {
            continue
        }
        let lhs = comparison.values[0].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        let rhs = comparison.values[1].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        if let left = evaluateArithmetic(lhs), let right = evaluateArithmetic(rhs) {
            return switch operation {
            case "==": left == right
            case "!=": left != right
            case ">=": left >= right
            case "<=": left <= right
            case ">": left > right
            case "<": left < right
            default: false
            }
        }
        return operation == "==" ? lhs == rhs : operation == "!=" ? lhs != rhs : false
    }
    if let number = evaluateArithmetic(value) {
        return number != 0
    }
    return !value.isEmpty && value != "0"
}

private func removingOuterParentheses(_ source: String) -> String {
    var value = source
    while value.first == "(", value.last == ")" {
        var depth = 0
        var enclosesWholeValue = true
        for index in value.indices {
            if value[index] == "(" {
                depth += 1
            }
            if value[index] == ")" {
                depth -= 1
            }
            if depth == 0, index != value.index(before: value.endIndex) {
                enclosesWholeValue = false
                break
            }
        }
        guard enclosesWholeValue else { break }
        value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }
    return value
}

private func splitTopLevel(_ source: String, operators: [String]) -> (operation: String, values: [String])? {
    for operation in operators {
        var values: [String] = []
        var start = source.startIndex
        var index = source.startIndex
        var roundDepth = 0
        var squareDepth = 0
        var quoted = false
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                quoted.toggle()
            }
            if !quoted {
                if character == "(" {
                    roundDepth += 1
                }
                if character == ")" {
                    roundDepth -= 1
                }
                if character == "[" {
                    squareDepth += 1
                }
                if character == "]" {
                    squareDepth -= 1
                }
            }
            if !quoted, roundDepth == 0, squareDepth == 0,
               source[index...].hasPrefix(operation)
            {
                values.append(String(source[start ..< index]))
                index = source.index(index, offsetBy: operation.count)
                start = index
                continue
            }
            index = source.index(after: index)
        }
        if !values.isEmpty {
            values.append(String(source[start...]))
            return (operation, values)
        }
    }
    return nil
}

private func evaluateArithmetic(_ source: String) -> Double? {
    var parser = ShinoArithmeticParser(source)
    guard let value = parser.expression() else { return nil }
    parser.skipSpaces()
    return parser.isAtEnd ? value : nil
}

private struct ShinoArithmeticParser {
    private let characters: [Character]
    private var position = 0

    init(_ source: String) {
        characters = Array(source)
    }

    var isAtEnd: Bool {
        position == characters.count
    }

    mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while true {
            skipSpaces()
            if consume("+") {
                guard let rhs = term() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = term() else { return nil }
                value -= rhs
            } else {
                return value
            }
        }
    }

    mutating func skipSpaces() {
        while position < characters.count, characters[position].isWhitespace {
            position += 1
        }
    }

    private mutating func term() -> Double? {
        guard var value = power() else { return nil }
        while true {
            skipSpaces()
            if consume("*") {
                guard let rhs = power() else { return nil }
                value *= rhs
            } else if consume("/") {
                guard let rhs = power(), rhs != 0 else { return nil }
                value /= rhs
            } else if consume("%") {
                guard let rhs = power(), rhs != 0 else { return nil }
                value.formTruncatingRemainder(dividingBy: rhs)
            } else {
                return value
            }
        }
    }

    private mutating func power() -> Double? {
        guard var value = unary() else { return nil }
        skipSpaces()
        if consume("^") {
            guard let rhs = power() else { return nil }
            value = pow(value, rhs)
        }
        return value
    }

    private mutating func unary() -> Double? {
        skipSpaces()
        if consume("+") {
            return unary()
        }
        if consume("-") {
            return unary().map(-)
        }
        return primary()
    }

    private mutating func primary() -> Double? {
        skipSpaces()
        if consume("(") {
            guard let value = expression() else { return nil }
            skipSpaces()
            return consume(")") ? value : nil
        }
        let start = position
        while position < characters.count, characters[position].isNumber || characters[position] == "." {
            position += 1
        }
        guard position > start else { return nil }
        return Double(String(characters[start ..< position]))
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard position < characters.count, characters[position] == character else { return false }
        position += 1
        return true
    }
}

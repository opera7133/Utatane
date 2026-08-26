import Foundation
import UtataneCore
import UtataneNativeSaori
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

private enum AkariEntry: Sendable {
    case talk(String)
    case jump(target: String, condition: String?)
}

private enum AkariExecution {
    case continued
    case broke
    case continuedLoop
    case returned(AkariValue)
}

private struct AkariProgram: Sendable {
    var events: [String: [AkariEntry]] = [:]
    var variables: [String: AkariValue] = [:]
    var words: [String: [String]] = [:]
    var functions: [String: AkariFunction] = [:]
}

public actor NativeAkariPersonalityEngine: PersonalityEngine {
    private var program: AkariProgram
    private var staticVariables: [String: AkariValue] = [:]
    private var activeStaticBindings: [String: String] = [:]
    private var activeFunctionName: String?
    private let variableStoreURL: URL
    private let fileSystem: AkariVirtualFileSystem
    private let saoriCaller: (any NativeSaoriCalling)?
    private let httpFetcher: any AkariHTTPFetching
    private var loadedSaori: [String: String] = [:]
    private let adapter = GhostEventShioriAdapter()

    public init(
        masterDirectoryURL: URL,
        variableStoreURL: URL? = nil,
        saoriCaller: (any NativeSaoriCalling)? = nil,
        httpFetcher: any AkariHTTPFetching = AkariURLSessionHTTPFetcher()
    ) throws {
        self.variableStoreURL = variableStoreURL ?? masterDirectoryURL.appending(path: "akari-vars.json")
        fileSystem = AkariVirtualFileSystem(
            master: masterDirectoryURL,
            storage: self.variableStoreURL.deletingLastPathComponent().appending(path: "files")
        )
        self.saoriCaller = saoriCaller ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        self.httpFetcher = httpFetcher
        program = try Self.loadProgram(from: masterDirectoryURL)
        if let data = try? Data(contentsOf: self.variableStoreURL) {
            let saved = (try? JSONDecoder().decode([String: AkariValue].self, from: data))
                ?? (try? JSONDecoder().decode([String: String].self, from: data).mapValues(AkariValue.string))
            if let saved {
                program.variables.merge(saved) { _, saved in saved }
            }
        }
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: masterDirectoryURL.appending(path: "descript.txt")), let text = decode(data) else { return false }
        return text.split(whereSeparator: \Character.isNewline).contains { line in
            let fields = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return fields.count == 2 && fields[0].caseInsensitiveCompare("shiori") == .orderedSame
                && URL(fileURLWithPath: fields[1]).lastPathComponent.caseInsensitiveCompare("akari.dll") == .orderedSame
        }
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let request = adapter.request(for: event)
        guard let id = request.id else { return PersonalityResponse(script: nil) }
        let source = resolve(event: id, request: request, depth: 0)
            ?? (id == "OnAITalk" ? resolve(event: "OnFreeTalk", request: request, depth: 0) : nil)
        if id == "OnClose" {
            try save()
        }
        if let source, let rendered = render(source, request: request) {
            return PersonalityResponse(script: SakuraScript(rawValue: rendered))
        }
        let references = Dictionary(uniqueKeysWithValues: (0 ..< 32).compactMap { index in
            request.reference(index).map { ("Reference\(index)", AkariValue.string($0)) }
        })
        let argument = AkariValue.dictionary(references.merging(["ID": .string(id)]) { _, newer in newer })
        guard let value = executeAZR(function: id, arguments: [argument], request: request, depth: 0),
              !value.stringValue.isEmpty
        else { return PersonalityResponse(script: nil) }
        return PersonalityResponse(script: SakuraScript(rawValue: value.stringValue))
    }

    private static func loadProgram(from master: URL) throws -> AkariProgram {
        var program = AkariProgram()
        loadInitialVariables(from: master.appending(path: "res/init.txt"), into: &program.variables)
        let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        program.variables.merge([
            "現在年": .integer(now.year ?? 0), "現在月": .integer(now.month ?? 0), "現在日": .integer(now.day ?? 0),
            "現在時": .integer(now.hour ?? 0), "現在分": .integer(now.minute ?? 0), "現在秒": .integer(now.second ?? 0)
        ]) { current, _ in current }
        var loadedPlainScript = false
        guard let enumerator = FileManager.default.enumerator(at: master, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return program }
        for case let url as URL in enumerator {
            guard let data = try? Data(contentsOf: url), let text = decode(data) else { continue }
            switch url.pathExtension.lowercased() {
            case "txt" where !["init.txt", "descript.txt"].contains(url.lastPathComponent.lowercased()):
                loadedPlainScript = true
                merge(parse(text), into: &program)
            case "azr":
                loadedPlainScript = true
                program.functions.merge(AkariAZRParser.functions(in: text)) { _, newer in newer }
                for declaration in AkariAZRParser.globalDeclarations(in: text) {
                    program.variables[declaration.name] = declaration.expression.map(parseValue) ?? .null
                }
            default: continue
            }
        }
        if !loadedPlainScript,
           let data = try? Data(contentsOf: master.appending(path: "main.amb")),
           let entries = AkariMaterialBox.decode(data)
        {
            for entry in entries {
                guard let text = decode(entry.data) else { continue }
                switch URL(fileURLWithPath: entry.path).pathExtension.lowercased() {
                case "txt": merge(parse(text), into: &program)
                case "azr":
                    program.functions.merge(AkariAZRParser.functions(in: text)) { _, newer in newer }
                    for declaration in AkariAZRParser.globalDeclarations(in: text) {
                        program.variables[declaration.name] = declaration.expression.map(parseValue) ?? .null
                    }
                default: continue
                }
            }
        }
        return program
    }

    private static func loadInitialVariables(from url: URL, into variables: inout [String: AkariValue]) {
        guard let data = try? Data(contentsOf: url), let text = decode(data) else { return }
        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine)
            guard !line.hasPrefix("#"), !line.hasPrefix("＃"), let separator = line.firstIndex(of: ":") else { continue }
            variables[String(line[..<separator])] = parseValue(String(line[line.index(after: separator)...]))
        }
    }

    private static func parse(_ text: String) -> AkariProgram {
        var result = AkariProgram()
        var event: String?
        var entries: [AkariEntry] = []
        var candidate: String?
        var word: String?
        var wordValues: [String] = []
        func flushCandidate() {
            if let candidate, !candidate.isEmpty {
                entries.append(.talk(candidate))
            }
            candidate = nil
        }
        func flushEvent(nextEvent: String? = nil) {
            flushCandidate()
            if let event {
                if entries.isEmpty, let nextEvent {
                    entries.append(.jump(target: nextEvent, condition: nil))
                }
                result.events[event, default: []].append(contentsOf: entries)
            }
            entries = []
        }
        func flushWord() {
            if let word, !wordValues.isEmpty {
                result.words[word, default: []].append(contentsOf: wordValues)
            }
            word = nil
            wordValues = []
        }
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("＊") || line.hasPrefix("*") {
                flushWord()
                let name = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                flushEvent(nextEvent: name)
                event = name
            } else if line.hasPrefix("＠") || line.hasPrefix("@") {
                flushEvent()
                flushWord()
                event = nil
                word = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if word != nil {
                if !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("＃") {
                    wordValues.append(line)
                }
            } else if line.hasPrefix("＞") || line.hasPrefix(">") {
                flushCandidate()
                let fields = line.dropFirst().split(separator: "\t", maxSplits: 1).map(String.init)
                if let target = fields.first {
                    entries.append(.jump(target: target, condition: fields.count > 1 ? fields[1] : nil))
                }
            } else if line.hasPrefix("・") {
                flushCandidate()
                candidate = String(line.dropFirst())
            } else if candidate != nil, !line.hasPrefix("＃"), !line.hasPrefix("#") {
                candidate?.append("\n" + line)
            }
        }
        flushWord()
        flushEvent()
        return result
    }

    private static func merge(_ source: AkariProgram, into destination: inout AkariProgram) {
        for (key, values) in source.events {
            destination.events[key, default: []].append(contentsOf: values)
        }
        for (key, values) in source.words {
            destination.words[key, default: []].append(contentsOf: values)
        }
    }

    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
    }

    private static func parseValue(_ source: String) -> AkariValue {
        var parser = AkariValueParser(source)
        return parser.parse() ?? .string(source)
    }

    private func resolve(event: String, request: ShioriRequest, depth: Int) -> String? {
        guard depth < 32, let entries = program.events[event] else { return nil }
        var talks: [String] = []
        for entry in entries {
            switch entry {
            case let .talk(source): talks.append(source)
            case let .jump(target, condition):
                guard condition.map({ conditionMatches($0, request: request) }) ?? true,
                      let renderedTarget = interpolate(target, request: request),
                      let result = resolve(event: renderedTarget, request: request, depth: depth + 1)
                else { continue }
                return result
            }
        }
        return talks.randomElement()
    }

    private func conditionMatches(_ source: String, request: ShioriRequest) -> Bool {
        guard let condition = interpolate(source, request: request) else { return false }
        guard let separator = condition.firstIndex(of: "=") else { return Int(condition) != 0 }
        let lhs = String(condition[..<separator]).trimmingCharacters(in: .whitespaces)
        let rhs = String(condition[condition.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        let range = rhs.replacingOccurrences(of: "～", with: "~").split(separator: "~", maxSplits: 1, omittingEmptySubsequences: false)
        if range.count == 2, let value = Int(lhs) {
            let lower = Int(range[0])
            let upper = Int(range[1])
            return (lower.map { value >= $0 } ?? true) && (upper.map { value <= $0 } ?? true)
        }
        return lhs == rhs
    }

    private func render(_ source: String, request: ShioriRequest) -> String? {
        guard var text = interpolate(source, request: request) else { return nil }
        text = replaceSurfaces(in: text)
        var script = ""
        for (index, part) in text.components(separatedBy: "：").enumerated() {
            script += index.isMultiple(of: 2) ? "\\0" : "\\1"
            script += part
        }
        return script + "\\e"
    }

    private func interpolate(_ source: String, request: ShioriRequest) -> String? {
        var text = source.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")").replacingOccurrences(of: "＄", with: "$")
        for index in 0 ..< 32 {
            text = text.replacingOccurrences(of: "(R\(index))", with: request.reference(index) ?? "")
        }
        var iterations = 0
        while let call = innermostFunction(in: text) {
            guard iterations < 64, let value = evaluate(function: call.name, arguments: splitArguments(call.arguments), request: request) else { return nil }
            text.replaceSubrange(call.range, with: value.stringValue)
            iterations += 1
        }
        guard !containsUnsupportedFunction(in: text) else { return nil }
        for (name, value) in program.variables {
            text = text.replacingOccurrences(of: "(\(name))", with: value.stringValue)
        }
        for (name, values) in program.words where text.contains("(\(name))") {
            text = text.replacingOccurrences(of: "(\(name))", with: values.randomElement() ?? "")
        }
        return text
    }

    private func evaluate(function name: String, arguments rawArguments: [String], request: ShioriRequest) -> AkariValue? {
        let arguments = rawArguments.map { argument -> AkariValue in
            let rendered = interpolate(argument.trimmingCharacters(in: .whitespaces), request: request) ?? argument
            let value = Self.parseValue(rendered)
            if case let .string(name) = value, let variable = program.variables[name] {
                return variable
            }
            return value
        }
        switch name.uppercased() {
        case "INC": return arguments.first?.integerValue.map { .integer($0 + 1) }
        case "DEC": return arguments.first?.integerValue.map { .integer($0 - 1) }
        case "ADD": return integer(arguments, operation: +)
        case "SUB": return integer(arguments, operation: -)
        case "MUL": return integer(arguments, operation: *)
        case "DIV": return integer(arguments) { $1 == 0 ? nil : $0 / $1 }
        case "MOD": return integer(arguments) { $1 == 0 ? nil : $0 % $1 }
        case "CMP": return arguments.count >= 2 ? .integer(arguments[0] == arguments[1] ? 1 : 0) : nil
        case "IF":
            guard arguments.count >= 3 else { return nil }
            return arguments[0].integerValue != 0 ? arguments[1] : arguments[2]
        case "SET":
            guard arguments.count >= 2 else { return nil }
            program.variables[arguments[0].stringValue] = arguments[1]
            try? save()
            return .string("")
        case "STRLEN": return arguments.first.map { .integer($0.stringValue.count) }
        case "STRREPLACE":
            guard arguments.count >= 3 else { return nil }
            return .string(arguments[0].stringValue.replacingOccurrences(of: arguments[1].stringValue, with: arguments[2].stringValue))
        case "SUBSTR":
            guard arguments.count >= 2, let start = arguments[1].integerValue else { return nil }
            return .string(substring(arguments[0].stringValue, start: start, length: arguments.count > 2 ? arguments[2].integerValue : nil))
        case "RND", "RAND":
            guard let limit = arguments.first?.integerValue, limit > 0 else { return nil }
            return .integer(Int.random(in: 0 ..< limit))
        case "GETFILENAMEFROMURL":
            guard let value = arguments.first?.stringValue else { return nil }
            return .string(URL(string: value)?.lastPathComponent ?? URL(fileURLWithPath: value).lastPathComponent)
        case "ARYVN", "_ARYVN":
            guard let first = arguments.first, case let .array(values) = first else { return nil }
            return .integer(values.count)
        case "DICVN", "_DICVN":
            guard let first = arguments.first, case let .dictionary(values) = first else { return nil }
            return .integer(values.count)
        case "DICKEYGET", "_DICKEYGET":
            guard let first = arguments.first, case let .dictionary(values) = first else { return nil }
            return .array(values.keys.sorted().map(AkariValue.string))
        case "DICVGET", "_DICVGET":
            guard let first = arguments.first, case let .dictionary(values) = first else { return nil }
            return .array(values.keys.sorted().compactMap { values[$0] })
        case "ARYGET", "_ARYGET":
            guard arguments.count >= 2, case let .array(values) = arguments[0],
                  let index = arguments[1].integerValue, values.indices.contains(index)
            else { return nil }
            return values[index]
        case "DICGET", "_DICGET":
            guard arguments.count >= 2, case let .dictionary(values) = arguments[0] else { return nil }
            return values[arguments[1].stringValue] ?? .null
        case "RANDSELECT", "_RANDSELECT":
            let values = arguments.flatMap { value -> [AkariValue] in
                if case let .array(items) = value {
                    return items
                }
                return [value]
            }
            return values.randomElement()
        case "GETTYPE", "_GETTYPE": return arguments.first.map { .string($0.typeName) }
        case "STRARY", "_STRARY": return arguments.first.map { .array($0.stringValue.map { .string(String($0)) }) }
        case "ARYSTR", "_ARYSTR":
            guard let first = arguments.first, case let .array(values) = first else { return nil }
            return .string(values.map(\.stringValue).joined())
        case "_FNCSTR":
            guard let function = arguments.first?.stringValue else { return nil }
            return executeAZR(function: function, arguments: Array(arguments.dropFirst()), request: request, depth: 1)
        case "_READTEXT":
            guard let path = arguments.first?.stringValue else { return nil }
            return fileSystem.readText(
                path: path,
                encoding: arguments.count > 1 ? arguments[1].stringValue : "auto",
                newline: arguments.count > 2 ? arguments[2].stringValue : nil
            )
        case "_WRITETEXT":
            guard arguments.count >= 2 else { return nil }
            return .integer(fileSystem.writeText(
                path: arguments[0].stringValue,
                value: arguments[1],
                encoding: arguments.count > 2 ? arguments[2].stringValue : "utf8",
                newline: arguments.count > 3 ? arguments[3].stringValue : "crlf"
            ) ? 1 : 0)
        case "_ISFILE": return .integer(arguments.first.map { fileSystem.exists(path: $0.stringValue) } == true ? 1 : 0)
        case "_FENUM": return arguments.first.flatMap { fileSystem.enumerate(path: $0.stringValue) }
        case "_ABSPATH": return arguments.first.flatMap { fileSystem.absolutePath(path: $0.stringValue) }.map(AkariValue.string)
        case "_READCSV":
            guard let path = arguments.first?.stringValue else { return nil }
            return fileSystem.readCSV(path: path, encoding: arguments.count > 1 ? arguments[1].stringValue : "auto")
        case "_SAVECSV":
            guard arguments.count >= 2 else { return nil }
            return .integer(fileSystem.writeCSV(
                path: arguments[0].stringValue,
                rows: arguments[1],
                encoding: arguments.count > 2 ? arguments[2].stringValue : "utf8"
            ) ? 1 : 0)
        case "_VSAVE":
            guard arguments.count >= 2 else { return nil }
            return .integer(fileSystem.saveValue(name: arguments[0].stringValue, value: arguments[1]) ? 1 : 0)
        case "_VLOAD": return arguments.first.flatMap { fileSystem.loadValue(name: $0.stringValue) } ?? .null
        case "_FCOPY":
            guard arguments.count >= 2 else { return nil }
            return .integer(fileSystem.copy(source: arguments[0].stringValue, destination: arguments[1].stringValue) ? 1 : 0)
        case "_FMOVE":
            guard arguments.count >= 2 else { return nil }
            return .integer(fileSystem.copy(source: arguments[0].stringValue, destination: arguments[1].stringValue, move: true) ? 1 : 0)
        case "_FDELETE": return .integer(arguments.first.map { fileSystem.delete(path: $0.stringValue) } == true ? 1 : 0)
        case "_DCREATE": return .integer(arguments.first.map { fileSystem.createDirectory(path: $0.stringValue) } == true ? 1 : 0)
        case "_DDELETE": return .integer(arguments.first.map { fileSystem.delete(path: $0.stringValue, directory: true) } == true ? 1 : 0)
        case "_DCOPY":
            guard arguments.count >= 2 else { return nil }
            return .integer(fileSystem.copy(source: arguments[0].stringValue, destination: arguments[1].stringValue) ? 1 : 0)
        case "_SCRIPT_LOAD":
            guard let path = arguments.first?.stringValue, let source = fileSystem.readScript(path: path) else { return .integer(0) }
            program.functions.merge(AkariAZRParser.functions(in: source)) { _, newer in newer }
            for declaration in AkariAZRParser.globalDeclarations(in: source) {
                if program.variables[declaration.name] == nil {
                    program.variables[declaration.name] = declaration.expression.map(Self.parseValue) ?? .null
                }
            }
            return .integer(1)
        case "_TOKENIZE": return arguments.first.flatMap { fileSystem.tokenize(path: $0.stringValue) }
        case "_FILEMD5": return arguments.first.flatMap { fileSystem.md5(path: $0.stringValue) }.map(AkariValue.string)
        case "_SAORILOAD":
            guard let caller = saoriCaller, let path = arguments.first?.stringValue else { return .integer(0) }
            let identifier = arguments.count > 1 && !arguments[1].stringValue.isEmpty ? arguments[1].stringValue : path
            caller.load(path)
            loadedSaori[identifier] = path
            return .integer(1)
        case "_SAORIUNLOAD":
            guard let caller = saoriCaller, let identifier = arguments.first?.stringValue,
                  let path = loadedSaori.removeValue(forKey: identifier)
            else { return .integer(0) }
            caller.unload(path)
            return .integer(1)
        case "_SAORIREQUEST":
            guard let caller = saoriCaller, let identifier = arguments.first?.stringValue else { return nil }
            let persistentPath = loadedSaori[identifier]
            let path = persistentPath ?? identifier
            if persistentPath == nil {
                caller.load(path)
            }
            let result = caller.call(path, arguments: arguments.dropFirst().map(\.stringValue))
            if persistentPath == nil {
                caller.unload(path)
            }
            let values = result.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
            var response: [String: AkariValue] = [:]
            if let first = values.first {
                response["Result"] = .string(first)
            }
            for (index, value) in values.enumerated() {
                response["Value\(index)"] = .string(value)
            }
            return .dictionary(response)
        case "_HTTPGET":
            guard let url = arguments.first.flatMap({ URL(string: $0.stringValue) }),
                  let data = httpFetcher.fetch(url: url, maximumBytes: 1_048_576),
                  let text = decodeHTTPText(data, encoding: arguments.count > 1 ? arguments[1].stringValue : "sjis")
            else { return nil }
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            return .array(normalized.split(separator: "\n", omittingEmptySubsequences: false).map { .string(String($0)) })
        case "_HTTP_DOWNLOAD":
            guard arguments.count >= 2, let url = URL(string: arguments[0].stringValue),
                  let data = httpFetcher.fetch(url: url, maximumBytes: 8_388_608)
            else { return .integer(0) }
            return .integer(fileSystem.writeData(path: arguments[1].stringValue, data: data) ? 1 : 0)
        default:
            if let result = AkariPureFunctions.evaluate(name, arguments: arguments) {
                return result
            }
            let variables = program.variables
            let result = executeAZR(function: name, arguments: arguments, request: request, depth: 0)
            if result == nil {
                program.variables = variables
            }
            return result
        }
    }

    private func executeAZR(
        function name: String,
        arguments: [AkariValue],
        request: ShioriRequest,
        depth: Int
    ) -> AkariValue? {
        guard depth < 32, let function = program.functions[name] else { return nil }
        let previousFunctionName = activeFunctionName
        let previousBindings = activeStaticBindings
        activeFunctionName = name
        activeStaticBindings = [:]
        var locals = Dictionary(uniqueKeysWithValues: function.parameters.enumerated().map { index, parameter in
            (parameter, index < arguments.count ? arguments[index] : .null)
        })
        guard let result = executeAZRBody(function.body, locals: &locals, request: request, depth: depth, steps: 0) else {
            activeFunctionName = previousFunctionName
            activeStaticBindings = previousBindings
            return nil
        }
        for (name, key) in activeStaticBindings {
            staticVariables[key] = locals[name]
        }
        activeFunctionName = previousFunctionName
        activeStaticBindings = previousBindings
        switch result {
        case .continued: return .null
        case let .returned(value): return value
        case .broke, .continuedLoop: return nil
        }
    }

    private func executeAZRBody(
        _ body: String,
        locals: inout [String: AkariValue],
        request: ShioriRequest,
        depth: Int,
        steps: Int
    ) -> AkariExecution? {
        guard steps < 10000, let nodes = AkariAZRParser.nodes(in: body) else { return nil }
        var steps = steps
        for node in nodes {
            steps += 1
            guard steps < 10000 else { return nil }
            switch node {
            case let .simple(statement):
                if statement == "break" {
                    return .broke
                }
                if statement == "continue" {
                    return .continuedLoop
                }
                if statement.hasPrefix("return") {
                    let expression = statement.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let value = expression.isEmpty ? AkariValue.null : evaluateAZRExpression(String(expression), locals: &locals, request: request, depth: depth) else { return nil }
                    return .returned(value)
                }
                guard executeSimpleAZRStatement(statement, locals: &locals, request: request, depth: depth) else { return nil }
            case let .conditional(condition, thenBody, elseBody):
                guard let value = evaluateAZRExpression(condition, locals: &locals, request: request, depth: depth) else { return nil }
                let selected = truthy(value) ? thenBody : elseBody
                if let selected {
                    guard let result = executeAZRBody(selected, locals: &locals, request: request, depth: depth, steps: steps) else { return nil }
                    if case .returned = result {
                        return result
                    }
                    if case .broke = result {
                        return result
                    }
                    if case .continuedLoop = result {
                        return result
                    }
                }
            case let .whileLoop(condition, loopBody):
                var iterations = 0
                while true {
                    guard iterations < 10000,
                          let value = evaluateAZRExpression(condition, locals: &locals, request: request, depth: depth)
                    else { return nil }
                    if !truthy(value) {
                        break
                    }
                    guard let result = executeAZRBody(loopBody, locals: &locals, request: request, depth: depth, steps: steps + iterations) else { return nil }
                    if case .returned = result {
                        return result
                    }
                    if case .broke = result {
                        break
                    }
                    if case .continuedLoop = result {
                        iterations += 1
                        continue
                    }
                    iterations += 1
                }
            case let .forLoop(initializer, condition, increment, loopBody):
                guard executeSimpleAZRStatement(initializer, locals: &locals, request: request, depth: depth) else { return nil }
                var iterations = 0
                while true {
                    guard iterations < 10000,
                          let value = evaluateAZRExpression(condition, locals: &locals, request: request, depth: depth)
                    else { return nil }
                    if !truthy(value) {
                        break
                    }
                    guard let result = executeAZRBody(loopBody, locals: &locals, request: request, depth: depth, steps: steps + iterations) else { return nil }
                    if case .returned = result {
                        return result
                    }
                    if case .broke = result {
                        break
                    }
                    guard executeSimpleAZRStatement(increment, locals: &locals, request: request, depth: depth) else { return nil }
                    iterations += 1
                    if case .continuedLoop = result {
                        continue
                    }
                }
            case let .switchStatement(expression, body):
                guard let selected = evaluateAZRExpression(expression, locals: &locals, request: request, depth: depth),
                      let cases = parseSwitchCases(body)
                else { return nil }
                var start = cases.firstIndex { $0.label == nil }
                for (index, item) in cases.enumerated() where item.label != nil {
                    guard let label = item.label,
                          let value = evaluateAZRExpression(label, locals: &locals, request: request, depth: depth)
                    else { return nil }
                    if value == selected {
                        start = index
                        break
                    }
                }
                if let start {
                    for item in cases[start...] {
                        guard let result = executeAZRBody(item.body, locals: &locals, request: request, depth: depth, steps: steps) else { return nil }
                        switch result {
                        case .broke: break
                        case .continued: continue
                        case .continuedLoop, .returned: return result
                        }
                        break
                    }
                }
            }
        }
        return .continued
    }

    private func parseSwitchCases(_ source: String) -> [(label: String?, body: String)]? {
        let pattern = #"(?m)(?:^|[;{}]\s*)(case\s+([^:]+)|default)\s*:"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return nil }
        return matches.enumerated().compactMap { index, match in
            guard let whole = Range(match.range, in: source) else { return nil }
            let end = index + 1 < matches.count ? Range(matches[index + 1].range, in: source)?.lowerBound ?? source.endIndex : source.endIndex
            let label = Range(match.range(at: 2), in: source).map { String(source[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            return (label, String(source[whole.upperBound ..< end]))
        }
    }

    private func evaluateAZRExpression(
        _ source: String,
        locals: inout [String: AkariValue],
        request: ShioriRequest,
        depth: Int
    ) -> AkariValue? {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("("), source.hasSuffix(")"),
           closingParenthesis(in: source, opening: source.startIndex) == source.index(before: source.endIndex)
        {
            return evaluateAZRExpression(String(source.dropFirst().dropLast()), locals: &locals, request: request, depth: depth)
        }
        if let question = topLevelRange(of: "?", in: source),
           let colon = topLevelRange(of: ":", in: String(source[question.upperBound...])),
           let condition = evaluateAZRExpression(String(source[..<question.lowerBound]), locals: &locals, request: request, depth: depth)
        {
            let remainder = String(source[question.upperBound...])
            let trueExpression = String(remainder[..<colon.lowerBound])
            let falseExpression = String(remainder[colon.upperBound...])
            return evaluateAZRExpression(truthy(condition) ? trueExpression : falseExpression, locals: &locals, request: request, depth: depth)
        }
        for type in ["int", "long", "double", "string", "array", "dict"] where source.hasPrefix("(\(type))") {
            guard let value = evaluateAZRExpression(String(source.dropFirst(type.count + 2)), locals: &locals, request: request, depth: depth) else { return nil }
            return cast(value, to: type)
        }
        if source.hasPrefix("!") {
            guard let value = evaluateAZRExpression(String(source.dropFirst()), locals: &locals, request: request, depth: depth) else { return nil }
            return .integer(truthy(value) ? 0 : 1)
        }
        if source.hasPrefix("~") {
            guard let value = evaluateAZRExpression(String(source.dropFirst()), locals: &locals, request: request, depth: depth)?.integerValue else { return nil }
            return .integer(~value)
        }
        for operation in ["||", "&&"] {
            if let parts = splitTopLevel(source, operator: operation), parts.count > 1 {
                let values = parts.compactMap { evaluateAZRExpression($0, locals: &locals, request: request, depth: depth) }
                guard values.count == parts.count else { return nil }
                return .integer(operation == "||" ? (values.contains(where: truthy) ? 1 : 0) : (values.allSatisfy(truthy) ? 1 : 0))
            }
        }
        for operation in ["==", "!=", "<=", ">=", "<", ">"] {
            if let parts = splitTopLevel(source, operator: operation), parts.count == 2,
               let lhs = evaluateAZRExpression(parts[0], locals: &locals, request: request, depth: depth),
               let rhs = evaluateAZRExpression(parts[1], locals: &locals, request: request, depth: depth)
            {
                return .integer(compare(lhs, rhs, operation: operation) ? 1 : 0)
            }
        }
        for operation in ["|", "^", "&", "<<", ">>"] {
            if let parts = splitTopLevel(source, operator: operation), parts.count == 2,
               let lhs = evaluateAZRExpression(parts[0], locals: &locals, request: request, depth: depth)?.integerValue,
               let rhs = evaluateAZRExpression(parts[1], locals: &locals, request: request, depth: depth)?.integerValue
            {
                switch operation {
                case "|": return .integer(lhs | rhs)
                case "^": return .integer(lhs ^ rhs)
                case "&": return .integer(lhs & rhs)
                case "<<" where rhs >= 0: return .integer(lhs << rhs)
                case ">>" where rhs >= 0: return .integer(lhs >> rhs)
                default: return nil
                }
            }
        }
        if let parts = splitTopLevel(source, operator: "+"), parts.count > 1 {
            let values = parts.compactMap { evaluateAZRExpression($0, locals: &locals, request: request, depth: depth) }
            guard values.count == parts.count else { return nil }
            if values.allSatisfy({ $0.integerValue != nil }) {
                return .integer(values.compactMap(\.integerValue).reduce(0, +))
            }
            return .string(values.map(\.stringValue).joined())
        }
        for operation in ["-", "*", "/", "%"] {
            if let parts = splitTopLevel(source, operator: operation), parts.count == 2,
               let lhs = evaluateAZRExpression(parts[0], locals: &locals, request: request, depth: depth)?.integerValue,
               let rhs = evaluateAZRExpression(parts[1], locals: &locals, request: request, depth: depth)?.integerValue
            {
                switch operation {
                case "-": return .integer(lhs - rhs)
                case "*": return .integer(lhs * rhs)
                case "/" where rhs != 0: return .integer(lhs / rhs)
                case "%" where rhs != 0: return .integer(lhs % rhs)
                default: return nil
                }
            }
        }
        if let call = parseAZRCall(source) {
            let values = splitArguments(call.arguments).compactMap {
                evaluateAZRExpression($0, locals: &locals, request: request, depth: depth + 1)
            }
            guard values.count == splitArguments(call.arguments).count else { return nil }
            if program.functions[call.name] != nil {
                return executeAZR(function: call.name, arguments: values, request: request, depth: depth + 1)
            }
            return evaluate(function: call.name, arguments: values.map(\.literal), request: request)
        }
        if let indexed = parseIndexedValue(source),
           let base = evaluateAZRExpression(indexed.name, locals: &locals, request: request, depth: depth),
           let key = evaluateAZRExpression(indexed.index, locals: &locals, request: request, depth: depth)
        {
            switch base {
            case let .array(values):
                guard let index = key.integerValue, values.indices.contains(index) else { return .null }
                return values[index]
            case let .dictionary(values): return values[key.stringValue] ?? .null
            default: return nil
            }
        }
        if let value = locals[source] ?? program.variables[source] {
            return value
        }
        return Self.parseValue(source)
    }

    private func cast(_ value: AkariValue, to type: String) -> AkariValue? {
        switch type {
        case "int", "long": return value.integerValue.map(AkariValue.integer)
        case "double": return Double(value.stringValue).map(AkariValue.double)
        case "string": return .string(value.stringValue)
        case "array":
            if case .array = value {
                return value
            }
            return .array([value])
        case "dict":
            if case .dictionary = value {
                return value
            }
            return nil
        default: return nil
        }
    }

    private func decodeHTTPText(_ data: Data, encoding: String) -> String? {
        switch encoding.lowercased().replacingOccurrences(of: "-", with: "") {
        case "utf8": String(data: data, encoding: .utf8)
        case "eucjp": String(data: data, encoding: .japaneseEUC)
        case "jis", "iso2022jp": String(data: data, encoding: .iso2022JP)
        case "sjis", "shiftjis", "": String(data: data, encoding: .shiftJIS)
        case "auto": String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
        default: nil
        }
    }

    private func executeSimpleAZRStatement(
        _ rawStatement: String,
        locals: inout [String: AkariValue],
        request: ShioriRequest,
        depth: Int
    ) -> Bool {
        let statement = rawStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        if statement.isEmpty {
            return true
        }
        let declarations = AkariAZRParser.declarationList(statement)
        if !declarations.isEmpty {
            for declaration in declarations {
                let initial = declaration.expression.flatMap {
                    evaluateAZRExpression($0, locals: &locals, request: request, depth: depth)
                } ?? .null
                if statement.hasPrefix("static "), let function = activeFunctionName {
                    let key = "\(function).\(declaration.name)"
                    activeStaticBindings[declaration.name] = key
                    locals[declaration.name] = staticVariables[key] ?? initial
                } else {
                    locals[declaration.name] = initial
                }
            }
            return true
        }
        for suffix in ["++", "--"] where statement.hasSuffix(suffix) {
            let target = String(statement.dropLast(2)).trimmingCharacters(in: .whitespaces)
            guard let current = value(forTarget: target, locals: locals)?.integerValue else { return false }
            return assign(.integer(current + (suffix == "++" ? 1 : -1)), to: target, locals: &locals)
        }
        for operation in ["+=", "-=", "*=", "/=", "%=", "="] {
            guard let range = topLevelRange(of: operation, in: statement) else { continue }
            let target = String(statement[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let expression = String(statement[range.upperBound...])
            guard let rhs = evaluateAZRExpression(expression, locals: &locals, request: request, depth: depth) else { return false }
            let assignedValue: AkariValue
            if operation == "=" {
                assignedValue = rhs
            } else {
                guard let lhs = value(forTarget: target, locals: locals) else { return false }
                if operation == "+=" {
                    switch (lhs, rhs) {
                    case let (.array(left), .array(right)): assignedValue = .array(left + right)
                    case let (.array(left), value): assignedValue = .array(left + [value])
                    case let (.dictionary(left), .dictionary(right)): assignedValue = .dictionary(left.merging(right) { _, newer in newer })
                    case _ where lhs.integerValue == nil || rhs.integerValue == nil: assignedValue = .string(lhs.stringValue + rhs.stringValue)
                    default:
                        guard let left = lhs.integerValue, let right = rhs.integerValue else { return false }
                        assignedValue = .integer(left + right)
                    }
                } else {
                    guard let left = lhs.integerValue, let right = rhs.integerValue else { return false }
                    switch operation {
                    case "-=": assignedValue = .integer(left - right)
                    case "*=": assignedValue = .integer(left * right)
                    case "/=" where right != 0: assignedValue = .integer(left / right)
                    case "%=" where right != 0: assignedValue = .integer(left % right)
                    default: return false
                    }
                }
            }
            return assign(assignedValue, to: target, locals: &locals)
        }
        guard parseAZRCall(statement) != nil else { return false }
        return evaluateAZRExpression(statement, locals: &locals, request: request, depth: depth) != nil
    }

    private func value(forTarget target: String, locals: [String: AkariValue]) -> AkariValue? {
        if let indexed = parseIndexedValue(target), let base = locals[indexed.name] ?? program.variables[indexed.name] {
            let keyName = indexed.index.trimmingCharacters(in: .whitespaces)
            let key = locals[keyName] ?? program.variables[keyName] ?? Self.parseValue(keyName)
            switch base {
            case let .array(values): return key.integerValue.flatMap { values.indices.contains($0) ? values[$0] : nil }
            case let .dictionary(values): return values[key.stringValue]
            default: return nil
            }
        }
        return locals[target] ?? program.variables[target]
    }

    private func assign(_ value: AkariValue, to target: String, locals: inout [String: AkariValue]) -> Bool {
        if let indexed = parseIndexedValue(target) {
            let keyName = indexed.index.trimmingCharacters(in: .whitespaces)
            let key = locals[keyName] ?? program.variables[keyName] ?? Self.parseValue(keyName)
            let local = locals[indexed.name] != nil
            guard var base = locals[indexed.name] ?? program.variables[indexed.name] else { return false }
            switch base {
            case var .array(values):
                guard let index = key.integerValue, values.indices.contains(index) else { return false }
                values[index] = value
                base = .array(values)
            case var .dictionary(values):
                values[key.stringValue] = value
                base = .dictionary(values)
            default: return false
            }
            if local {
                locals[indexed.name] = base
            } else {
                program.variables[indexed.name] = base
            }
            return true
        }
        guard target.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
        if locals[target] != nil {
            locals[target] = value
        } else {
            program.variables[target] = value
        }
        return true
    }

    private func truthy(_ value: AkariValue) -> Bool {
        switch value {
        case .null: false
        case let .integer(value): value != 0
        case let .double(value): value != 0
        case let .string(value): !value.isEmpty && value != "0"
        case let .array(values): !values.isEmpty
        case let .dictionary(values): !values.isEmpty
        }
    }

    private func compare(_ lhs: AkariValue, _ rhs: AkariValue, operation: String) -> Bool {
        if let left = lhs.integerValue, let right = rhs.integerValue {
            switch operation {
            case "==": return left == right
            case "!=": return left != right
            case "<": return left < right
            case ">": return left > right
            case "<=": return left <= right
            case ">=": return left >= right
            default: return false
            }
        }
        switch operation {
        case "==": return lhs == rhs
        case "!=": return lhs != rhs
        case "<": return lhs.stringValue < rhs.stringValue
        case ">": return lhs.stringValue > rhs.stringValue
        case "<=": return lhs.stringValue <= rhs.stringValue
        case ">=": return lhs.stringValue >= rhs.stringValue
        default: return false
        }
    }

    private func parseDeclaration(_ source: String) -> (name: String, expression: String?)? {
        let types = ["string", "int", "long", "double", "array", "dict"]
        guard let type = types.first(where: { source.hasPrefix($0 + " ") || source.hasPrefix($0 + "\t") }) else { return nil }
        let remainder = source.dropFirst(type.count).trimmingCharacters(in: .whitespaces)
        if let separator = remainder.firstIndex(of: "=") {
            return (
                String(remainder[..<separator]).trimmingCharacters(in: .whitespaces),
                String(remainder[remainder.index(after: separator)...])
            )
        }
        return (remainder, nil)
    }

    private func topLevelAssignment(in source: String) -> (name: String, expression: String)? {
        guard let separator = topLevelIndex(of: "=", in: source) else { return nil }
        let name = source[..<separator].trimmingCharacters(in: .whitespaces)
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (name, String(source[source.index(after: separator)...]))
    }

    private func parseAZRCall(_ source: String) -> (name: String, arguments: String)? {
        guard let opening = source.firstIndex(of: "("), source.last == ")" else { return nil }
        let name = source[..<opening].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (name, String(source[source.index(after: opening) ..< source.index(before: source.endIndex)]))
    }

    private func parseIndexedValue(_ source: String) -> (name: String, index: String)? {
        guard let opening = source.firstIndex(of: "["), source.last == "]" else { return nil }
        return (
            String(source[..<opening]).trimmingCharacters(in: .whitespaces),
            String(source[source.index(after: opening) ..< source.index(before: source.endIndex)])
        )
    }

    private func splitBinary(_ source: String, operator target: Character) -> [String]? {
        var parts: [String] = []
        var start = source.startIndex
        var parenthesisDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
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
            if character == "[" {
                bracketDepth += 1
            }
            if character == "]" {
                bracketDepth -= 1
            }
            if character == target, parenthesisDepth == 0, braceDepth == 0, bracketDepth == 0 {
                parts.append(String(source[start ..< index]))
                start = source.index(after: index)
            }
        }
        if parts.isEmpty {
            return nil
        }
        parts.append(String(source[start...]))
        return parts
    }

    private func splitTopLevel(_ source: String, operator target: String) -> [String]? {
        var result: [String] = []
        var start = source.startIndex
        var search = source.startIndex
        while search < source.endIndex {
            let suffix = String(source[search...])
            guard let range = topLevelRange(of: target, in: suffix) else { break }
            let offset = suffix.distance(from: suffix.startIndex, to: range.lowerBound)
            let lower = source.index(search, offsetBy: offset)
            let upper = source.index(lower, offsetBy: target.count)
            result.append(String(source[start ..< lower]))
            start = upper
            search = upper
        }
        guard !result.isEmpty else { return nil }
        result.append(String(source[start...]))
        return result
    }

    private func topLevelRange(of target: String, in source: String) -> Range<String.Index>? {
        var parenthesisDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var quoted = false
        var escaped = false
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
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
                if character == "[" {
                    bracketDepth += 1
                }
                if character == "]" {
                    bracketDepth -= 1
                }
                if parenthesisDepth == 0, braceDepth == 0, bracketDepth == 0,
                   source[index...].hasPrefix(target)
                {
                    return index ..< source.index(index, offsetBy: target.count)
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func topLevelIndex(of target: Character, in source: String) -> String.Index? {
        var parenthesisDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
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
            if character == "(", target != "(" {
                parenthesisDepth += 1
            }
            if character == ")", target != ")" {
                parenthesisDepth -= 1
            }
            if character == "{" {
                braceDepth += 1
            }
            if character == "}" {
                braceDepth -= 1
            }
            if character == "[" {
                bracketDepth += 1
            }
            if character == "]" {
                bracketDepth -= 1
            }
            if character == target, parenthesisDepth == 0, braceDepth == 0, bracketDepth == 0 {
                return index
            }
        }
        return nil
    }

    private func integer(_ arguments: [AkariValue], operation: (Int, Int) -> Int?) -> AkariValue? {
        guard arguments.count >= 2, let lhs = arguments[0].integerValue, let rhs = arguments[1].integerValue,
              let value = operation(lhs, rhs)
        else { return nil }
        return .integer(value)
    }

    public func save() throws {
        let transient = ["現在年", "現在月", "現在日", "現在時", "現在分", "現在秒"]
        let data = try JSONEncoder().encode(program.variables.filter { !transient.contains($0.key) })
        try FileManager.default.createDirectory(
            at: variableStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: variableStoreURL, options: .atomic)
    }

    private func substring(_ source: String, start: Int, length: Int?) -> String {
        let lower = source.index(source.startIndex, offsetBy: max(0, start), limitedBy: source.endIndex) ?? source.endIndex
        guard let length, length >= 0 else { return String(source[lower...]) }
        let upper = source.index(lower, offsetBy: length, limitedBy: source.endIndex) ?? source.endIndex
        return String(source[lower ..< upper])
    }

    private func innermostFunction(in source: String) -> (name: String, arguments: String, range: Range<String.Index>)? {
        var candidates: [(dollar: String.Index, name: String, opening: String.Index)] = []
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "$" {
                let nameStart = source.index(after: index)
                var cursor = nameStart
                while cursor < source.endIndex, source[cursor].isLetter || source[cursor].isNumber || source[cursor] == "_" {
                    cursor = source.index(after: cursor)
                }
                if cursor > nameStart, cursor < source.endIndex, source[cursor] == "(" {
                    candidates.append((index, String(source[nameStart ..< cursor]), cursor))
                }
            }
            index = source.index(after: index)
        }
        for candidate in candidates {
            guard let closing = closingParenthesis(in: source, opening: candidate.opening) else { continue }
            let arguments = String(source[source.index(after: candidate.opening) ..< closing])
            if innermostFunction(in: arguments) == nil {
                return (candidate.name, arguments, candidate.dollar ..< source.index(after: closing))
            }
        }
        return nil
    }

    private func closingParenthesis(in source: String, opening: String.Index) -> String.Index? {
        var depth = 0
        var index = opening
        while index < source.endIndex {
            if source[index] == "(" {
                depth += 1
            }
            if source[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func splitArguments(_ source: String) -> [String] {
        var result: [String] = []
        var start = source.startIndex
        var parenthesisDepth = 0
        var braceDepth = 0
        var quoted = false
        var escaped = false
        for index in source.indices {
            let character = source[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\", quoted {
                escaped = true
                continue
            }
            if character == "\"" {
                quoted.toggle()
                continue
            }
            guard !quoted else { continue }
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
            if character == ",", parenthesisDepth == 0, braceDepth == 0 {
                result.append(String(source[start ..< index]))
                start = source.index(after: index)
            }
        }
        result.append(String(source[start...]))
        return result
    }

    private func containsUnsupportedFunction(in source: String) -> Bool {
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "$" {
                let next = source.index(after: index)
                if next < source.endIndex, source[next].isLetter || source[next] == "_" {
                    return true
                }
            }
            index = source.index(after: index)
        }
        return false
    }

    private func replaceSurfaces(in source: String) -> String {
        var result = ""
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "(", let end = source[index...].firstIndex(of: ")"),
               let number = surfaceNumber(source[source.index(after: index) ..< end])
            {
                result += "\\s[\(number)]"
                index = source.index(after: end)
            } else {
                result.append(source[index])
                index = source.index(after: index)
            }
        }
        return result
    }

    private func surfaceNumber(_ source: Substring) -> Int? {
        let digits = source.map { character -> Character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1,
                  (0xFF10 ... 0xFF19).contains(scalar.value),
                  let normalized = UnicodeScalar(scalar.value - 0xFF10 + 0x30)
            else { return character }
            return Character(normalized)
        }
        return Int(String(digits))
    }
}

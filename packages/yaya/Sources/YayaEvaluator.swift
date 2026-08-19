import Foundation

public enum YayaValue: Codable, Equatable, Sendable {
    case void
    case integer(Int64)
    case floatingPoint(Double)
    case string(String)
    case array([YayaValue])

    public var stringValue: String {
        switch self {
        case .void: ""
        case let .integer(value): String(value)
        case let .floatingPoint(value): String(value)
        case let .string(value): value
        case let .array(values): values.map(\.stringValue).joined(separator: ",")
        }
    }

    public var isTruthy: Bool {
        switch self {
        case .void: false
        case let .integer(value): value != 0
        case let .floatingPoint(value): value != 0
        case let .string(value): !value.isEmpty
        case let .array(values): !values.isEmpty
        }
    }
}

public enum YayaRuntimeError: Error, Equatable, Sendable {
    case functionNotFound(String)
    case undefinedIdentifier(String)
    case invalidOperand(String)
    case invalidAssignment
    case indexOutOfBounds(Int)
    case unsupportedCall
    case recursionLimit
    case loopLimitExceeded
}

public struct YayaEvaluator {
    public static let supportedBuiltinNames: Set<String> = [
        "ARRAYDEDUP",
        "ARRAYSIZE",
        "ASORT",
        "ASEARCH",
        "ANY",
        "CHR",
        "CUTSPACE",
        "CVINT",
        "CVSTR",
        "ERASE",
        "ERASEVAR",
        "EVAL",
        "FATTRIB",
        "FCHARSET",
        "FCLOSE",
        "FDEL",
        "FENUM",
        "FOPEN",
        "FREAD",
        "FRENAME",
        "FSIZE",
        "FWRITE",
        "GETFUNCLIST",
        "GETERRORLOG",
        "GETSECCOUNT",
        "GETSETTING",
        "GETSTRBYTES",
        "GETTICKCOUNT",
        "GETTIME",
        "GETTYPE",
        "GETTYPEEX",
        "HAN2ZEN",
        "IARRAY",
        "INSERT",
        "ISINTSTR",
        "ISFUNC",
        "ISREALSTR",
        "ISVAR",
        "LOGGING",
        "RAND",
        "RE_GETSTR",
        "RE_MATCH",
        "REPLACE",
        "RE_REPLACE",
        "RE_SEARCH",
        "RE_SPLIT",
        "RESTOREVAR",
        "SAVEVAR",
        "SETSETTING",
        "SPLIT",
        "SPLITPATH",
        "STRFORM",
        "STRSTR",
        "STRLEN",
        "SUBSTR",
        "TOAUTO",
        "TOAUTOEX",
        "TOINT",
        "TOLOWER",
        "TOREAL",
        "TOSTR",
        "TOUPPER",
        "ZEN2HAN"
    ]

    public private(set) var globals: [String: YayaValue]
    private let functions: [String: YayaFunction]
    private let recursionLimit: Int
    private let loopLimit: Int
    private let randomIndex: (Int) -> Int
    private let environment: any YayaRuntimeEnvironment
    private var sequentialOffsets: [String: Int] = [:]
    private var nonoverlapRemaining: [String: [Int]] = [:]
    private var lastRegexCaptures: [String] = []

    public init(
        program: YayaProgram,
        globals: [String: YayaValue] = [:],
        environment: any YayaRuntimeEnvironment = YayaNativeRuntimeEnvironment(),
        recursionLimit: Int = 128,
        loopLimit: Int = 10000,
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0 ..< $0) }
    ) {
        self.globals = globals
        self.environment = environment
        var functions: [String: YayaFunction] = [:]
        for function in program.functions {
            if let existing = functions[function.name] {
                functions[function.name] = YayaFunction(
                    name: existing.name,
                    choiceType: existing.choiceType,
                    body: existing.body + function.body,
                    range: existing.range
                )
            } else {
                functions[function.name] = function
            }
        }
        self.functions = functions
        self.recursionLimit = recursionLimit
        self.loopLimit = loopLimit
        self.randomIndex = randomIndex
    }

    public mutating func call(_ name: String, arguments: [YayaValue] = []) throws -> YayaValue {
        try call(name, arguments: arguments, depth: 0)
    }

    private mutating func call(_ name: String, arguments: [YayaValue], depth: Int) throws -> YayaValue {
        try executeFunction(name, arguments: arguments, depth: depth).value
    }

    private mutating func executeFunction(
        _ name: String,
        arguments: [YayaValue],
        depth: Int
    ) throws -> FunctionExecutionResult {
        guard depth < recursionLimit else { throw YayaRuntimeError.recursionLimit }
        guard let function = functions[name] else { throw YayaRuntimeError.functionNotFound(name) }
        var locals: [String: YayaValue] = [
            "_argc": .integer(Int64(arguments.count)),
            "_argv": .array(arguments)
        ]
        let result = try evaluateSelection(
            function.body,
            choiceType: function.choiceType,
            key: "function:\(name)",
            locals: &locals,
            depth: depth
        )
        let updatedArguments = if case let .array(values) = locals["_argv"] {
            values
        } else {
            arguments
        }
        return FunctionExecutionResult(value: result.value, arguments: updatedArguments)
    }

    private mutating func evaluateSelection(
        _ statements: [YayaStatement],
        choiceType: YayaChoiceType,
        key: String,
        locals: inout [String: YayaValue],
        depth: Int,
        selectedIndex: Int? = nil
    ) throws -> EvaluationResult {
        var areas: [[YayaValue]] = [[]]
        for statement in statements {
            switch statement {
            case let .expression(expression):
                let value = try evaluate(expression, locals: &locals, depth: depth)
                if !isAssignment(expression), value != .void {
                    areas[areas.count - 1].append(value)
                }

            case let .parallel(expression, _):
                let value = try evaluate(expression, locals: &locals, depth: depth)
                if case let .array(values) = value {
                    areas[areas.count - 1].append(contentsOf: values)
                } else {
                    append(value, to: &areas)
                }

            case let .discard(expression, _):
                _ = try evaluate(expression, locals: &locals, depth: depth)

            case let .returnValue(expression, _):
                let value: YayaValue = if let expression {
                    try evaluate(expression, locals: &locals, depth: depth)
                } else if let selectedIndex {
                    select(areas, at: selectedIndex)
                } else {
                    select(areas, choiceType: choiceType, key: key)
                }
                return EvaluationResult(value: value, control: .returnValue)

            case .breakLoop:
                return EvaluationResult(value: select(areas, choiceType: choiceType, key: key), control: .breakLoop)

            case .continueLoop:
                return EvaluationResult(value: select(areas, choiceType: choiceType, key: key), control: .continueLoop)

            case let .block(body, range):
                let result = try evaluateSelection(
                    body,
                    choiceType: defaultBlockChoice(for: choiceType),
                    key: "\(key):block:\(range.start.offset)",
                    locals: &locals,
                    depth: depth
                )
                if result.control != .normal {
                    return result
                }
                append(result.value, to: &areas)

            case .choiceSeparator:
                areas.append([])

            case let .conditional(branches, elseBody, range):
                var selectedBody: [YayaStatement]?
                for branch in branches {
                    if try evaluate(branch.condition, locals: &locals, depth: depth).isTruthy {
                        selectedBody = branch.body
                        break
                    }
                }
                if selectedBody == nil {
                    selectedBody = elseBody
                }
                if let selectedBody {
                    let result = try evaluateSelection(
                        selectedBody,
                        choiceType: defaultBlockChoice(for: choiceType),
                        key: "\(key):if:\(range.start.offset)",
                        locals: &locals,
                        depth: depth
                    )
                    if result.control != .normal {
                        return result
                    }
                    append(result.value, to: &areas)
                }

            case let .caseSelection(subject, preamble, branches, othersBody, range):
                let subjectValue = try evaluate(subject, locals: &locals, depth: depth)
                let preambleResult = try evaluateSelection(
                    preamble,
                    choiceType: defaultBlockChoice(for: choiceType),
                    key: "\(key):case-preamble:\(range.start.offset)",
                    locals: &locals,
                    depth: depth
                )
                if preambleResult.control != .normal {
                    return preambleResult
                }
                append(preambleResult.value, to: &areas)
                var selectedBody = othersBody
                for branch in branches {
                    let matches = try evaluate(branch.matches, locals: &locals, depth: depth)
                    if caseMatches(subjectValue, matches: matches) {
                        selectedBody = branch.body
                        break
                    }
                }
                let result = try evaluateSelection(
                    selectedBody,
                    choiceType: defaultBlockChoice(for: choiceType),
                    key: "\(key):case:\(range.start.offset)",
                    locals: &locals,
                    depth: depth
                )
                if result.control != .normal {
                    return result
                }
                append(result.value, to: &areas)

            case let .switchSelection(indexExpression, body, range):
                let indexValue = try evaluate(indexExpression, locals: &locals, depth: depth)
                let index = try Int(integerValue(indexValue))
                let result = try evaluateSelection(
                    body,
                    choiceType: defaultBlockChoice(for: choiceType),
                    key: "\(key):switch:\(range.start.offset)",
                    locals: &locals,
                    depth: depth,
                    selectedIndex: index
                )
                if result.control != .normal {
                    return result
                }
                append(result.value, to: &areas)

            case let .whileLoop(condition, body, range):
                var iteration = 0
                while try evaluate(condition, locals: &locals, depth: depth).isTruthy {
                    try checkLoopLimit(&iteration)
                    let result = try evaluateSelection(
                        body,
                        choiceType: defaultBlockChoice(for: choiceType),
                        key: "\(key):while:\(range.start.offset)",
                        locals: &locals,
                        depth: depth
                    )
                    append(result.value, to: &areas)
                    if result.control == .returnValue {
                        return result
                    }
                    if result.control == .breakLoop {
                        break
                    }
                }

            case let .forLoop(initializer, condition, increment, body, range):
                _ = try evaluate(initializer, locals: &locals, depth: depth)
                var iteration = 0
                while try evaluate(condition, locals: &locals, depth: depth).isTruthy {
                    try checkLoopLimit(&iteration)
                    let result = try evaluateSelection(
                        body,
                        choiceType: defaultBlockChoice(for: choiceType),
                        key: "\(key):for:\(range.start.offset)",
                        locals: &locals,
                        depth: depth
                    )
                    append(result.value, to: &areas)
                    if result.control == .returnValue {
                        return result
                    }
                    if result.control == .breakLoop {
                        break
                    }
                    _ = try evaluate(increment, locals: &locals, depth: depth)
                }

            case let .forEach(collection, variable, body, range):
                let collectionValue = try evaluate(collection, locals: &locals, depth: depth)
                let values = foreachValues(collectionValue)
                var iteration = 0
                for value in values {
                    try checkLoopLimit(&iteration)
                    setVariable(variable, value: value, locals: &locals)
                    let result = try evaluateSelection(
                        body,
                        choiceType: defaultBlockChoice(for: choiceType),
                        key: "\(key):foreach:\(range.start.offset)",
                        locals: &locals,
                        depth: depth
                    )
                    append(result.value, to: &areas)
                    if result.control == .returnValue {
                        return result
                    }
                    if result.control == .breakLoop {
                        break
                    }
                }
            }
        }
        let value = if let selectedIndex {
            select(areas, at: selectedIndex)
        } else {
            select(areas, choiceType: choiceType, key: key)
        }
        return EvaluationResult(value: value, control: .normal)
    }

    private mutating func evaluate(
        _ expression: YayaExpression,
        locals: inout [String: YayaValue],
        depth: Int
    ) throws -> YayaValue {
        switch expression {
        case let .literal(literal, _):
            return switch literal {
            case let .integer(value): .integer(value)
            case let .floatingPoint(value): .floatingPoint(value)
            case let .string(value): try .string(expandEmbeddedExpressions(value, locals: &locals, depth: depth))
            }

        case let .identifier(name, _):
            if let value = locals[name] ?? globals[name] {
                return value
            }
            if functions[name] != nil {
                return try call(name, arguments: [], depth: depth + 1)
            }
            if let builtin = try evaluateBuiltin(name, arguments: [], locals: &locals, depth: depth) {
                return builtin
            }
            return .void

        case let .unary(symbol, operand, _):
            if symbol == "&" {
                let reference = try resolveLValue(operand, locals: &locals, depth: depth)
                return try read(reference, locals: &locals)
            }
            if symbol == "++" || symbol == "--" {
                let current = try evaluate(operand, locals: &locals, depth: depth)
                let delta: YayaValue = .integer(symbol == "++" ? 1 : -1)
                let value = try evaluateBinary(current, operator: "+", delta)
                return try assign(operand, operator: "=", value: value, locals: &locals, depth: depth)
            }
            let value = try evaluate(operand, locals: &locals, depth: depth)
            return try evaluateUnary(symbol, value: value)

        case let .binary(left, symbol, right, _):
            if assignmentOperators.contains(symbol) {
                let value = try evaluate(right, locals: &locals, depth: depth)
                return try assign(left, operator: symbol, value: value, locals: &locals, depth: depth)
            }
            if symbol == "&&" {
                let leftValue = try evaluate(left, locals: &locals, depth: depth)
                return leftValue.isTruthy ? try evaluate(right, locals: &locals, depth: depth) : .integer(0)
            }
            if symbol == "||" {
                let leftValue = try evaluate(left, locals: &locals, depth: depth)
                return leftValue.isTruthy ? .integer(1) : try evaluate(right, locals: &locals, depth: depth)
            }
            let leftValue = try evaluate(left, locals: &locals, depth: depth)
            let rightValue = try evaluate(right, locals: &locals, depth: depth)
            return try evaluateBinary(leftValue, operator: symbol, rightValue)

        case let .call(callee, arguments, _):
            guard case let .identifier(name, _) = callee else { throw YayaRuntimeError.unsupportedCall }
            if functions[name] != nil {
                var values: [YayaValue] = []
                var references: [Int: YayaLValue] = [:]
                for (index, argument) in arguments.enumerated() {
                    if case let .unary("&", operand, _) = argument {
                        let reference = try resolveLValue(operand, locals: &locals, depth: depth)
                        references[index] = reference
                        try values.append(read(reference, locals: &locals))
                    } else {
                        try values.append(evaluate(argument, locals: &locals, depth: depth))
                    }
                }
                let result = try executeFunction(name, arguments: values, depth: depth + 1)
                for (index, reference) in references where index < result.arguments.count {
                    try write(reference, value: result.arguments[index], locals: &locals)
                }
                return result.value
            }
            let values = try arguments.map { try evaluate($0, locals: &locals, depth: depth) }
            if let builtin = try evaluateBuiltin(
                name,
                arguments: values,
                locals: &locals,
                depth: depth
            ) {
                return builtin
            }
            throw YayaRuntimeError.functionNotFound(name)

        case let .subscriptAccess(base, index, _):
            let baseValue = try evaluate(base, locals: &locals, depth: depth)
            let indexValue = try evaluate(index, locals: &locals, depth: depth)
            let integer = try integerValue(indexValue)
            guard integer >= 0 else { return .void }
            switch baseValue {
            case let .array(values):
                guard integer < values.count else { return .void }
                return values[Int(integer)]
            case let .string(value):
                guard integer < value.count else { return .void }
                return .string(String(value[value.index(value.startIndex, offsetBy: Int(integer))]))
            default:
                throw YayaRuntimeError.invalidOperand("[]")
            }
        }
    }

    private mutating func assign(
        _ target: YayaExpression,
        operator symbol: String,
        value: YayaValue,
        locals: inout [String: YayaValue],
        depth: Int
    ) throws -> YayaValue {
        let reference = try resolveLValue(target, locals: &locals, depth: depth)
        let normalized = symbol.replacingOccurrences(of: ":", with: "")
        let assigned: YayaValue
        if normalized == "=" {
            assigned = value
        } else {
            let current = try read(reference, locals: &locals)
            assigned = try evaluateBinary(current, operator: String(normalized.dropLast()), value)
        }
        try write(reference, value: assigned, locals: &locals)
        return assigned
    }

    private func evaluateUnary(_ symbol: String, value: YayaValue) throws -> YayaValue {
        switch symbol {
        case "!": .integer(value.isTruthy ? 0 : 1)
        case "+": value
        case "-":
            switch value {
            case let .integer(number): .integer(-number)
            case let .floatingPoint(number): .floatingPoint(-number)
            default: throw YayaRuntimeError.invalidOperand(symbol)
            }
        default: throw YayaRuntimeError.invalidOperand(symbol)
        }
    }

    private func evaluateBinary(_ left: YayaValue, operator symbol: String, _ right: YayaValue) throws -> YayaValue {
        switch symbol {
        case "+":
            if case let .string(value) = left {
                return .string(value + right.stringValue)
            }
            if case .string = right {
                return .string(left.stringValue + right.stringValue)
            }
            return try numeric(left, right, integer: +, floatingPoint: +)
        case "-": return try numeric(left, right, integer: -, floatingPoint: -)
        case "*": return try numeric(left, right, integer: *, floatingPoint: *)
        case "/":
            let divisor = try doubleValue(right)
            guard divisor != 0 else { throw YayaRuntimeError.invalidOperand("division by zero") }
            return try .floatingPoint(doubleValue(left) / divisor)
        case "%":
            let divisor = try integerValue(right)
            guard divisor != 0 else { throw YayaRuntimeError.invalidOperand("division by zero") }
            return try .integer(integerValue(left) % divisor)
        case "==": return .integer(left == right ? 1 : 0)
        case "!=": return .integer(left != right ? 1 : 0)
        case ">": return try .integer(doubleValue(left) > doubleValue(right) ? 1 : 0)
        case "<": return try .integer(doubleValue(left) < doubleValue(right) ? 1 : 0)
        case ">=": return try .integer(doubleValue(left) >= doubleValue(right) ? 1 : 0)
        case "<=": return try .integer(doubleValue(left) <= doubleValue(right) ? 1 : 0)
        case "_in_": return .integer(contains(right, value: left) ? 1 : 0)
        case "!_in_": return .integer(contains(right, value: left) ? 0 : 1)
        case ",":
            let leftValues = if case let .array(existing) = left {
                existing
            } else {
                [left]
            }
            let rightValues = if case let .array(existing) = right {
                existing
            } else {
                [right]
            }
            let values = leftValues + rightValues
            return .array(values)
        default: throw YayaRuntimeError.invalidOperand(symbol)
        }
    }

    private mutating func evaluateBuiltin(
        _ name: String,
        arguments: [YayaValue],
        locals: inout [String: YayaValue],
        depth: Int
    ) throws -> YayaValue? {
        let normalizedName = name.uppercased()
        guard Self.supportedBuiltinNames.contains(normalizedName) else { return nil }
        switch normalizedName {
        case "STRLEN":
            guard let first = arguments.first else { return .integer(0) }
            return .integer(Int64(first.stringValue.count))
        case "TOINT", "CVINT":
            guard let first = arguments.first else { return .integer(0) }
            return try .integer(integerValue(first))
        case "TOREAL":
            guard let first = arguments.first else { return .floatingPoint(0) }
            return try .floatingPoint(doubleValue(first))
        case "TOSTR", "CVSTR":
            return .string(arguments.map(stringForConversion).joined())
        case "TOAUTO", "TOAUTOEX":
            guard let first = arguments.first else { return .void }
            guard case let .string(value) = first else { return first }
            if let integer = Int64(value) {
                return .integer(integer)
            }
            if let real = Double(value), value.contains(".") {
                return .floatingPoint(real)
            }
            return .string(value)
        case "GETTYPE":
            return .integer(Int64(typeCode(arguments.first ?? .void)))
        case "ARRAYSIZE":
            guard let first = arguments.first else { return .integer(0) }
            guard case let .array(values) = first else { return .integer(0) }
            return .integer(Int64(values.count))
        case "IARRAY":
            return .array(arguments.flatMap(flattenedArrayArgument))
        case "ARRAYDEDUP":
            var result: [YayaValue] = []
            for value in arguments.flatMap(flattenedArrayArgument) where !result.contains(value) {
                result.append(value)
            }
            return .array(result)
        case "ANY":
            let candidates: [YayaValue] = if arguments.count == 1, case let .string(value) = arguments[0] {
                value.split(separator: "\u{1}", omittingEmptySubsequences: false)
                    .map { .string(String($0)) }
            } else {
                arguments.flatMap(flattenedArrayArgument)
            }
            guard !candidates.isEmpty else { return .void }
            return candidates[normalizedRandomIndex(count: candidates.count)]
        case "ASORT":
            guard let option = arguments.first?.stringValue.lowercased() else { return .array([]) }
            let values = arguments.dropFirst().flatMap(flattenedArrayArgument)
            let descending = option.contains("des")
            let indexed = values.enumerated().sorted { left, right in
                let comparison: ComparisonResult
                if option.contains("int") || option.contains("double") {
                    let lhs = (try? doubleValue(left.element)) ?? 0
                    let rhs = (try? doubleValue(right.element)) ?? 0
                    comparison = lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
                } else if option.contains("len") {
                    let lhs = left.element.stringValue.count
                    let rhs = right.element.stringValue.count
                    comparison = lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
                } else if option.contains("nocase") || option.contains("insensitive") {
                    comparison = left.element.stringValue.localizedCaseInsensitiveCompare(right.element.stringValue)
                } else {
                    comparison = left.element.stringValue.compare(right.element.stringValue)
                }
                return descending ? comparison == .orderedDescending : comparison == .orderedAscending
            }
            if option.contains("index") {
                return .array(indexed.map { .integer(Int64($0.offset)) })
            }
            return .array(indexed.map(\.element))
        case "ASEARCH":
            guard let key = arguments.first else { return .integer(-1) }
            let candidates = arguments.dropFirst().flatMap(flattenedArrayArgument)
            return .integer(Int64(candidates.firstIndex(of: key) ?? -1))
        case "ISVAR":
            guard let name = arguments.first?.stringValue else { return .integer(0) }
            return .integer(locals[name] != nil || globals[name] != nil ? 1 : 0)
        case "GETTYPEEX":
            guard let name = arguments.first?.stringValue else { return .integer(0) }
            return .integer(Int64(typeCode(locals[name] ?? globals[name] ?? .void)))
        case "GETSETTING":
            guard let name = arguments.first?.stringValue else { return .void }
            return environment.setting(named: name) ?? .void
        case "SETSETTING":
            guard arguments.count >= 2 else { return .integer(0) }
            return .integer(environment.setSetting(arguments[1], named: arguments[0].stringValue) ? 1 : 0)
        case "GETFUNCLIST":
            let prefix = arguments.first?.stringValue ?? ""
            return .array(functions.keys.filter { prefix.isEmpty || $0.hasPrefix(prefix) }
                .sorted().map(YayaValue.string))
        case "LOGGING":
            environment.log(arguments.map(\.stringValue).joined())
            return .void
        case "GETERRORLOG":
            return .string(environment.errorLog())
        case "ERASEVAR":
            for value in arguments.flatMap(flattenedArrayArgument) {
                let name = value.stringValue
                locals.removeValue(forKey: name)
                globals.removeValue(forKey: name)
            }
            return .void
        case "SAVEVAR":
            try environment.saveVariables(globals, path: arguments.first?.stringValue)
            return .void
        case "RESTOREVAR":
            let restored = try environment.restoreVariables(path: arguments.first?.stringValue)
            globals.merge(restored) { _, restored in restored }
            return .void
        case "FSIZE":
            guard let path = arguments.first?.stringValue else { return .integer(-1) }
            return try .integer(environment.fileSize(path: path))
        case "FCHARSET":
            guard let value = arguments.first else { return .void }
            let encoding: YayaTextEncoding = if case let .string(name) = value {
                YayaTextEncoding(name: name) ?? .utf8
            } else {
                try integerValue(value) == 0 ? .shiftJIS : .utf8
            }
            environment.setFileEncoding(encoding)
            return .void
        case "FOPEN":
            guard arguments.count >= 2 else { return .integer(0) }
            return try .integer(Int64(environment.openFile(
                path: arguments[0].stringValue,
                mode: arguments[1].stringValue
            )))
        case "FCLOSE":
            guard let path = arguments.first?.stringValue else { return .void }
            _ = try environment.closeFile(path: path)
            return .void
        case "FREAD":
            guard let path = arguments.first?.stringValue else { return .integer(-1) }
            guard let line = try environment.readLine(path: path) else { return .integer(-1) }
            return .string(line)
        case "FWRITE":
            guard arguments.count >= 2 else { return .void }
            _ = try environment.writeLine(arguments[1].stringValue, path: arguments[0].stringValue)
            return .void
        case "FDEL":
            guard let path = arguments.first?.stringValue else { return .integer(0) }
            return try .integer(environment.deleteFile(path: path) ? 1 : 0)
        case "FRENAME":
            guard arguments.count >= 2 else { return .integer(0) }
            return try .integer(environment.renameFile(
                from: arguments[0].stringValue,
                to: arguments[1].stringValue
            ) ? 1 : 0)
        case "FENUM":
            guard let path = arguments.first?.stringValue else { return .void }
            let delimiter = arguments.dropFirst().first?.stringValue ?? "\u{1}"
            return try .string(environment.enumerateFiles(path: path).joined(separator: delimiter))
        case "FATTRIB":
            guard let path = arguments.first?.stringValue,
                  let attributes = try environment.fileAttributes(path: path)
            else { return .integer(-1) }
            return .array(attributes.map(YayaValue.integer))
        case "ISFUNC":
            guard let name = arguments.first?.stringValue else { return .integer(0) }
            return .integer(functions[name] != nil ? 1 : 0)
        case "RAND":
            let count = try arguments.first.map(integerValue) ?? 100
            guard count > 0 else { return .integer(0) }
            return .integer(Int64(normalizedRandomIndex(count: Int(count))))
        case "EVAL":
            guard let source = arguments.first?.stringValue, !source.isEmpty else { return .void }
            if arguments.count > 1, functions[source] != nil {
                return try call(source, arguments: Array(arguments.dropFirst()), depth: depth + 1)
            }
            let expression = try YayaExpressionParser.parse(source: source)
            return try evaluate(expression, locals: &locals, depth: depth + 1)
        case "STRSTR":
            guard arguments.count >= 2 else { return .integer(-1) }
            let source = Array(arguments[0].stringValue)
            let target = Array(arguments[1].stringValue)
            let start = try max(0, arguments.dropFirst(2).first.map { try Int(integerValue($0)) } ?? 0)
            guard start <= source.count, !target.isEmpty, target.count <= source.count - start else {
                return .integer(-1)
            }
            let index = (start ... source.count - target.count).first {
                Array(source[$0 ..< $0 + target.count]) == target
            }
            return .integer(Int64(index ?? -1))
        case "REPLACE":
            guard arguments.count >= 3 else { return .void }
            let limit = try arguments.dropFirst(3).first.map { try Int(integerValue($0)) } ?? 0
            return .string(replacing(
                arguments[0].stringValue,
                target: arguments[1].stringValue,
                replacement: arguments[2].stringValue,
                limit: limit
            ))
        case "SUBSTR":
            guard arguments.count >= 3 else { return .void }
            return try .string(substring(
                arguments[0].stringValue,
                position: Int(integerValue(arguments[1])),
                length: Int(integerValue(arguments[2]))
            ))
        case "ERASE":
            guard arguments.count >= 3 else { return .void }
            return try .string(erasing(
                arguments[0].stringValue,
                position: Int(integerValue(arguments[1])),
                length: Int(integerValue(arguments[2]))
            ))
        case "INSERT":
            guard arguments.count >= 3 else { return .void }
            var characters = Array(arguments[0].stringValue)
            let position = try max(0, min(characters.count, Int(integerValue(arguments[1]))))
            characters.insert(contentsOf: arguments[2].stringValue, at: position)
            return .string(String(characters))
        case "CUTSPACE":
            return .string(arguments.first?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        case "CHR":
            let scalars = try arguments.compactMap { value -> Unicode.Scalar? in
                try Unicode.Scalar(Int(integerValue(value)))
            }
            return .string(String(String.UnicodeScalarView(scalars)))
        case "TOLOWER":
            return .string(arguments.first?.stringValue.lowercased() ?? "")
        case "TOUPPER":
            return .string(arguments.first?.stringValue.uppercased() ?? "")
        case "ZEN2HAN":
            guard let source = arguments.first?.stringValue else { return .void }
            return .string(convertWidth(
                source,
                options: arguments.dropFirst().first?.stringValue,
                reverse: false
            ))
        case "HAN2ZEN":
            guard let source = arguments.first?.stringValue else { return .void }
            return .string(convertWidth(
                source,
                options: arguments.dropFirst().first?.stringValue,
                reverse: true
            ))
        case "SPLIT":
            guard arguments.count >= 2 else { return .array([]) }
            let limit = try arguments.dropFirst(2).first.map { try Int(integerValue($0)) } ?? 0
            return .array(split(arguments[0].stringValue, separator: arguments[1].stringValue, limit: limit)
                .map(YayaValue.string))
        case "GETSTRBYTES":
            return .integer(Int64(arguments.first?.stringValue.lengthOfBytes(using: .utf8) ?? 0))
        case "ISINTSTR":
            guard let value = arguments.first?.stringValue else { return .integer(0) }
            return .integer(Int64(value) == nil ? 0 : 1)
        case "ISREALSTR":
            guard let value = arguments.first?.stringValue else { return .integer(0) }
            return .integer(Double(value) == nil ? 0 : 1)
        case "RE_SEARCH", "RE_MATCH":
            guard arguments.count >= 2 else { return .integer(0) }
            let source = arguments[0].stringValue
            guard let regex = try? NSRegularExpression(pattern: arguments[1].stringValue) else {
                lastRegexCaptures = []
                return .integer(0)
            }
            let fullRange = NSRange(source.startIndex..., in: source)
            guard let match = regex.firstMatch(in: source, range: fullRange),
                  normalizedName == "RE_SEARCH" || match.range == fullRange
            else {
                lastRegexCaptures = []
                return .integer(0)
            }
            lastRegexCaptures = (0 ..< match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: source) else { return "" }
                return String(source[range])
            }
            return .integer(1)
        case "RE_GETSTR":
            let index = try arguments.first.map { try Int(integerValue($0)) } ?? 0
            guard index >= 0, index < lastRegexCaptures.count else { return .string("") }
            return .string(lastRegexCaptures[index])
        case "RE_REPLACE":
            guard arguments.count >= 3 else { return .string(arguments.first?.stringValue ?? "") }
            let limit = try arguments.dropFirst(3).first.map { try Int(integerValue($0)) } ?? 0
            return .string(regexReplacing(
                arguments[0].stringValue,
                pattern: arguments[1].stringValue,
                replacement: arguments[2].stringValue,
                limit: limit
            ))
        case "RE_SPLIT":
            guard arguments.count >= 2 else { return .array([]) }
            let limit = try arguments.dropFirst(2).first.map { try Int(integerValue($0)) } ?? 0
            return .array(regexSplit(
                arguments[0].stringValue,
                pattern: arguments[1].stringValue,
                limit: limit
            ).map(YayaValue.string))
        case "STRFORM":
            guard let format = arguments.first?.stringValue else { return .void }
            return .string(formatString(format, values: Array(arguments.dropFirst())))
        case "SPLITPATH":
            guard let path = arguments.first?.stringValue else { return .array([]) }
            return .array(splitPath(path).map(YayaValue.string))
        case "GETTIME":
            let date = if let first = arguments.first {
                try Date(timeIntervalSince1970: TimeInterval(integerValue(first)))
            } else {
                environment.currentDate()
            }
            return .array(timeComponents(for: date))
        case "GETSECCOUNT":
            if arguments.isEmpty {
                return .integer(Int64(environment.currentDate().timeIntervalSince1970))
            }
            return try .integer(secondsSinceEpoch(arguments))
        case "GETTICKCOUNT":
            if let first = arguments.first, try integerValue(first) != 0 {
                return .integer(0)
            }
            return .integer(environment.uptimeMilliseconds())
        default:
            preconditionFailure("Every supported builtin must have an evaluator")
        }
    }

    private func stringForConversion(_ value: YayaValue) -> String {
        if case let .array(values) = value {
            return values.map(\.stringValue).joined(separator: "\u{1}")
        }
        return value.stringValue
    }

    private func typeCode(_ value: YayaValue) -> Int {
        switch value {
        case .void: 0
        case .integer: 1
        case .floatingPoint: 2
        case .string: 3
        case let .array(values): values.count == 1 ? typeCode(values[0]) : 4
        }
    }

    private func flattenedArrayArgument(_ value: YayaValue) -> [YayaValue] {
        if case let .array(values) = value {
            return values
        }
        return [value]
    }

    private func replacing(_ source: String, target: String, replacement: String, limit: Int) -> String {
        guard !target.isEmpty else { return source }
        var result = source
        var searchStart = result.startIndex
        var replacements = 0
        while limit <= 0 || replacements < limit,
              let range = result.range(of: target, range: searchStart ..< result.endIndex)
        {
            result.replaceSubrange(range, with: replacement)
            searchStart = result.index(range.lowerBound, offsetBy: replacement.count)
            replacements += 1
        }
        return result
    }

    private func substring(_ source: String, position: Int, length: Int) throws -> String {
        let range = normalizedRange(count: source.count, position: position, length: length)
        guard let range else { return "" }
        return String(Array(source)[range])
    }

    private func erasing(_ source: String, position: Int, length: Int) throws -> String {
        let range = normalizedRange(count: source.count, position: position, length: length)
        guard let range else { return "" }
        var characters = Array(source)
        characters.removeSubrange(range)
        return String(characters)
    }

    private func normalizedRange(count: Int, position: Int, length: Int) -> Range<Int>? {
        var position = position
        var length = length
        if position < 0 {
            position += count
            if position < 0 {
                length += position
                position = 0
            }
        }
        guard position < count, length > 0 else { return nil }
        return position ..< min(count, position + length)
    }

    private func split(_ source: String, separator: String, limit: Int) -> [String] {
        guard limit != 1, !separator.isEmpty else { return [source] }
        var result: [String] = []
        var remainder = source[...]
        while limit <= 0 || result.count < limit - 1,
              let range = remainder.range(of: separator)
        {
            result.append(String(remainder[..<range.lowerBound]))
            remainder = remainder[range.upperBound...]
        }
        result.append(String(remainder))
        return result
    }

    private func regexReplacing(_ source: String, pattern: String, replacement: String, limit: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let selected = limit > 0 ? Array(matches.prefix(limit)) : matches
        var result = source
        for match in selected.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let template = regex.replacementString(for: match, in: source, offset: 0, template: replacement)
            result.replaceSubrange(range, with: template)
        }
        return result
    }

    private func regexSplit(_ source: String, pattern: String, limit: Int) -> [String] {
        guard limit != 1,
              let regex = try? NSRegularExpression(pattern: pattern)
        else { return [source] }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let selected = limit > 0 ? Array(matches.prefix(limit - 1)) : matches
        var result: [String] = []
        var start = source.startIndex
        for match in selected {
            guard let range = Range(match.range, in: source) else { continue }
            result.append(String(source[start ..< range.lowerBound]))
            start = range.upperBound
        }
        result.append(String(source[start...]))
        return result
    }

    private func formatString(_ format: String, values: [YayaValue]) -> String {
        let pattern = #"\$([-+0 #]?)(\d*)(?:\.(\d+))?([diuoxXfFeEgGsc])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return format }
        let matches = regex.matches(in: format, range: NSRange(format.startIndex..., in: format))
        var result = format
        for (argumentIndex, match) in matches.enumerated().reversed() where argumentIndex < values.count {
            guard let range = Range(match.range, in: format) else { continue }
            let flag = capture(match, index: 1, in: format)
            let width = Int(capture(match, index: 2, in: format)) ?? 0
            let type = capture(match, index: 4, in: format)
            let value = values[argumentIndex]
            let replacement: String
            switch type {
            case "d", "i", "u":
                let number = (try? integerValue(value)) ?? 0
                let sign = number < 0 ? "-" : (flag == "+" ? "+" : "")
                let digits = String(abs(number))
                let paddingCharacter = flag == "0" ? "0" : " "
                let padding = String(repeating: paddingCharacter, count: max(0, width - sign.count - digits.count))
                replacement = sign + padding + digits
            case "x", "X", "o":
                let number = UInt64(bitPattern: (try? integerValue(value)) ?? 0)
                let radix = type == "o" ? 8 : 16
                var digits = String(number, radix: radix)
                if type == "X" {
                    digits = digits.uppercased()
                }
                replacement = String(repeating: flag == "0" ? "0" : " ", count: max(0, width - digits.count)) + digits
            case "c":
                let scalar = Unicode.Scalar(Int((try? integerValue(value)) ?? 0))
                replacement = scalar.map(String.init) ?? ""
            default:
                replacement = value.stringValue
            }
            guard let resultRange = result.range(of: String(format[range]), options: .backwards) else { continue }
            result.replaceSubrange(resultRange, with: replacement)
        }
        return result
    }

    private func capture(_ match: NSTextCheckingResult, index: Int, in source: String) -> String {
        guard let range = Range(match.range(at: index), in: source) else { return "" }
        return String(source[range])
    }

    private func convertWidth(_ source: String, options: String?, reverse: Bool) -> String {
        guard let options else {
            return source.applyingTransform(.fullwidthToHalfwidth, reverse: reverse) ?? source
        }
        let normalizedOptions = options.lowercased()
        let convertsNumber = normalizedOptions.contains("num")
        let convertsAlphabet = normalizedOptions.contains("alpha")
        let convertsSymbol = normalizedOptions.contains("sym")
        let convertsKana = normalizedOptions.contains("kana")
        var result = ""
        for character in source {
            let text = String(character)
            let scalar = character.unicodeScalars.first?.value ?? 0
            let isNumber = (0x30 ... 0x39).contains(scalar) || (0xFF10 ... 0xFF19).contains(scalar)
            let isAlphabet = (0x41 ... 0x5A).contains(scalar) || (0x61 ... 0x7A).contains(scalar) ||
                (0xFF21 ... 0xFF3A).contains(scalar) || (0xFF41 ... 0xFF5A).contains(scalar)
            let isKana = (0x3040 ... 0x30FF).contains(scalar) || (0xFF61 ... 0xFF9F).contains(scalar)
            let shouldConvert = (convertsNumber && isNumber) || (convertsAlphabet && isAlphabet) ||
                (convertsKana && isKana) || (convertsSymbol && !isNumber && !isAlphabet && !isKana)
            if shouldConvert {
                result += text.applyingTransform(.fullwidthToHalfwidth, reverse: reverse) ?? text
            } else {
                result += text
            }
        }
        return result.precomposedStringWithCanonicalMapping
    }

    private func splitPath(_ source: String) -> [String] {
        let path = source.replacingOccurrences(of: "\\", with: "/")
        let directory: String
        let fileName: String
        if let slash = path.lastIndex(of: "/") {
            directory = String(path[...slash])
            fileName = String(path[path.index(after: slash)...])
        } else {
            directory = ""
            fileName = path
        }
        if let period = fileName.lastIndex(of: ".") {
            return ["", directory, String(fileName[..<period]), String(fileName[fileName.index(after: period)...])]
        }
        return ["", directory, fileName, ""]
    }

    private func timeComponents(for date: Date) -> [YayaValue] {
        let calendar = environment.calendar
        let components = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute, .second],
            from: date
        )
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let isDaylightSavingTime = calendar.timeZone.isDaylightSavingTime(for: date) ? 1 : 0
        return [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            (components.weekday ?? 1) - 1,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            dayOfYear - 1,
            isDaylightSavingTime
        ].map { .integer(Int64($0)) }
    }

    private func secondsSinceEpoch(_ arguments: [YayaValue]) throws -> Int64 {
        if arguments.count == 1, case let .string(value) = arguments[0] {
            let formats = [
                "EEE, dd MMM yyyy HH:mm:ss zzz",
                "EEEE, dd-MMM-yy HH:mm:ss zzz",
                "EEE MMM d HH:mm:ss yyyy"
            ]
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                if let date = formatter.date(from: value) {
                    return Int64(date.timeIntervalSince1970)
                }
            }
        }

        var components = environment.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: environment.currentDate()
        )
        let integers = try arguments.map { try Int(integerValue($0)) }
        if integers.indices.contains(0) {
            components.year = integers[0]
        }
        if integers.indices.contains(1) {
            components.month = integers[1]
        }
        if integers.indices.contains(2) {
            components.day = integers[2]
        }
        if integers.indices.contains(4) {
            components.hour = integers[4]
        }
        if integers.indices.contains(5) {
            components.minute = integers[5]
        }
        if integers.indices.contains(6) {
            components.second = integers[6]
        }
        guard let date = environment.calendar.date(from: components) else { return 0 }
        return Int64(date.timeIntervalSince1970)
    }

    private mutating func select(
        _ areas: [[YayaValue]],
        choiceType: YayaChoiceType,
        key: String
    ) -> YayaValue {
        let populated = areas.filter { !$0.isEmpty }
        guard !populated.isEmpty else { return .void }

        switch choiceType.output {
        case .void:
            return .void
        case .all:
            return .string(populated.flatMap(\.self).map(\.stringValue).joined())
        case .last:
            return populated.last?.last ?? .void
        case .pickOne, .pool, .melt:
            break
        }

        if choiceType.selection == .array {
            let values = populated.flatMap { area in
                area.flatMap { value -> [YayaValue] in
                    if case let .array(elements) = value {
                        return elements
                    }
                    return [value]
                }
            }
            return .array(values)
        }

        let selected = populated.enumerated().compactMap { areaIndex, values in
            choose(values, mode: choiceType.selection, key: "\(key):area:\(areaIndex)")
        }
        guard selected.count > 1 else { return selected.first ?? .void }
        return .string(selected.map(\.stringValue).joined())
    }

    private func select(_ areas: [[YayaValue]], at index: Int) -> YayaValue {
        let selected = areas.map { values in
            guard index >= 0, index < values.count else { return YayaValue.void }
            return values[index]
        }
        guard selected.count > 1 else { return selected.first ?? .void }
        return .string(selected.map(\.stringValue).joined())
    }

    private mutating func choose(_ values: [YayaValue], mode: YayaSelectionMode, key: String) -> YayaValue? {
        guard !values.isEmpty else { return nil }
        let index: Int
        switch mode {
        case .random, .array:
            index = normalizedRandomIndex(count: values.count)
        case .sequential:
            index = sequentialOffsets[key, default: 0] % values.count
            sequentialOffsets[key] = index + 1
        case .nonoverlap:
            var remaining = nonoverlapRemaining[key] ?? []
            if remaining.isEmpty {
                remaining = Array(values.indices)
            }
            let remainingIndex = normalizedRandomIndex(count: remaining.count)
            index = remaining.remove(at: remainingIndex)
            nonoverlapRemaining[key] = remaining
        }
        return values[index]
    }

    private func normalizedRandomIndex(count: Int) -> Int {
        guard count > 1 else { return 0 }
        let candidate = randomIndex(count)
        return ((candidate % count) + count) % count
    }

    private func defaultBlockChoice(for parent: YayaChoiceType) -> YayaChoiceType {
        let selection: YayaSelectionMode = parent.selection == .array ? .array : .random
        let output: YayaOutputMode = switch parent.output {
        case .pool, .melt, .pickOne: parent.output
        case .void, .all, .last: parent.output
        }
        return YayaChoiceType(selection: selection, output: output)
    }

    private func append(_ value: YayaValue, to areas: inout [[YayaValue]]) {
        guard value != .void else { return }
        areas[areas.count - 1].append(value)
    }

    private func caseMatches(_ subject: YayaValue, matches: YayaValue) -> Bool {
        if case let .array(values) = matches {
            return values.contains(subject)
        }
        return subject == matches
    }

    private func isAssignment(_ expression: YayaExpression) -> Bool {
        switch expression {
        case let .binary(_, symbol, _, _):
            assignmentOperators.contains(symbol)
        case let .unary(symbol, _, _):
            symbol == "++" || symbol == "--"
        default:
            false
        }
    }

    private func checkLoopLimit(_ iteration: inout Int) throws {
        guard loopLimit == 0 || iteration < loopLimit else {
            throw YayaRuntimeError.loopLimitExceeded
        }
        iteration += 1
    }

    private func foreachValues(_ value: YayaValue) -> [YayaValue] {
        switch value {
        case let .array(values):
            values
        case let .string(value):
            value.split(separator: "\u{1}", omittingEmptySubsequences: false).map { .string(String($0)) }
        default:
            []
        }
    }

    private mutating func expandEmbeddedExpressions(
        _ source: String,
        locals: inout [String: YayaValue],
        depth: Int
    ) throws -> String {
        guard source.contains("%(") else { return source }
        let characters = Array(source)
        var result = ""
        var index = 0

        while index < characters.count {
            guard characters[index] == "%", index + 1 < characters.count, characters[index + 1] == "(" else {
                result.append(characters[index])
                index += 1
                continue
            }

            let expressionStart = index + 2
            var cursor = expressionStart
            var parenthesisDepth = 1
            var quote: Character?
            while cursor < characters.count {
                let character = characters[cursor]
                if let activeQuote = quote {
                    if character == activeQuote {
                        quote = nil
                    }
                } else if character == "'" || character == "\"" {
                    quote = character
                } else if character == "(" {
                    parenthesisDepth += 1
                } else if character == ")" {
                    parenthesisDepth -= 1
                    if parenthesisDepth == 0 {
                        break
                    }
                }
                cursor += 1
            }
            guard parenthesisDepth == 0 else {
                throw YayaRuntimeError.invalidOperand("unterminated embedded expression")
            }

            let expressionSource = String(characters[expressionStart ..< cursor])
            let expression = try YayaExpressionParser.parse(source: expressionSource)
            let value = try evaluate(expression, locals: &locals, depth: depth)
            result += value.stringValue
            index = cursor + 1
        }
        return result
    }

    private mutating func setVariable(_ name: String, value: YayaValue, locals: inout [String: YayaValue]) {
        if name.hasPrefix("_") {
            locals[name] = value
        } else {
            globals[name] = value
        }
    }

    private mutating func resolveLValue(
        _ expression: YayaExpression,
        locals: inout [String: YayaValue],
        depth: Int
    ) throws -> YayaLValue {
        switch expression {
        case let .identifier(name, _):
            return .variable(name)
        case let .subscriptAccess(base, indexExpression, _):
            let baseReference = try resolveLValue(base, locals: &locals, depth: depth)
            let indexValue = try evaluate(indexExpression, locals: &locals, depth: depth)
            let index = try integerValue(indexValue)
            guard index >= 0 else { throw YayaRuntimeError.indexOutOfBounds(Int(index)) }
            return .element(base: baseReference, index: Int(index))
        default:
            throw YayaRuntimeError.invalidAssignment
        }
    }

    private func read(_ reference: YayaLValue, locals: inout [String: YayaValue]) throws -> YayaValue {
        switch reference {
        case let .variable(name):
            return locals[name] ?? globals[name] ?? .void
        case let .element(base, index):
            let value = try read(base, locals: &locals)
            switch value {
            case let .array(values):
                guard index < values.count else { return .void }
                return values[index]
            case let .string(value):
                guard index < value.count else { return .void }
                return .string(String(value[value.index(value.startIndex, offsetBy: index)]))
            default:
                throw YayaRuntimeError.invalidOperand("[]")
            }
        }
    }

    private mutating func write(
        _ reference: YayaLValue,
        value: YayaValue,
        locals: inout [String: YayaValue]
    ) throws {
        switch reference {
        case let .variable(name):
            setVariable(name, value: value, locals: &locals)
        case let .element(base, index):
            let container = try read(base, locals: &locals)
            switch container {
            case var .array(values):
                if index >= values.count {
                    values.append(contentsOf: repeatElement(.void, count: index - values.count + 1))
                }
                values[index] = value
                try write(base, value: .array(values), locals: &locals)
            case let .string(string):
                guard index < string.count else { throw YayaRuntimeError.indexOutOfBounds(index) }
                let target = string.index(string.startIndex, offsetBy: index)
                var updated = string
                updated.replaceSubrange(target ... target, with: value.stringValue)
                try write(base, value: .string(updated), locals: &locals)
            default:
                throw YayaRuntimeError.invalidOperand("[]=")
            }
        }
    }

    private func numeric(
        _ left: YayaValue,
        _ right: YayaValue,
        integer: (Int64, Int64) -> Int64,
        floatingPoint: (Double, Double) -> Double
    ) throws -> YayaValue {
        if case let .integer(lhs) = left, case let .integer(rhs) = right {
            return .integer(integer(lhs, rhs))
        }
        return try .floatingPoint(floatingPoint(doubleValue(left), doubleValue(right)))
    }

    private func integerValue(_ value: YayaValue) throws -> Int64 {
        switch value {
        case let .integer(number): number
        case let .floatingPoint(number): Int64(number)
        case let .string(string): Int64(string) ?? 0
        case .void: 0
        case .array: 0
        }
    }

    private func doubleValue(_ value: YayaValue) throws -> Double {
        switch value {
        case let .integer(number): Double(number)
        case let .floatingPoint(number): number
        case let .string(string): Double(string) ?? 0
        case .void: 0
        case .array: 0
        }
    }

    private func contains(_ container: YayaValue, value: YayaValue) -> Bool {
        switch container {
        case let .array(values): values.contains(value)
        case let .string(string): string.contains(value.stringValue)
        default: false
        }
    }

    private var assignmentOperators: Set<String> {
        ["=", "+=", "-=", "*=", "/=", "%=", ":=", "+:=", "-:=", "*:=", "/:=", "%:=", ",="]
    }
}

private struct EvaluationResult {
    let value: YayaValue
    let control: EvaluationControl
}

private enum EvaluationControl: Equatable {
    case normal
    case breakLoop
    case continueLoop
    case returnValue
}

private indirect enum YayaLValue {
    case variable(String)
    case element(base: YayaLValue, index: Int)
}

private struct FunctionExecutionResult {
    let value: YayaValue
    let arguments: [YayaValue]
}

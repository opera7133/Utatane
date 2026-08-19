public enum YayaSelectionMode: String, Equatable, Sendable {
    case random
    case sequential
    case nonoverlap
    case array
}

public enum YayaOutputMode: String, Equatable, Sendable {
    case pickOne
    case pool
    case melt
    case void
    case all
    case last
}

public struct YayaChoiceType: Equatable, Sendable {
    public let selection: YayaSelectionMode
    public let output: YayaOutputMode

    public static let random = YayaChoiceType(selection: .random, output: .pickOne)

    public init(selection: YayaSelectionMode, output: YayaOutputMode = .pickOne) {
        self.selection = selection
        self.output = output
    }

    public init(rawValue: String?) {
        let value = rawValue?.lowercased() ?? "random"
        if value.contains("sequential") {
            selection = .sequential
        } else if value.contains("nonoverlap") {
            selection = .nonoverlap
        } else if value.contains("array") {
            selection = .array
        } else {
            selection = .random
        }

        if value.contains("pool") {
            output = .pool
        } else if value.contains("melt") {
            output = .melt
        } else if value.contains("void") {
            output = .void
        } else if value.contains("all") {
            output = .all
        } else if value.contains("last") {
            output = .last
        } else {
            output = .pickOne
        }
    }
}

public struct YayaFunction: Equatable, Sendable {
    public let name: String
    public let choiceType: YayaChoiceType
    public let body: [YayaStatement]
    public let range: YayaSourceRange

    public init(name: String, choiceType: YayaChoiceType, body: [YayaStatement], range: YayaSourceRange) {
        self.name = name
        self.choiceType = choiceType
        self.body = body
        self.range = range
    }
}

public struct YayaCaseBranch: Equatable, Sendable {
    public let matches: YayaExpression
    public let body: [YayaStatement]

    public init(matches: YayaExpression, body: [YayaStatement]) {
        self.matches = matches
        self.body = body
    }
}

public struct YayaConditionalBranch: Equatable, Sendable {
    public let condition: YayaExpression
    public let body: [YayaStatement]

    public init(condition: YayaExpression, body: [YayaStatement]) {
        self.condition = condition
        self.body = body
    }
}

public indirect enum YayaStatement: Equatable, Sendable {
    case expression(YayaExpression)
    case parallel(YayaExpression, range: YayaSourceRange)
    case discard(YayaExpression, range: YayaSourceRange)
    case conditional(branches: [YayaConditionalBranch], elseBody: [YayaStatement], range: YayaSourceRange)
    case caseSelection(
        subject: YayaExpression,
        preamble: [YayaStatement],
        branches: [YayaCaseBranch],
        othersBody: [YayaStatement],
        range: YayaSourceRange
    )
    case switchSelection(index: YayaExpression, body: [YayaStatement], range: YayaSourceRange)
    case returnValue(YayaExpression?, range: YayaSourceRange)
    case whileLoop(condition: YayaExpression, body: [YayaStatement], range: YayaSourceRange)
    case forLoop(
        initializer: YayaExpression,
        condition: YayaExpression,
        increment: YayaExpression,
        body: [YayaStatement],
        range: YayaSourceRange
    )
    case forEach(
        collection: YayaExpression,
        variable: String,
        body: [YayaStatement],
        range: YayaSourceRange
    )
    case breakLoop(range: YayaSourceRange)
    case continueLoop(range: YayaSourceRange)
    case block([YayaStatement], range: YayaSourceRange)
    case choiceSeparator(range: YayaSourceRange)

    public var range: YayaSourceRange {
        switch self {
        case let .expression(expression): expression.range
        case let .parallel(_, range), let .discard(_, range), let .whileLoop(_, _, range),
             let .forLoop(_, _, _, _, range), let .forEach(_, _, _, range), let .breakLoop(range),
             let .continueLoop(range), let .switchSelection(_, _, range): range
        case let .conditional(_, _, range), let .caseSelection(_, _, _, _, range),
             let .returnValue(_, range), let .block(_, range),
             let .choiceSeparator(range): range
        }
    }
}

public struct YayaProgram: Equatable, Sendable {
    public let functions: [YayaFunction]
    public let diagnostics: [YayaSyntaxDiagnostic]

    public init(functions: [YayaFunction], diagnostics: [YayaSyntaxDiagnostic]) {
        self.functions = functions
        self.diagnostics = diagnostics
    }

    public func function(named name: String) -> YayaFunction? {
        functions.first { $0.name == name }
    }
}

public enum YayaDictionaryParseError: Error, Equatable, Sendable {
    case lexical([YayaSyntaxDiagnostic])
    case expected(String, YayaToken?)
    case expression(YayaExpressionParseError, [YayaToken])
}

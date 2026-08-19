public struct YayaDictionaryParser {
    private let tokens: [YayaToken]
    private var index = 0
    private var diagnostics: [YayaSyntaxDiagnostic] = []

    public init(tokens: [YayaToken]) {
        self.tokens = tokens
    }

    public static func parse(source: String) throws -> YayaProgram {
        var lexer = YayaLexer(source: source)
        let result = lexer.lex()
        let errors = result.diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw YayaDictionaryParseError.lexical(errors)
        }
        var parser = YayaDictionaryParser(tokens: result.tokens)
        var program = try parser.parse()
        program = YayaProgram(
            functions: program.functions,
            diagnostics: result.diagnostics + program.diagnostics
        )
        return program
    }

    public mutating func parse() throws -> YayaProgram {
        var functions: [YayaFunction] = []
        while !isAtEnd {
            skipSeparators()
            guard !isAtEnd else { break }
            if case .directive = peek()?.kind {
                skipToNextLine()
                continue
            }
            try functions.append(parseFunction())
        }
        return YayaProgram(functions: functions, diagnostics: diagnostics)
    }

    private mutating func parseFunction() throws -> YayaFunction {
        guard let nameToken = advance(), case let .identifier(name) = nameToken.kind else {
            throw YayaDictionaryParseError.expected("function name", peek())
        }

        var choiceType: String?
        if match(.colon) {
            guard let token = advance(), case let .identifier(value) = token.kind else {
                throw YayaDictionaryParseError.expected("choice type", peek())
            }
            choiceType = value
        }
        skipSeparators()
        let (body, closing) = try parseBlock()
        return YayaFunction(
            name: name,
            choiceType: YayaChoiceType(rawValue: choiceType),
            body: body,
            range: .init(start: nameToken.range.start, end: closing.range.end)
        )
    }

    private mutating func parseBlock() throws -> ([YayaStatement], YayaToken) {
        guard let opening = advance(), opening.kind == .leftBrace else {
            throw YayaDictionaryParseError.expected("'{'", peek())
        }
        var statements: [YayaStatement] = []
        while !isAtEnd {
            skipSeparators()
            if let token = peek(), token.kind == .rightBrace {
                _ = advance()
                return (statements, token)
            }
            try statements.append(parseStatement())
        }
        throw YayaDictionaryParseError.expected("'}'", nil)
    }

    private mutating func parseStatement() throws -> YayaStatement {
        guard let token = peek() else {
            throw YayaDictionaryParseError.expected("statement", nil)
        }

        if token.kind == .leftBrace {
            let start = token.range.start
            let (body, closing) = try parseBlock()
            return .block(body, range: .init(start: start, end: closing.range.end))
        }

        if case .operatorSymbol("--") = token.kind {
            _ = advance()
            return .choiceSeparator(range: token.range)
        }

        if case let .identifier(keyword) = token.kind {
            switch keyword {
            case "if":
                return try parseConditional()
            case "case":
                return try parseCase()
            case "switch":
                return try parseSwitch()
            case "while":
                return try parseWhile()
            case "for":
                return try parseFor()
            case "foreach":
                return try parseForEach()
            case "parallel":
                return try parsePrefixedExpression(asParallel: true)
            case "void":
                return try parsePrefixedExpression(asParallel: false)
            case "break":
                _ = advance()
                return .breakLoop(range: token.range)
            case "continue":
                _ = advance()
                return .continueLoop(range: token.range)
            case "return":
                return try parseReturn()
            default:
                break
            }
        }

        let expressionTokens = collectExpressionTokens()
        guard !expressionTokens.isEmpty else {
            throw YayaDictionaryParseError.expected("expression", token)
        }
        return try .expression(parseExpression(expressionTokens))
    }

    private mutating func parseSwitch() throws -> YayaStatement {
        let token = advance()!
        let index = try parseExpressionBeforeBlock()
        let (body, closing) = try parseBlock()
        return .switchSelection(
            index: index,
            body: body,
            range: .init(start: token.range.start, end: closing.range.end)
        )
    }

    private mutating func parseWhile() throws -> YayaStatement {
        let token = advance()!
        let condition = try parseExpressionBeforeBlock()
        let (body, closing) = try parseBlock()
        return .whileLoop(
            condition: condition,
            body: body,
            range: .init(start: token.range.start, end: closing.range.end)
        )
    }

    private mutating func parseFor() throws -> YayaStatement {
        let token = advance()!
        let segments = collectLoopHeaderSegments()
        guard segments.count == 3 else {
            throw YayaDictionaryParseError.expected("three ';'-separated for expressions", peek())
        }
        let initializer = try parseExpression(segments[0])
        let condition = try parseExpression(segments[1])
        let increment = try parseExpression(segments[2])
        skipSeparators()
        let (body, closing) = try parseBlock()
        return .forLoop(
            initializer: initializer,
            condition: condition,
            increment: increment,
            body: body,
            range: .init(start: token.range.start, end: closing.range.end)
        )
    }

    private mutating func parseForEach() throws -> YayaStatement {
        let token = advance()!
        let segments = collectLoopHeaderSegments()
        guard segments.count == 2 else {
            throw YayaDictionaryParseError.expected("collection and variable separated by ';'", peek())
        }
        let collection = try parseExpression(segments[0])
        let variableExpression = try parseExpression(segments[1])
        guard case let .identifier(variable, _) = variableExpression else {
            throw YayaDictionaryParseError.expected("foreach variable", segments[1].first)
        }
        skipSeparators()
        let (body, closing) = try parseBlock()
        return .forEach(
            collection: collection,
            variable: variable,
            body: body,
            range: .init(start: token.range.start, end: closing.range.end)
        )
    }

    private mutating func parsePrefixedExpression(asParallel: Bool) throws -> YayaStatement {
        let token = advance()!
        let expressionTokens = collectExpressionTokens()
        guard !expressionTokens.isEmpty else {
            throw YayaDictionaryParseError.expected("expression", peek())
        }
        let expression = try parseExpression(expressionTokens)
        let range = YayaSourceRange(start: token.range.start, end: expression.range.end)
        return asParallel ? .parallel(expression, range: range) : .discard(expression, range: range)
    }

    private mutating func collectLoopHeaderSegments() -> [[YayaToken]] {
        var segments: [[YayaToken]] = [[]]
        var parenthesisDepth = 0
        var bracketDepth = 0
        while let token = peek() {
            if parenthesisDepth == 0, bracketDepth == 0 {
                if token.kind == .leftBrace {
                    break
                }
                if token.kind == .semicolon {
                    _ = advance()
                    segments.append([])
                    continue
                }
            }
            if token.kind == .operatorSymbol("(") {
                parenthesisDepth += 1
            }
            if token.kind == .operatorSymbol(")") {
                parenthesisDepth -= 1
            }
            if token.kind == .operatorSymbol("[") {
                bracketDepth += 1
            }
            if token.kind == .operatorSymbol("]") {
                bracketDepth -= 1
            }
            if token.kind != .newline {
                segments[segments.count - 1].append(token)
            }
            _ = advance()
        }
        return segments
    }

    private mutating func parseCase() throws -> YayaStatement {
        let caseToken = advance()!
        let subject = try parseExpressionBeforeBlock()
        guard advance()?.kind == .leftBrace else {
            throw YayaDictionaryParseError.expected("'{'", peek())
        }

        var branches: [YayaCaseBranch] = []
        var preamble: [YayaStatement] = []
        var othersBody: [YayaStatement] = []
        var end = caseToken.range.end
        var foundClosingBrace = false
        while !isAtEnd {
            skipSeparators()
            if let closing = peek(), closing.kind == .rightBrace {
                _ = advance()
                end = closing.range.end
                foundClosingBrace = true
                break
            }
            guard let token = peek() else { break }
            guard case let .identifier(keyword) = token.kind,
                  keyword == "when" || keyword == "others"
            else {
                try preamble.append(parseStatement())
                continue
            }
            _ = advance()
            switch keyword {
            case "when":
                let matches = try parseExpressionBeforeBlock()
                let (body, bodyEnd) = try parseControlBody()
                branches.append(YayaCaseBranch(matches: matches, body: body))
                end = bodyEnd
            case "others":
                skipSeparators()
                if peek()?.kind == .leftBrace {
                    let (body, closing) = try parseBlock()
                    othersBody = body
                    end = closing.range.end
                } else {
                    let statement = try parseStatement()
                    othersBody = [statement]
                    end = statement.range.end
                }
            default:
                throw YayaDictionaryParseError.expected("'when' or 'others'", token)
            }
        }
        guard foundClosingBrace else {
            throw YayaDictionaryParseError.expected("'}'", peek())
        }

        return .caseSelection(
            subject: subject,
            preamble: preamble,
            branches: branches,
            othersBody: othersBody,
            range: .init(start: caseToken.range.start, end: end)
        )
    }

    private mutating func parseConditional() throws -> YayaStatement {
        let ifToken = advance()!
        var branches: [YayaConditionalBranch] = []
        let condition = try parseExpressionBeforeBlock()
        let (body, bodyEnd) = try parseControlBody()
        branches.append(YayaConditionalBranch(condition: condition, body: body))
        var end = bodyEnd
        var elseBody: [YayaStatement] = []

        while true {
            skipSeparators()
            guard let token = peek(), case let .identifier(keyword) = token.kind else { break }
            if keyword == "elseif" {
                _ = advance()
                let branchCondition = try parseExpressionBeforeBlock()
                let (branchBody, branchEnd) = try parseControlBody()
                branches.append(YayaConditionalBranch(condition: branchCondition, body: branchBody))
                end = branchEnd
            } else if keyword == "else" || keyword == "others" {
                _ = advance()
                skipSeparators()
                let (body, elseEnd) = try parseControlBody()
                elseBody = body
                end = elseEnd
                break
            } else {
                break
            }
        }
        return .conditional(
            branches: branches,
            elseBody: elseBody,
            range: .init(start: ifToken.range.start, end: end)
        )
    }

    private mutating func parseControlBody() throws -> ([YayaStatement], YayaSourcePosition) {
        skipSeparators()
        if peek()?.kind == .leftBrace {
            let (body, closing) = try parseBlock()
            return (body, closing.range.end)
        }
        let statement = try parseStatement()
        return ([statement], statement.range.end)
    }

    private mutating func parseReturn() throws -> YayaStatement {
        let returnToken = advance()!
        let expressionTokens = collectExpressionTokens()
        let expression = try expressionTokens.isEmpty ? nil : parseExpression(expressionTokens)
        let end = expression?.range.end ?? returnToken.range.end
        return .returnValue(expression, range: .init(start: returnToken.range.start, end: end))
    }

    private mutating func parseExpressionBeforeBlock() throws -> YayaExpression {
        let expressionTokens = collectExpressionTokens(stoppingAtBlock: true)
        guard !expressionTokens.isEmpty else {
            throw YayaDictionaryParseError.expected("condition", peek())
        }
        skipSeparators()
        return try parseExpression(expressionTokens)
    }

    private mutating func collectExpressionTokens(stoppingAtBlock: Bool = false) -> [YayaToken] {
        var result: [YayaToken] = []
        var parenthesisDepth = 0
        var bracketDepth = 0
        while let token = peek() {
            if parenthesisDepth == 0, bracketDepth == 0 {
                if token.kind == .newline || token.kind == .semicolon || token.kind == .rightBrace {
                    break
                }
                if stoppingAtBlock, token.kind == .leftBrace {
                    break
                }
            }
            if token.kind == .operatorSymbol("(") {
                parenthesisDepth += 1
            }
            if token.kind == .operatorSymbol(")") {
                parenthesisDepth -= 1
            }
            if token.kind == .operatorSymbol("[") {
                bracketDepth += 1
            }
            if token.kind == .operatorSymbol("]") {
                bracketDepth -= 1
            }
            result.append(advance()!)
        }
        if peek()?.kind == .semicolon {
            _ = advance()
        }
        return result
    }

    private func parseExpression(_ tokens: [YayaToken]) throws -> YayaExpression {
        do {
            var parser = YayaExpressionParser(tokens: tokens)
            return try parser.parse()
        } catch let error as YayaExpressionParseError {
            throw YayaDictionaryParseError.expression(error, tokens)
        }
    }

    private mutating func skipSeparators() {
        while peek()?.kind == .newline || peek()?.kind == .semicolon {
            _ = advance()
        }
    }

    private mutating func skipToNextLine() {
        while let token = advance(), token.kind != .newline, token.kind != .endOfFile {}
    }

    private mutating func match(_ kind: YayaTokenKind) -> Bool {
        guard peek()?.kind == kind else { return false }
        _ = advance()
        return true
    }

    private var isAtEnd: Bool {
        peek()?.kind == .endOfFile || peek() == nil
    }

    private func peek() -> YayaToken? {
        index < tokens.count ? tokens[index] : nil
    }

    @discardableResult
    private mutating func advance() -> YayaToken? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }
}

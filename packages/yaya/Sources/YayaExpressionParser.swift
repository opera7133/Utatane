public struct YayaExpressionParser {
    private let tokens: [YayaToken]
    private var index = 0

    public init(tokens: [YayaToken]) {
        self.tokens = tokens.filter {
            $0.kind != .newline && $0.kind != .endOfFile
        }
    }

    public static func parse(source: String) throws -> YayaExpression {
        var lexer = YayaLexer(source: source)
        let result = lexer.lex()
        let errors = result.diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw YayaExpressionParseError.lexical(errors)
        }
        var parser = YayaExpressionParser(tokens: result.tokens)
        return try parser.parse()
    }

    public mutating func parse() throws -> YayaExpression {
        let expression = try parseExpression(minimumPrecedence: 1)
        if let token = peek() {
            throw YayaExpressionParseError.trailingToken(token)
        }
        return expression
    }

    private mutating func parseExpression(minimumPrecedence: Int) throws -> YayaExpression {
        var left = try parsePrefix()

        while let token = peek(),
              case let .operatorSymbol(symbol) = token.kind,
              let precedence = precedence(of: symbol),
              precedence >= minimumPrecedence
        {
            _ = advance()
            let nextMinimum = isRightAssociative(symbol) ? precedence : precedence + 1
            let right = try parseExpression(minimumPrecedence: nextMinimum)
            left = .binary(
                left: left,
                operator: symbol,
                right: right,
                range: .init(start: left.range.start, end: right.range.end)
            )
        }
        return left
    }

    private mutating func parsePrefix() throws -> YayaExpression {
        guard let token = advance() else {
            throw YayaExpressionParseError.expectedExpression(endRange)
        }

        let expression: YayaExpression
        switch token.kind {
        case let .integer(raw):
            let value: Int64? = if raw.lowercased().hasPrefix("0x") {
                Int64(raw.dropFirst(2), radix: 16)
            } else {
                Int64(raw)
            }
            guard let value else {
                throw YayaExpressionParseError.invalidNumber(raw, token.range)
            }
            expression = .literal(.integer(value), range: token.range)

        case let .floatingPoint(raw):
            guard let value = Double(raw) else {
                throw YayaExpressionParseError.invalidNumber(raw, token.range)
            }
            expression = .literal(.floatingPoint(value), range: token.range)

        case let .stringLiteral(value, _, _):
            expression = .literal(.string(value), range: token.range)

        case let .identifier(name):
            expression = .identifier(name, range: token.range)

        case let .operatorSymbol(symbol) where ["!", "+", "-", "&", "++", "--"].contains(symbol):
            let operand = try parseExpression(minimumPrecedence: 10)
            expression = .unary(
                operator: symbol,
                operand: operand,
                range: .init(start: token.range.start, end: operand.range.end)
            )

        case .operatorSymbol("("):
            let grouped = try parseExpression(minimumPrecedence: 1)
            _ = try consumeOperator(")")
            expression = grouped

        default:
            throw YayaExpressionParseError.expectedExpression(token.range)
        }

        return try parsePostfix(expression)
    }

    private mutating func parsePostfix(_ initial: YayaExpression) throws -> YayaExpression {
        var expression = initial
        while let token = peek() {
            switch token.kind {
            case .operatorSymbol("("):
                _ = advance()
                var arguments: [YayaExpression] = []
                if !checkOperator(")") {
                    repeat {
                        try arguments.append(parseExpression(minimumPrecedence: 2))
                    } while matchOperator(",")
                }
                let closing = try consumeOperator(")")
                expression = .call(
                    callee: expression,
                    arguments: arguments,
                    range: .init(start: expression.range.start, end: closing.range.end)
                )

            case .operatorSymbol("["):
                _ = advance()
                let indexExpression = try parseExpression(minimumPrecedence: 1)
                let closing = try consumeOperator("]")
                expression = .subscriptAccess(
                    base: expression,
                    index: indexExpression,
                    range: .init(start: expression.range.start, end: closing.range.end)
                )

            case let .operatorSymbol(symbol) where symbol == "++" || symbol == "--":
                _ = advance()
                expression = .unary(
                    operator: symbol,
                    operand: expression,
                    range: .init(start: expression.range.start, end: token.range.end)
                )

            default:
                return expression
            }
        }
        return expression
    }

    private func precedence(of symbol: String) -> Int? {
        switch symbol {
        case ",": 1
        case "=", "+=", "-=", "*=", "/=", "%=", ":=", "+:=", "-:=", "*:=", "/:=", "%:=", ",=": 2
        case "||": 3
        case "&&": 4
        case "==", "!=", ">=", "<=", ">", "<", "_in_", "!_in_": 5
        case "&": 6
        case "+", "-": 7
        case "*", "/", "%": 8
        default: nil
        }
    }

    private func isRightAssociative(_ symbol: String) -> Bool {
        precedence(of: symbol) == 2
    }

    private mutating func consumeOperator(_ symbol: String) throws -> YayaToken {
        guard let token = advance(), token.kind == .operatorSymbol(symbol) else {
            throw YayaExpressionParseError.expectedToken(symbol, peek()?.range ?? endRange)
        }
        return token
    }

    private mutating func matchOperator(_ symbol: String) -> Bool {
        guard checkOperator(symbol) else { return false }
        _ = advance()
        return true
    }

    private func checkOperator(_ symbol: String) -> Bool {
        peek()?.kind == .operatorSymbol(symbol)
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

    private var endRange: YayaSourceRange {
        let position = tokens.last?.range.end ?? .init(offset: 0, line: 1, column: 1)
        return .init(start: position, end: position)
    }
}

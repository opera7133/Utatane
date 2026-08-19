public enum YayaLiteral: Equatable, Sendable {
    case integer(Int64)
    case floatingPoint(Double)
    case string(String)
}

public indirect enum YayaExpression: Equatable, Sendable {
    case literal(YayaLiteral, range: YayaSourceRange)
    case identifier(String, range: YayaSourceRange)
    case unary(operator: String, operand: YayaExpression, range: YayaSourceRange)
    case binary(left: YayaExpression, operator: String, right: YayaExpression, range: YayaSourceRange)
    case call(callee: YayaExpression, arguments: [YayaExpression], range: YayaSourceRange)
    case subscriptAccess(base: YayaExpression, index: YayaExpression, range: YayaSourceRange)

    public var range: YayaSourceRange {
        switch self {
        case let .literal(_, range), let .identifier(_, range), let .unary(_, _, range),
             let .binary(_, _, _, range), let .call(_, _, range), let .subscriptAccess(_, _, range):
            range
        }
    }
}

public enum YayaExpressionParseError: Error, Equatable, Sendable {
    case lexical([YayaSyntaxDiagnostic])
    case expectedExpression(YayaSourceRange)
    case expectedToken(String, YayaSourceRange)
    case invalidNumber(String, YayaSourceRange)
    case trailingToken(YayaToken)
}

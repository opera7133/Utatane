import Foundation

public struct YayaSourcePosition: Equatable, Sendable {
    public let offset: Int
    public let line: Int
    public let column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }
}

public struct YayaSourceRange: Equatable, Sendable {
    public let start: YayaSourcePosition
    public let end: YayaSourcePosition

    public init(start: YayaSourcePosition, end: YayaSourcePosition) {
        self.start = start
        self.end = end
    }
}

public enum YayaQuoteStyle: Equatable, Sendable {
    case single
    case double
}

public enum YayaTokenKind: Equatable, Sendable {
    case identifier(String)
    case integer(String)
    case floatingPoint(String)
    case stringLiteral(value: String, quote: YayaQuoteStyle, isHereDocument: Bool)
    case operatorSymbol(String)
    case directive(String)
    case leftBrace
    case rightBrace
    case colon
    case semicolon
    case newline
    case endOfFile
}

public struct YayaToken: Equatable, Sendable {
    public let kind: YayaTokenKind
    public let range: YayaSourceRange

    public init(kind: YayaTokenKind, range: YayaSourceRange) {
        self.kind = kind
        self.range = range
    }
}

public struct YayaSyntaxDiagnostic: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        case warning
        case error
    }

    public let severity: Severity
    public let sourceURL: URL?
    public let range: YayaSourceRange
    public let message: String

    public init(severity: Severity, sourceURL: URL?, range: YayaSourceRange, message: String) {
        self.severity = severity
        self.sourceURL = sourceURL
        self.range = range
        self.message = message
    }
}

public struct YayaLexResult: Equatable, Sendable {
    public let tokens: [YayaToken]
    public let diagnostics: [YayaSyntaxDiagnostic]

    public init(tokens: [YayaToken], diagnostics: [YayaSyntaxDiagnostic]) {
        self.tokens = tokens
        self.diagnostics = diagnostics
    }
}

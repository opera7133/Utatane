import Foundation

public struct YayaCompatibilityIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case read
        case lexical
        case syntax
    }

    public let kind: Kind
    public let sourceURL: URL
    public let line: Int?
    public let column: Int?
    public let message: String

    public init(kind: Kind, sourceURL: URL, line: Int?, column: Int?, message: String) {
        self.kind = kind
        self.sourceURL = sourceURL
        self.line = line
        self.column = column
        self.message = message
    }
}

public struct YayaCompatibilityReport: Equatable, Sendable {
    public let dictionaryCount: Int
    public let parsedDictionaryCount: Int
    public let issues: [YayaCompatibilityIssue]
    public let runtime: YayaRuntimeCompatibilityReport

    public init(
        dictionaryCount: Int,
        parsedDictionaryCount: Int,
        issues: [YayaCompatibilityIssue],
        runtime: YayaRuntimeCompatibilityReport = YayaRuntimeCompatibilityReport(
            declaredFunctionCount: 0,
            functionCallCount: 0,
            unsupportedFunctions: []
        )
    ) {
        self.dictionaryCount = dictionaryCount
        self.parsedDictionaryCount = parsedDictionaryCount
        self.issues = issues
        self.runtime = runtime
    }
}

public struct YayaCompatibilityAuditor {
    private let reader: YayaDictionaryReader

    public init(reader: YayaDictionaryReader = YayaDictionaryReader()) {
        self.reader = reader
    }

    public func audit(configuration: YayaConfiguration) -> YayaCompatibilityReport {
        var parsedDictionaryCount = 0
        var issues: [YayaCompatibilityIssue] = []
        var programs: [(sourceURL: URL, program: YayaProgram)] = []
        var globalDefinitions: [String: String] = [:]
        let preprocessor = YayaPreprocessor()

        for source in configuration.dictionaries {
            let document: YayaDictionaryDocument
            do {
                document = try reader.read(source)
            } catch {
                if !source.isOptional {
                    issues.append(YayaCompatibilityIssue(
                        kind: .read,
                        sourceURL: source.url,
                        line: nil,
                        column: nil,
                        message: String(describing: error)
                    ))
                }
                continue
            }

            let processedSource = preprocessor.process(
                source: document.text,
                globalDefinitions: &globalDefinitions
            )
            var lexer = YayaLexer(source: processedSource, sourceURL: source.url)
            let lexResult = lexer.lex()
            let lexicalErrors = lexResult.diagnostics.filter { $0.severity == .error }
            if !lexicalErrors.isEmpty {
                issues.append(contentsOf: lexicalErrors.map {
                    YayaCompatibilityIssue(
                        kind: .lexical,
                        sourceURL: source.url,
                        line: $0.range.start.line,
                        column: $0.range.start.column,
                        message: $0.message
                    )
                })
                continue
            }

            do {
                var parser = YayaDictionaryParser(tokens: lexResult.tokens)
                let program = try parser.parse()
                programs.append((source.url, program))
                parsedDictionaryCount += 1
            } catch let error as YayaDictionaryParseError {
                issues.append(issue(for: error, sourceURL: source.url))
            } catch {
                issues.append(YayaCompatibilityIssue(
                    kind: .syntax,
                    sourceURL: source.url,
                    line: nil,
                    column: nil,
                    message: String(describing: error)
                ))
            }
        }

        return YayaCompatibilityReport(
            dictionaryCount: configuration.dictionaries.count,
            parsedDictionaryCount: parsedDictionaryCount,
            issues: issues,
            runtime: YayaRuntimeCompatibilityAuditor().audit(programs: programs)
        )
    }

    private func issue(for error: YayaDictionaryParseError, sourceURL: URL) -> YayaCompatibilityIssue {
        switch error {
        case let .lexical(diagnostics):
            let diagnostic = diagnostics.first
            return YayaCompatibilityIssue(
                kind: .lexical,
                sourceURL: sourceURL,
                line: diagnostic?.range.start.line,
                column: diagnostic?.range.start.column,
                message: diagnostic?.message ?? "Lexical error"
            )
        case let .expected(expected, token):
            return YayaCompatibilityIssue(
                kind: .syntax,
                sourceURL: sourceURL,
                line: token?.range.start.line,
                column: token?.range.start.column,
                message: "Expected \(expected)"
            )
        case let .expression(error, _):
            let location = expressionLocation(error)
            return YayaCompatibilityIssue(
                kind: .syntax,
                sourceURL: sourceURL,
                line: location?.line,
                column: location?.column,
                message: String(describing: error)
            )
        }
    }

    private func expressionLocation(_ error: YayaExpressionParseError) -> YayaSourcePosition? {
        switch error {
        case let .lexical(diagnostics): diagnostics.first?.range.start
        case let .expectedExpression(range), let .expectedToken(_, range), let .invalidNumber(_, range):
            range.start
        case let .trailingToken(token): token.range.start
        }
    }
}

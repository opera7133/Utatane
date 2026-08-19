import Foundation

public enum YayaProgramLoadError: Error, Equatable, Sendable {
    case lexical(URL, [YayaSyntaxDiagnostic])
    case syntax(URL, String)
}

public struct YayaProgramLoader {
    private let reader: YayaDictionaryReader

    public init(reader: YayaDictionaryReader = YayaDictionaryReader()) {
        self.reader = reader
    }

    public func load(configuration: YayaConfiguration) throws -> YayaProgram {
        var functions: [YayaFunction] = []
        var diagnostics: [YayaSyntaxDiagnostic] = []
        var globalDefinitions: [String: String] = [:]
        let preprocessor = YayaPreprocessor()

        for source in configuration.dictionaries {
            let document: YayaDictionaryDocument
            do {
                document = try reader.read(source)
            } catch {
                if source.isOptional {
                    continue
                }
                throw error
            }
            let processedSource = preprocessor.process(
                source: document.text,
                globalDefinitions: &globalDefinitions
            )
            var lexer = YayaLexer(source: processedSource, sourceURL: source.url)
            let lexResult = lexer.lex()
            let errors = lexResult.diagnostics.filter { $0.severity == .error }
            guard errors.isEmpty else {
                throw YayaProgramLoadError.lexical(source.url, errors)
            }
            do {
                var parser = YayaDictionaryParser(tokens: lexResult.tokens)
                let program = try parser.parse()
                functions.append(contentsOf: program.functions)
                diagnostics.append(contentsOf: program.diagnostics)
            } catch {
                throw YayaProgramLoadError.syntax(source.url, String(describing: error))
            }
        }
        return YayaProgram(functions: functions, diagnostics: diagnostics)
    }
}

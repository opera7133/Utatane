import Foundation

public enum YayaDictionaryReadError: Error, Equatable, Sendable {
    case fileNotFound(String)
    case unreadableText(String, YayaTextEncoding)
}

public struct YayaDictionaryDocument: Equatable, Sendable {
    public let source: YayaDictionarySource
    public let text: String
    public let lexResult: YayaLexResult

    public init(source: YayaDictionarySource, text: String, lexResult: YayaLexResult) {
        self.source = source
        self.text = text
        self.lexResult = lexResult
    }
}

public struct YayaDictionaryReader {
    public init() {}

    public func read(_ source: YayaDictionarySource) throws -> YayaDictionaryDocument {
        let data: Data
        do {
            data = try Data(contentsOf: source.url)
        } catch {
            throw YayaDictionaryReadError.fileNotFound(source.url.path)
        }
        let text: String
        var decodingDiagnostics: [YayaSyntaxDiagnostic] = []
        if let decoded = String(data: data, encoding: source.encoding.foundationEncoding) {
            text = strippingByteOrderMark(decoded)
        } else if source.encoding == .utf8 {
            text = strippingByteOrderMark(String(decoding: data, as: UTF8.self))
            let position = YayaSourcePosition(offset: 0, line: 1, column: 1)
            decodingDiagnostics.append(YayaSyntaxDiagnostic(
                severity: .warning,
                sourceURL: source.url,
                range: .init(start: position, end: position),
                message: "Invalid UTF-8 sequences were replaced"
            ))
        } else {
            throw YayaDictionaryReadError.unreadableText(source.url.path, source.encoding)
        }
        var lexer = YayaLexer(source: text, sourceURL: source.url)
        let result = lexer.lex()
        return YayaDictionaryDocument(
            source: source,
            text: text,
            lexResult: YayaLexResult(
                tokens: result.tokens,
                diagnostics: decodingDiagnostics + result.diagnostics
            )
        )
    }

    public func read(configuration: YayaConfiguration) throws -> [YayaDictionaryDocument] {
        try configuration.dictionaries.map(read)
    }

    private func strippingByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}

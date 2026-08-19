import Foundation

public struct YayaLexer {
    private static let operators = [
        "!_in_", "+:=", "-:=", "*:=", "/:=", "%:=", "_in_", "==", "!=", ">=", "<=", "||", "&&",
        "++", "--", "+=", "-=", "*=", "/=", "%=", ":=", ",=", ",", "+", "-", "*", "/", "%", ">", "<", "&", "!", "=", "(", ")", "[", "]"
    ]

    private let characters: [Character]
    private let sourceURL: URL?
    private var index = 0
    private var line = 1
    private var column = 1
    private var tokens: [YayaToken] = []
    private var diagnostics: [YayaSyntaxDiagnostic] = []

    public init(source: String, sourceURL: URL? = nil) {
        characters = Array(source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n"))
        self.sourceURL = sourceURL
    }

    public mutating func lex() -> YayaLexResult {
        while !isAtEnd {
            scanToken()
        }
        let position = currentPosition
        tokens.append(YayaToken(kind: .endOfFile, range: .init(start: position, end: position)))
        return YayaLexResult(tokens: tokens, diagnostics: diagnostics)
    }

    private mutating func scanToken() {
        let start = currentPosition
        guard let character = peek() else { return }

        if character == " " || character == "\t" || character == "　" || character == "\u{FEFF}" {
            _ = advance()
            return
        }
        if character == "\n" || character == "\r" {
            consumeNewline()
            append(.newline, from: start)
            return
        }
        if matches("//") {
            skipLineComment()
            return
        }
        if matches("/*") {
            skipBlockComment(from: start)
            return
        }
        if character == "/", isLineContinuation() {
            consumeLineContinuation()
            return
        }
        if matches("<<'"), isHereDocumentMarker() {
            scanHereDocument(quote: "'", style: .single, from: start)
            return
        }
        if matches("<<\""), isHereDocumentMarker() {
            scanHereDocument(quote: "\"", style: .double, from: start)
            return
        }
        if character == "'" || character == "\"" {
            scanString(quote: character, from: start)
            return
        }
        if character == "#" {
            scanDirective(from: start)
            return
        }
        if character.isNumber {
            scanNumber(from: start)
            return
        }
        switch character {
        case "{":
            _ = advance()
            append(.leftBrace, from: start)
            return
        case "}":
            _ = advance()
            append(.rightBrace, from: start)
            return
        case ":":
            _ = advance()
            append(.colon, from: start)
            return
        case ";":
            _ = advance()
            append(.semicolon, from: start)
            return
        default:
            break
        }
        if let symbol = matchingOperator() {
            consume(symbol.count)
            append(.operatorSymbol(symbol), from: start)
            return
        }
        scanIdentifier(from: start)
    }

    private mutating func scanString(quote: Character, from start: YayaSourcePosition) {
        _ = advance()
        var value = ""
        while let character = peek(), character != quote {
            value.append(advance()!)
        }
        guard peek() == quote else {
            diagnose("Unterminated string literal", from: start)
            append(.stringLiteral(value: value, quote: quoteStyle(quote), isHereDocument: false), from: start)
            return
        }
        _ = advance()
        append(.stringLiteral(value: value, quote: quoteStyle(quote), isHereDocument: false), from: start)
    }

    private mutating func scanHereDocument(
        quote: Character,
        style: YayaQuoteStyle,
        from start: YayaSourcePosition
    ) {
        consume(3)
        while peek() == " " || peek() == "\t" {
            _ = advance()
        }
        if peek() == "\n" || peek() == "\r" {
            consumeNewline()
        }

        var value = ""
        var atLineStart = true
        while !isAtEnd {
            if atLineStart {
                var lookahead = index
                while lookahead < characters.count,
                      characters[lookahead] == " " || characters[lookahead] == "\t"
                {
                    lookahead += 1
                }
                if lookahead + 2 < characters.count,
                   characters[lookahead] == quote,
                   characters[lookahead + 1] == ">",
                   characters[lookahead + 2] == ">"
                {
                    while index < lookahead {
                        _ = advance()
                    }
                    consume(3)
                    append(.stringLiteral(value: value, quote: style, isHereDocument: true), from: start)
                    return
                }
            }

            guard let character = advance() else { break }
            value.append(character)
            atLineStart = character == "\n" || character == "\r"
        }
        diagnose("Unterminated here document", from: start)
        append(.stringLiteral(value: value, quote: style, isHereDocument: true), from: start)
    }

    private mutating func scanDirective(from start: YayaSourcePosition) {
        _ = advance()
        var name = ""
        while let character = peek(), isIdentifierCharacter(character) {
            name.append(advance()!)
        }
        if name.isEmpty {
            diagnose("Expected a preprocessor directive after '#'", from: start)
        }
        append(.directive(name), from: start)
    }

    private mutating func scanNumber(from start: YayaSourcePosition) {
        var value = ""
        if matches("0x") || matches("0X") {
            value.append(advance()!)
            value.append(advance()!)
            while let character = peek(), character.isHexDigit {
                value.append(advance()!)
            }
            append(.integer(value), from: start)
            return
        }

        while let character = peek(), character.isNumber {
            value.append(advance()!)
        }
        var isFloatingPoint = false
        if peek() == ".", peek(1)?.isNumber == true {
            isFloatingPoint = true
            value.append(advance()!)
            while let character = peek(), character.isNumber {
                value.append(advance()!)
            }
        }
        if peek() == "e" || peek() == "E" {
            let exponentStart = index
            var exponent = String(advance()!)
            if peek() == "+" || peek() == "-" {
                exponent.append(advance()!)
            }
            if peek()?.isNumber == true {
                isFloatingPoint = true
                while let character = peek(), character.isNumber {
                    exponent.append(advance()!)
                }
                value += exponent
            } else {
                index = exponentStart
                column -= exponent.count
            }
        }
        append(isFloatingPoint ? .floatingPoint(value) : .integer(value), from: start)
    }

    private mutating func scanIdentifier(from start: YayaSourcePosition) {
        var value = ""
        while let character = peek(), isIdentifierCharacter(character) {
            value.append(advance()!)
        }
        if value == "_in_" {
            append(.operatorSymbol(value), from: start)
        } else if !value.isEmpty {
            append(.identifier(value), from: start)
        } else {
            let unexpected = advance().map(String.init) ?? ""
            diagnose("Unexpected character '\(unexpected)'", from: start)
        }
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        if character.isWhitespace || character == "\r" || character == "\n" {
            return false
        }
        if "{}:;'\"#".contains(character) {
            return false
        }
        return !",+-*/%><&!=()[]".contains(character)
    }

    private func matchingOperator() -> String? {
        Self.operators.first { matches($0) }
    }

    private func isLineContinuation() -> Bool {
        var lookahead = index + 1
        while lookahead < characters.count,
              characters[lookahead] == " " || characters[lookahead] == "\t"
        {
            lookahead += 1
        }
        return lookahead >= characters.count || characters[lookahead] == "\n" || characters[lookahead] == "\r"
    }

    private func isHereDocumentMarker() -> Bool {
        var lookahead = index + 3
        while lookahead < characters.count,
              characters[lookahead] == " " || characters[lookahead] == "\t"
        {
            lookahead += 1
        }
        return lookahead >= characters.count || characters[lookahead] == "\n" || characters[lookahead] == "\r"
    }

    private mutating func consumeLineContinuation() {
        _ = advance()
        while peek() == " " || peek() == "\t" {
            _ = advance()
        }
        if peek() == "\n" || peek() == "\r" {
            consumeNewline()
        }
    }

    private mutating func skipLineComment() {
        while let character = peek(), character != "\n", character != "\r" {
            _ = advance()
        }
    }

    private mutating func skipBlockComment(from start: YayaSourcePosition) {
        consume(2)
        while !isAtEnd, !matches("*/") {
            _ = advance()
        }
        guard matches("*/") else {
            diagnose("Unterminated block comment", from: start)
            return
        }
        consume(2)
    }

    private mutating func consumeNewline() {
        if peek() == "\r" {
            index += 1
            if peek() == "\n" {
                index += 1
            }
        } else if peek() == "\n" {
            index += 1
        }
        line += 1
        column = 1
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard !isAtEnd else { return nil }
        let character = characters[index]
        index += 1
        if character == "\r" {
            line += 1
            column = 1
        } else if character == "\n" {
            if index < 2 || characters[index - 2] != "\r" {
                line += 1
            }
            column = 1
        } else {
            column += 1
        }
        return character
    }

    private mutating func consume(_ count: Int) {
        for _ in 0 ..< count {
            _ = advance()
        }
    }

    private func peek(_ distance: Int = 0) -> Character? {
        let target = index + distance
        return target < characters.count ? characters[target] : nil
    }

    private func matches(_ text: String) -> Bool {
        let candidate = Array(text)
        guard index + candidate.count <= characters.count else { return false }
        return Array(characters[index ..< index + candidate.count]) == candidate
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }

    private var currentPosition: YayaSourcePosition {
        .init(offset: index, line: line, column: column)
    }

    private mutating func append(_ kind: YayaTokenKind, from start: YayaSourcePosition) {
        tokens.append(YayaToken(kind: kind, range: .init(start: start, end: currentPosition)))
    }

    private mutating func diagnose(_ message: String, from start: YayaSourcePosition) {
        diagnostics.append(YayaSyntaxDiagnostic(
            severity: .error,
            sourceURL: sourceURL,
            range: .init(start: start, end: currentPosition),
            message: message
        ))
    }

    private func quoteStyle(_ quote: Character) -> YayaQuoteStyle {
        quote == "'" ? .single : .double
    }
}

private extension Character {
    var isHexDigit: Bool {
        isNumber || ("a" ... "f").contains(lowercased())
    }
}

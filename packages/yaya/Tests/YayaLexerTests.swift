import Foundation
import Testing
@testable import UtataneYaya

@Test func `lexes functions expressions and comments`() {
    let source = """
    /* heading */
    OnBoot : array
    {
        if reference[0] !_in_ 'halt' { value += 0x10 }
        // ignored
        E.EvalEmbedValue("hello")
    }
    """
    var lexer = YayaLexer(source: source)
    let result = lexer.lex()

    #expect(result.diagnostics.isEmpty)
    #expect(result.tokens.map(\.kind).contains(.identifier("OnBoot")))
    #expect(result.tokens.map(\.kind).contains(.operatorSymbol("!_in_")))
    #expect(result.tokens.map(\.kind).contains(.integer("0x10")))
    #expect(result.tokens.map(\.kind).contains(.identifier("E.EvalEmbedValue")))
    #expect(result.tokens.map(\.kind).contains(.stringLiteral(value: "hello", quote: .double, isHereDocument: false)))
}

@Test func `lexes here document as one string`() {
    let source = """
    Talk
    {
        value = <<'
        first line
        second line
        '>>
    }
    """
    var lexer = YayaLexer(source: source)
    let result = lexer.lex()
    let strings = result.tokens.compactMap { token -> String? in
        guard case let .stringLiteral(value, _, isHereDocument) = token.kind,
              isHereDocument
        else { return nil }
        return value
    }

    #expect(result.diagnostics.isEmpty)
    #expect(strings.count == 1)
    #expect(strings[0].contains("first line\n"))
    #expect(strings[0].contains("second line\n"))
}

@Test func `removes line continuation without emitting division or newline`() {
    var lexer = YayaLexer(source: "value = \"a\" /\n + \"b\"")
    let kinds = lexer.lex().tokens.map(\.kind)

    #expect(kinds.filter { $0 == .operatorSymbol("/") }.isEmpty)
    #expect(kinds.filter { $0 == .newline }.isEmpty)
    #expect(kinds.contains(.operatorSymbol("+")))
}

@Test func `reports unterminated string and comment locations`() {
    var stringLexer = YayaLexer(source: "Talk { 'unfinished")
    let stringResult = stringLexer.lex()
    #expect(stringResult.diagnostics.count == 1)
    #expect(stringResult.diagnostics[0].range.start.line == 1)

    var commentLexer = YayaLexer(source: "Talk\n/* unfinished")
    let commentResult = commentLexer.lex()
    #expect(commentResult.diagnostics.count == 1)
    #expect(commentResult.diagnostics[0].range.start.line == 2)
}

@Test func `dictionary reader uses configured encoding`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("UtataneYayaLexerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let url = root.appendingPathComponent("legacy.dic")
    let text = "OnBoot { 'こんにちは' }"
    try #require(text.data(using: .shiftJIS)).write(to: url)
    let source = YayaDictionarySource(url: url, encoding: .shiftJIS, isOptional: false)

    let document = try YayaDictionaryReader().read(source)

    #expect(document.text == text)
    #expect(document.lexResult.diagnostics.isEmpty)
    #expect(document.lexResult.tokens.map(\.kind).contains(
        .stringLiteral(value: "こんにちは", quote: .single, isHereDocument: false)
    ))
}

@Test func `dictionary reader warns and continues for invalid UTF-8`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("UtataneYayaInvalidUTF8Tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let url = root.appendingPathComponent("mixed.dic")
    try Data([0x2F, 0x2F, 0x20, 0x82, 0xA0, 0x0A, 0x54, 0x61, 0x6C, 0x6B]).write(to: url)
    let source = YayaDictionarySource(url: url, encoding: .utf8, isOptional: false)

    let document = try YayaDictionaryReader().read(source)

    #expect(document.lexResult.diagnostics.count == 1)
    #expect(document.lexResult.diagnostics[0].severity == .warning)
    #expect(document.lexResult.tokens.map(\.kind).contains(.identifier("Talk")))
}

@Test func `dictionary reader strips UTF-8 byte order mark`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("UtataneYayaBOMTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let url = root.appendingPathComponent("bom.dic")
    try "\u{FEFF}OnBoot { 'hello' }".write(to: url, atomically: true, encoding: .utf8)
    let source = YayaDictionarySource(url: url, encoding: .utf8, isOptional: false)

    let document = try YayaDictionaryReader().read(source)

    #expect(document.text.first == "O")
    #expect(document.lexResult.tokens.first?.kind == .identifier("OnBoot"))
}

import Testing
@testable import UtataneSakuraScript

@Test func `strict diagnostics retain source positions and allow ordinary commands`() {
    let parser = SakuraScriptParser()
    let source = #"hello\![unknown,command]\z[invalid]"#
    let diagnostics = parser.diagnostics(source)
    #expect(!diagnostics.isEmpty)
    #expect(diagnostics.allSatisfy { $0.range.lowerBound >= 5 && $0.range.upperBound <= source.count })
    #expect(parser.diagnostics(#"\0\s[0]hello\n\q[選択,OnChoice]\e"#).isEmpty)
}

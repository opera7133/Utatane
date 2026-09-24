import Testing
@testable import UtataneSakuraScript

@Test func `source locations count tags Japanese escapes and literal sections`() {
    let parser = SakuraScriptParser()
    let pieces: [(String, [SakuraScriptToken], [Int]?)] = [
        (#"\s[2]"#, [.surface(2)], nil),
        (#"あいう\\後"#, [.text(#"あいう\後"#)], [1, 2, 3, 5, 6]),
        (#"\%"#, [.text("%")], nil),
        (#"\_u[0x3042]"#, [.text("あ")], nil),
        (#"\&[amp]"#, [.text("&")], nil),
        (#"\_!A\s[1]Ｂ\_!"#, [.text(#"A\s[1]Ｂ"#)], [4, 5, 6, 7, 8, 9, 10]),
        (#"%property[test]"#, [.property("test")], nil),
        (#"%selfname"#, [.environmentVariable("selfname")], nil),
        (#"\q0*[id][選択]"#, [.marker, .choice(label: "選択", id: "id", arguments: []), .lineBreak(scale: nil)], nil),
        (#"\e"#, [.end], nil)
    ]
    let source = pieces.map(\.0).joined()
    let located = parser.parseLocated(source + "ignored")
    #expect(located.map(\.token) == parser.parse(source))
    #expect(located.map(\.token) == pieces.flatMap(\.1))
    var offset = 0
    var expected: [SakuraScriptSourceLocation] = []
    for (raw, tokens, textEnds) in pieces {
        expected += tokens.map { _ in
            .init(range: offset ..< (offset + raw.count), textCharacterEnds: textEnds?.map { offset + $0 })
        }
        offset += raw.count
    }
    #expect(located.map(\.location) == expected)
    #expect(parser.parseLocated(#"終端\"#).last?.location.textCharacterEnds == [1, 2, 3])
}

@Test(arguments: ["", #"\"#, #"\p["#, #"%property["#, #"\_!未閉鎖"#, #"\unknown[あ]\z後"#, "絵😀e\u{301}"])
func `located parsing preserves ordinary parser results`(source: String) {
    let parser = SakuraScriptParser()
    let tokens = parser.parseLocated(source)
    #expect(tokens.map(\.token) == parser.parse(source))
    for token in tokens {
        #expect(token.location.range.lowerBound >= 0)
        #expect(token.location.range.upperBound <= source.count)
        if case let .text(text) = token.token, let ends = token.location.textCharacterEnds {
            #expect(ends.count == text.count)
        }
    }
}

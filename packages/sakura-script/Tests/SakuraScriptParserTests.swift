import Testing
@testable import UtataneSakuraScript

@Test
func `parses initial playback command set`() {
    let tokens = SakuraScriptParser().parse(
        #"\0こんにちは\n\w4\s[10]\1相方\_w[250]\x\x[noclear]\c消去後\e無視"#
    )

    #expect(tokens == [
        .scope(0),
        .text("こんにちは"),
        .lineBreak,
        .wait(milliseconds: 200),
        .surface(10),
        .scope(1),
        .text("相方"),
        .wait(milliseconds: 250),
        .waitForClick(clearOnResume: true),
        .waitForClick(clearOnResume: false),
        .clear,
        .text("消去後"),
        .end
    ])
}

@Test func `parses input box and asynchronous network commands`() {
    let tokens = SakuraScriptParser().parse(
        #"\![open,inputbox,OnNameInput,0,おにいちゃん]\![execute,http-get,https://example.com/feed.json,--async=OnLoaded]\![execute,weather-get,--async=OnWeather]"#
    )

    #expect(tokens == [
        .inputBox(id: "OnNameInput", timeoutMilliseconds: 0, initialValue: "おにいちゃん"),
        .httpGet(url: "https://example.com/feed.json", eventID: "OnLoaded"),
        .weatherGet(eventID: "OnWeather")
    ])
}

@Test
func `supports aliases short arguments and escaped backslash`() {
    let tokens = SakuraScriptParser().parse(#"\h\s1A\\B\u\p[2]C"#)

    #expect(tokens == [
        .scope(0),
        .surface(1),
        .text("A\\B"),
        .scope(1),
        .scope(2),
        .text("C")
    ])
}

@Test
func `parses a named surface alias`() {
    #expect(SakuraScriptParser().parse("\\s[smile]") == [.namedSurface("smile")])
}

@Test
func `parses choices anchors and quoted arguments`() {
    let tokens = SakuraScriptParser().parse(
        #"\q[選択肢,OnChoice,"a,b"] \_a[OnAnchor,arg]リンク\_a"#
    )

    #expect(tokens == [
        .choice(label: "選択肢", id: "OnChoice", arguments: ["a,b"]),
        .text(" "),
        .anchorStart(id: "OnAnchor", arguments: ["arg"]),
        .text("リンク"),
        .anchorEnd
    ])
}

@Test
func `parses embedded SHIORI events`() {
    #expect(SakuraScriptParser().parse(#"\![embed,OnCallSurface,5]"#) == [
        .embeddedEvent(id: "OnCallSurface", arguments: ["5"])
    ])
}

@Test
func `consumes anchor display marker without leaking question marks`() {
    let tokens = SakuraScriptParser().parse(#"\_a[https://example.test/]\_?News\_?\_a"#)

    #expect(tokens == [
        .anchorStart(id: "https://example.test/", arguments: []),
        .unknown("\\_?"),
        .text("News"),
        .unknown("\\_?"),
        .anchorEnd
    ])
}

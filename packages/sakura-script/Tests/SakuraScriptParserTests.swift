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
func `parses balloon surface commands`() {
    #expect(SakuraScriptParser().parse(#"\b2\b[10]"#) == [
        .balloonSurface(2),
        .balloonSurface(10)
    ])
}

@Test
func `parses bind commands including toggle and noevent`() {
    #expect(SakuraScriptParser().parse(
        #"\![bind,服,冬服,1]\![bind,腕,,0]\![bind-noevent,飾り,リボン]"#
    ) == [
        .bind(category: "服", part: "冬服", enabled: true, notifiesEvents: true),
        .bind(category: "腕", part: "", enabled: false, notifiesEvents: true),
        .bind(category: "飾り", part: "リボン", enabled: nil, notifiesEvents: false)
    ])
}

@Test
func `parses font commands`() {
    #expect(SakuraScriptParser().parse(#"\f[color,100,150,200]色\f[bold,true]\f[default]"#) == [
        .font(name: "color", arguments: ["100", "150", "200"]),
        .text("色"),
        .font(name: "bold", arguments: ["true"]),
        .font(name: "default", arguments: [])
    ])
}

@Test
func `parses extended choices and quick sections`() {
    #expect(SakuraScriptParser().parse(#"\__q[OnSelect,arg]選択肢\__q\_q速い\_q\![quicksection,true]\![quicksection,0]"#) == [
        .choiceStart(id: "OnSelect", arguments: ["arg"]),
        .text("選択肢"),
        .choiceEnd,
        .quickSection(nil),
        .text("速い"),
        .quickSection(nil),
        .quickSection(true),
        .quickSection(false)
    ])
}

@Test
func `parses browser commands`() {
    #expect(SakuraScriptParser().parse(#"\j[https://example.com/]\![open,browser,https://example.net/]"#) == [
        .open("https://example.com/"),
        .open("https://example.net/")
    ])
}

@Test
func `parses environment variables and escaped percent`() {
    #expect(SakuraScriptParser().parse(#"%month/%day %selfnameと%keroname \%username %* %unknown"#) == [
        .environmentVariable("month"),
        .text("/"),
        .environmentVariable("day"),
        .text(" "),
        .environmentVariable("selfname"),
        .text("と"),
        .environmentVariable("keroname"),
        .text(" "),
        .text("%"),
        .text("username "),
        .marker,
        .text(" %unknown")
    ])
}

@Test
func `parses raised events`() {
    #expect(SakuraScriptParser().parse(#"before\![raise,OnRaised,arg]after"#) == [
        .text("before"),
        .raisedEvent(id: "OnRaised", arguments: ["arg"]),
        .text("after")
    ])
}

@Test
func `parses content actions`() {
    #expect(SakuraScriptParser().parse(#"\+\_+\![change,ghost,Ria]\![call,ghost,Emily]\![change,shell,master]\![change,balloon,origin]\![updatebymyself]\![update,balloon]\![execute,headline,recall]"#) == [
        .contentAction(.randomGhost),
        .contentAction(.nextGhost),
        .contentAction(.changeGhost("Ria")),
        .contentAction(.callGhost("Emily")),
        .contentAction(.changeShell("master")),
        .contentAction(.changeBalloon("origin")),
        .contentAction(.updateGhost),
        .contentAction(.updateBalloon),
        .contentAction(.headline("recall"))
    ])
}

@Test
func `parses notification and timer events`() {
    #expect(SakuraScriptParser().parse(#"\![notify,OnNotice,a]\![timerraise,5000,1,OnOnce,b]\![timernotify,1000,0,OnRepeat,c]\![timerraise,0,1,OnOnce]"#) == [
        .notifyEvent(id: "OnNotice", arguments: ["a"]),
        .timerEvent(milliseconds: 5000, repeats: false, reflectsResponse: true, id: "OnOnce", arguments: ["b"]),
        .timerEvent(milliseconds: 1000, repeats: true, reflectsResponse: false, id: "OnRepeat", arguments: ["c"]),
        .timerEvent(milliseconds: 0, repeats: false, reflectsResponse: true, id: "OnOnce", arguments: [])
    ])
}

@Test
func `parses other ghost events`() {
    #expect(SakuraScriptParser().parse(#"\![raiseother,Emily,OnPing,a]\![notifyother,__SYSTEM_ALL_GHOST__,OnNotice,b]"#) == [
        .otherEvent(target: "Emily", id: "OnPing", arguments: ["a"], reflectsResponse: true),
        .otherEvent(
            target: "__SYSTEM_ALL_GHOST__",
            id: "OnNotice",
            arguments: ["b"],
            reflectsResponse: false
        )
    ])
}

@Test
func `parses sound commands`() {
    #expect(SakuraScriptParser().parse(#"\8[chime.wav]\_v[voice.mp3]\_V\![sound,loop,bgm.mp3]\![sound,pause]\![sound,resume]\![sound,stop]"#) == [
        .sound(.play(file: "chime.wav", loop: false, options: [])),
        .sound(.play(file: "voice.mp3", loop: false, options: [])),
        .sound(.wait),
        .sound(.play(file: "bgm.mp3", loop: true, options: [])),
        .sound(.pause),
        .sound(.resume),
        .sound(.stop)
    ])
}

@Test
func `parses sound loading and options`() {
    #expect(SakuraScriptParser().parse(#"\![sound,load,bgm.mp3,--volume=40]\![sound,play,bgm.mp3,--balance=-20,--rate=120]\![sound,option,bgm.mp3,--seektime=1500]"#) == [
        .sound(.load(file: "bgm.mp3", options: ["--volume=40"])),
        .sound(.play(file: "bgm.mp3", loop: false, options: ["--balance=-20", "--rate=120"])),
        .sound(.option(file: "bgm.mp3", options: ["--seektime=1500"]))
    ])
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

@Test
func `parses balloon marker command`() {
    #expect(SakuraScriptParser().parse(#"\![*]\q[選択肢,OnChoice]"#) == [
        .marker,
        .choice(label: "選択肢", id: "OnChoice", arguments: [])
    ])
}

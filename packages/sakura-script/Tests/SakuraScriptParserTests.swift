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
        .lineBreak(scale: nil),
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
func `keeps unbracketed IDs to one digit and parses bracketed multi-digit IDs`() {
    #expect(SakuraScriptParser().parse(#"\p12\s34\b56\p[12]\s[345]\b[67]\C"#) == [
        .scope(1),
        .text("2"),
        .surface(3),
        .text("4"),
        .balloonSurface(5),
        .text("6"),
        .scope(12),
        .surface(345),
        .balloonSurface(67),
        .clearAll
    ])
}

@Test
func `parses double-underscore millisecond wait`() {
    #expect(SakuraScriptParser().parse(#"\__w[250]\__w[-10]\__w[clear]"#) == [
        .waitUntil(milliseconds: 250),
        .waitUntil(milliseconds: 0),
        .waitUntil(milliseconds: nil)
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
func `parses legacy choice script terminator as end`() {
    #expect(SakuraScriptParser().parse(#"選択肢の後\z表示されない"#) == [
        .text("選択肢の後"),
        .end
    ])
}

@Test
func `parses choice timeout controls`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,choicetimeout,1500]\![set,choicetimeout,0]\![set,choicetimeout]\*"#
    ) == [
        .choiceTimeout(.milliseconds(1500)),
        .choiceTimeout(.disabled),
        .choiceTimeout(.defaultValue),
        .choiceTimeout(.disabled)
    ])
}

@Test
func `parses balloon playback controls`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,balloontimeout,1200]\![set,balloontimeout,0]\![set,balloontimeout]\![set,balloonwait,1.5]\![set,balloonwait,75%]\![set,balloonwait,20ms]\![set,balloonwait]\![set,balloonmarker,更新中]\![set,balloonmarker]\![set,autoscroll,disable]\![set,autoscroll,enable]"#
    ) == [
        .balloonTimeout(.milliseconds(1200)),
        .balloonTimeout(.disabled),
        .balloonTimeout(.defaultValue),
        .balloonWait(.multiplier(1.5)),
        .balloonWait(.multiplier(0.75)),
        .balloonWait(.milliseconds(20)),
        .balloonWait(.defaultValue),
        .balloonMarker("更新中"),
        .balloonMarker(""),
        .autoscroll(false),
        .autoscroll(true)
    ])
}

@Test
func `parses surface alpha transitions`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,alpha,50]\![set,alpha,200,--time=300,--wait]\![set,alpha,-1,250]"#
    ) == [
        .surfaceAlpha(percent: 50, durationMilliseconds: 0, waitsForCompletion: false),
        .surfaceAlpha(percent: 100, durationMilliseconds: 300, waitsForCompletion: true),
        .surfaceAlpha(percent: nil, durationMilliseconds: 250, waitsForCompletion: false)
    ])
}

@Test
func `parses surface scaling transitions`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,scaling,50]\![set,scaling,-100,75,--time=300,--wait]\![set,scaling,125,80,250]"#
    ) == [
        .surfaceScaling(
            horizontalPercent: 50,
            verticalPercent: 50,
            durationMilliseconds: 0,
            waitsForCompletion: false
        ),
        .surfaceScaling(
            horizontalPercent: -100,
            verticalPercent: 75,
            durationMilliseconds: 300,
            waitsForCompletion: true
        ),
        .surfaceScaling(
            horizontalPercent: 125,
            verticalPercent: 80,
            durationMilliseconds: 250,
            waitsForCompletion: false
        )
    ])
}

@Test
func `parses desktop alignment aliases and directions`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,alignmentondesktop,bottom]\![set,alignmenttodesktop,top]\![set,alignmenttodesktop,left]\![set,alignmenttodesktop,right]\![set,alignmenttodesktop,free]\![set,alignmenttodesktop,default]"#
    ) == [
        .desktopAlignment(.bottom),
        .desktopAlignment(.top),
        .desktopAlignment(.left),
        .desktopAlignment(.right),
        .desktopAlignment(.free),
        .desktopAlignment(.defaultValue)
    ])
}

@Test
func `parses window position reset commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![execute,resetwindowpos]\![execute,resetballoonpos]"#
    ) == [
        .resetWindowPositions,
        .resetBalloonPositions
    ])
}

@Test
func `parses automatic line break and partial clear commands`() {
    #expect(SakuraScriptParser().parse(#"\n[half]\n[150]\n[75%]"#) == [
        .lineBreak(scale: 0.5),
        .lineBreak(scale: 1.5),
        .lineBreak(scale: 0.75)
    ])
    #expect(SakuraScriptParser().parse(
        #"\_n折返しなし\_n\c[char,3]\c[char,2,4]\c[line,1]\c[line,2,3]"#
    ) == [
        .automaticLineBreak,
        .text("折返しなし"),
        .automaticLineBreak,
        .partialClear(unit: .character, count: 3, start: nil),
        .partialClear(unit: .character, count: 2, start: 4),
        .partialClear(unit: .line, count: 1, start: nil),
        .partialClear(unit: .line, count: 2, start: 3)
    ])
}

@Test
func `parses balloon repaint and movement locks`() {
    #expect(SakuraScriptParser().parse(
        #"\![lock,balloonrepaint]\![lock,balloonrepaint,manual]\![unlock,balloonrepaint]\![lock,balloonmove]\![unlock,balloonmove]"#
    ) == [
        .balloonRepaintLock(locked: true, manual: false),
        .balloonRepaintLock(locked: true, manual: true),
        .balloonRepaintLock(locked: false, manual: false),
        .balloonMoveLock(true),
        .balloonMoveLock(false)
    ])
}

@Test
func `parses time critical sections`() {
    #expect(SakuraScriptParser().parse(#"通常\t抑止中\e"#) == [
        .text("通常"),
        .timeCritical,
        .text("抑止中"),
        .end
    ])
}

@Test
func `parses synchronized scope sections`() {
    #expect(SakuraScriptParser().parse(#"\_s両方\_s\_s[0,2,3]複数\_s"#) == [
        .synchronizeScopes(nil),
        .text("両方"),
        .synchronizeScopes(nil),
        .synchronizeScopes([0, 2, 3]),
        .text("複数"),
        .synchronizeScopes(nil)
    ])
}

@Test
func `parses surface animation commands`() {
    #expect(SakuraScriptParser().parse(
        #"\i[blink]\i[12,wait]\![anim,clear,12]\![anim,stop,3]\![anim,pause,12]\![anim,resume,12]\![anim,offset,blink,4,-2]\![lock,repaint]\![unlock,repaint]\__w[animation,12]"#
    ) == [
        .animation(identifier: "blink", waitsForCompletion: false),
        .animation(identifier: "12", waitsForCompletion: true),
        .stopAnimation("12"),
        .stopAnimation("3"),
        .pauseAnimation("12"),
        .resumeAnimation("12"),
        .offsetAnimation(identifier: "blink", x: 4, y: -2),
        .repaintLock(locked: true, manual: false),
        .repaintLock(locked: false, manual: false),
        .waitForAnimation("12")
    ])
}

@Test
func `decodes UCS-2 ASCII and common entity references`() {
    #expect(SakuraScriptParser().parse(#"\_u[0x22EE]\_u[12354]\_m[0x41]\_m[66]\&[amp]\&[lt]\&[quot]"#) == [
        .text("⋮"),
        .text("あ"),
        .text("A"),
        .text("B"),
        .text("&"),
        .text("<"),
        .text("\"")
    ])
}

@Test
func `rejects invalid encoded characters`() {
    #expect(SakuraScriptParser().parse(#"\_u[0xD800]\_u[0x10000]\_m[128]\&[unknown]"#) == [
        .unknown("\\_u"),
        .unknown("\\_u"),
        .unknown("\\_m"),
        .unknown("\\&")
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
func `preserves direct scripts in regular and ranged choices`() {
    #expect(SakuraScriptParser().parse(#"\q[実行,script:\0通常\e]\__q[script:\0範囲\e]実行\__q"#) == [
        .choice(label: "実行", id: #"script:\0通常\e"#, arguments: []),
        .choiceStart(id: #"script:\0範囲\e"#, arguments: []),
        .text("実行"),
        .choiceEnd
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
    let tokens = SakuraScriptParser().parse(#"\_a[https://example.test/]News\_a"#)

    #expect(tokens == [
        .anchorStart(id: "https://example.test/", arguments: []),
        .text("News"),
        .anchorEnd
    ])
}

@Test
func `preserves SakuraScript commands inside literal sections`() {
    #expect(SakuraScriptParser().parse(#"before\_?\1\n%month\_?middle\_!\s[10]\e\_!after"#) == [
        .text("before"),
        .text(#"\1\n%month"#),
        .text("middle"),
        .text(#"\s[10]\e"#),
        .text("after")
    ])
}

@Test
func `treats an unterminated literal section as text through the end`() {
    #expect(SakuraScriptParser().parse(#"\_?\1still literal"#) == [
        .text(#"\1still literal"#)
    ])
}

@Test
func `parses balloon marker command`() {
    #expect(SakuraScriptParser().parse(#"\![*]\q[選択肢,OnChoice]"#) == [
        .marker,
        .choice(label: "選択肢", id: "OnChoice", arguments: [])
    ])
}

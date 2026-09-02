import Foundation
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
        .http(SakuraScriptHTTPRequest(
            method: "GET",
            url: "https://example.com/feed.json",
            eventID: "OnLoaded",
            waitsForCompletion: false
        )),
        .weatherGet(eventID: "OnWeather")
    ])
}

@Test func `parses SNTP commands`() {
    #expect(SakuraScriptParser().parse(#"\7\![executesntp]\6"#) == [
        .sntpStart,
        .sntpStart,
        .sntpCorrect
    ])
}

@Test
func `parses all HTTP methods and common request options`() {
    #expect(SakuraScriptParser().parse(
        #"\![execute,http-post,https://example.com/api,--sync=OnSaved,--param=a=1,--param=b=2,--authorization=Bearer token,--header=X-Test: yes,--content-type=application/json,--timeout=5,--no-cache,--nofile=Shift_JIS]\![execute,http-head,https://example.com,--file=headers.txt]\![execute,http-put,https://example.com,a=1]\![execute,http-delete,https://example.com]\![execute,http-patch,https://example.com,--async=result]\![execute,http-options,https://example.com]"#
    ) == [
        .http(SakuraScriptHTTPRequest(
            method: "POST", url: "https://example.com/api", eventID: "OnSaved",
            waitsForCompletion: true, parameters: ["a=1", "b=2"],
            headers: ["Authorization: Bearer token", "X-Test: yes", "Content-Type: application/json", "Cache-Control: no-cache"],
            timeoutSeconds: 5, output: .memory(characterEncoding: "Shift_JIS")
        )),
        .http(SakuraScriptHTTPRequest(method: "HEAD", url: "https://example.com", eventID: nil, waitsForCompletion: false, output: .file("headers.txt"))),
        .http(SakuraScriptHTTPRequest(method: "PUT", url: "https://example.com", eventID: nil, waitsForCompletion: false, parameters: ["a=1"])),
        .http(SakuraScriptHTTPRequest(method: "DELETE", url: "https://example.com", eventID: nil, waitsForCompletion: false)),
        .http(SakuraScriptHTTPRequest(method: "PATCH", url: "https://example.com", eventID: "result", waitsForCompletion: false)),
        .http(SakuraScriptHTTPRequest(method: "OPTIONS", url: "https://example.com", eventID: nil, waitsForCompletion: false))
    ])
}

@Test
func `parses ping and nslookup diagnostics`() {
    #expect(SakuraScriptParser().parse(
        #"\![execute,ping,--host=example.com,--event=OnChecked,--count=2,--size=64,--timeout=1000,--ttl=32]\![execute,nslookup,--host=127.0.0.1,--event=lookup]"#
    ) == [
        .networkDiagnostic(.ping(host: "example.com", eventID: "OnChecked", count: 2, size: 64, timeoutMilliseconds: 1000, ttl: 32)),
        .networkDiagnostic(.nslookup(host: "127.0.0.1", eventID: "lookup"))
    ])
}

@Test
func `parses WebSocket lifecycle and frames`() {
    #expect(SakuraScriptParser().parse(
        #"\![execute,websocket,wss://example.com/chat,--event=OnChat,--header=Authorization: token,--m_websocketProtocol=chat]\![send,websocket,wss://example.com/chat,Hello,World]\![send,websocket-binary,wss://example.com/chat,SGVsbG8=]\![close,websocket,wss://example.com/chat,1001]\![cancel,websocket,wss://example.com/chat]"#
    ) == [
        .webSocket(.connect(url: "wss://example.com/chat", eventID: "OnChat", headers: ["Authorization: token"], protocolName: "chat")),
        .webSocket(.sendText(url: "wss://example.com/chat", value: "Hello\r\nWorld")),
        .webSocket(.sendBinary(url: "wss://example.com/chat", value: Data("Hello".utf8))),
        .webSocket(.close(url: "wss://example.com/chat", code: 1001)),
        .webSocket(.cancel(url: "wss://example.com/chat"))
    ])
}

@Test
func `parses property system environment and commands`() {
    #expect(SakuraScriptParser().parse(
        #"%property[baseware.name]\![get,property,OnProperties,system.year,currentghost.name]\![set,property,currentghost.shelllist(master).menu,hidden]"#
    ) == [
        .property("baseware.name"),
        .getProperties(eventID: "OnProperties", properties: ["system.year", "currentghost.name"]),
        .setProperty(property: "currentghost.shelllist(master).menu", value: "hidden")
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
        #"\![set,balloontimeout,1200]\![set,balloontimeout,0]\![set,balloontimeout]\![set,balloonwait,1.5]\![set,balloonwait,75%]\![set,balloonwait,20ms]\![set,balloonwait]\![set,balloonoffset,@100,-50]\![set,balloonalign,top]\![set,balloonalign,invalid]\![set,balloonmarker,更新中]\![set,balloonmarker]\![set,balloonnum,download.zip,2,5]\![set,balloonnum,,,]\![set,serikotalk,false]\![set,serikotalk,true]\![set,autoscroll,disable]\![set,autoscroll,enable]"#
    ) == [
        .balloonTimeout(.milliseconds(1200)),
        .balloonTimeout(.disabled),
        .balloonTimeout(.defaultValue),
        .balloonWait(.multiplier(1.5)),
        .balloonWait(.multiplier(0.75)),
        .balloonWait(.milliseconds(20)),
        .balloonWait(.defaultValue),
        .balloonOffset(
            x: SakuraScriptBalloonCoordinate(value: 100, isRelative: true),
            y: SakuraScriptBalloonCoordinate(value: -50, isRelative: false)
        ),
        .balloonAlignment(.top),
        .balloonAlignment(.none),
        .balloonMarker("更新中"),
        .balloonMarker(""),
        .balloonNumber(file: "download.zip", current: "2", maximum: "5"),
        .balloonNumber(file: "", current: "", maximum: ""),
        .serikoTalk(false),
        .serikoTalk(true),
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
func `parses numeric balloon cursor moves`() {
    #expect(SakuraScriptParser().parse(#"\_l[0,0]\_l[,@12]\_l[@-30,]\_l[1.5em,@+70%]\_l[2lh,]"#) == [
        .cursorMove(
            x: SakuraScriptBalloonCoordinate(value: 0, isRelative: false),
            y: SakuraScriptBalloonCoordinate(value: 0, isRelative: false)
        ),
        .cursorMove(
            x: nil,
            y: SakuraScriptBalloonCoordinate(value: 12, isRelative: true)
        ),
        .cursorMove(
            x: SakuraScriptBalloonCoordinate(value: -30, isRelative: true),
            y: nil
        ),
        .cursorMove(
            x: SakuraScriptBalloonCoordinate(value: 1.5, isRelative: false, unit: .em),
            y: SakuraScriptBalloonCoordinate(value: 70, isRelative: true, unit: .percent)
        ),
        .cursorMove(
            x: SakuraScriptBalloonCoordinate(value: 2, isRelative: false, unit: .lineHeight),
            y: nil
        )
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
func `parses online user break and sync object controls`() {
    #expect(SakuraScriptParser().parse(
        #"\![enter,onlinemode]\![leave,onlinemode]\![enter,nouserbreakmode]\![leave,nouserbreakmode]\![set,syncobject,ready]\![wait,syncobject,ready,--timeout=250]\![reset,syncobject,ready]"#
    ) == [
        .onlineMode(true),
        .onlineMode(false),
        .noUserBreakMode(true),
        .noUserBreakMode(false),
        .syncObjectSet("ready"),
        .syncObjectWait(name: "ready", timeoutMilliseconds: 250),
        .syncObjectReset("ready")
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

@Test
func `parses close ghost, AITalk, stayontop and windowstate commands`() {
    #expect(SakuraScriptParser().parse(#"\-\a\v\![set,windowstate,stayontop]\![set,windowstate,!stayontop]"#) == [
        .contentAction(.closeGhost),
        .raisedEvent(id: "OnAITalk", arguments: []),
        .stayOnTop(true),
        .stayOnTop(true),
        .stayOnTop(false)
    ])
}

@Test
func `parses rss-get and rss-post commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![execute,rss-get,https://example.test/feed.xml,--async=OnFeedLoaded]\![execute,rss-post,https://example.test/rss,--param=q=news]"#
    ) == [
        .http(SakuraScriptHTTPRequest(
            method: "GET",
            url: "https://example.test/feed.xml",
            eventID: "OnFeedLoaded",
            waitsForCompletion: false,
            isFeed: true
        )),
        .http(SakuraScriptHTTPRequest(
            method: "POST",
            url: "https://example.test/rss",
            eventID: nil,
            waitsForCompletion: false,
            parameters: ["q=news"],
            isFeed: true
        ))
    ])
}

@Test
func `parses http cancellation and inputbox close commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![cancel,http,https://example.test/file.zip]\![cancel,http]\![close,inputbox,OnNameInput]\![close,inputbox,__SYSTEM_ALL_INPUT__]"#
    ) == [
        .cancelHTTP(url: "https://example.test/file.zip"),
        .cancelHTTP(url: nil),
        .closeInputBox(id: "OnNameInput"),
        .closeInputBox(id: "__SYSTEM_ALL_INPUT__")
    ])
}

@Test
func `parses other ghost timer commands and cancellation`() {
    #expect(SakuraScriptParser().parse(
        #"\![timerraiseother,30000,0,Emily,OnRoastedPotato,sweet potato]\![timerraiseother,0,1,Emily]\![timernotifyother,1000,1,*,OnPing]"#
    ) == [
        .otherTimerEvent(
            target: "Emily",
            milliseconds: 30000,
            repeats: true,
            reflectsResponse: true,
            id: "OnRoastedPotato",
            arguments: ["sweet potato"]
        ),
        .otherTimerEvent(
            target: "Emily",
            milliseconds: 0,
            repeats: false,
            reflectsResponse: true,
            id: "",
            arguments: []
        ),
        .otherTimerEvent(
            target: "*",
            milliseconds: 1000,
            repeats: false,
            reflectsResponse: false,
            id: "OnPing",
            arguments: []
        )
    ])
}

@Test
func `parses install and archive execution commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![execute,install,path,/tmp/test.nar]\![execute,install,url,https://example.test/ghost.nar,nar]\![execute,extractarchive,/tmp/a.zip,/tmp/dest,--event=OnExtractComplete,--password=secret]\![execute,compressarchive,/tmp/out.zip,/tmp/src]"#
    ) == [
        .contentAction(.install(.path("/tmp/test.nar"))),
        .contentAction(.install(.url("https://example.test/ghost.nar", type: "nar"))),
        .archive(.extract(
            archivePath: "/tmp/a.zip",
            destinationPath: "/tmp/dest",
            eventID: "OnExtractComplete",
            password: "secret"
        )),
        .archive(.compress(
            archivePath: "/tmp/out.zip",
            sourceDirectoryPath: "/tmp/src",
            eventID: nil,
            password: nil
        ))
    ])
}

@Test
func `parses expanded HTML and XML entity references`() {
    #expect(SakuraScriptParser().parse(
        #"\&[yen]\&[copy]\&[trade]\&[euro]\&[half_solidus]\&[deg]\&[plusmn]\&[hellip]"#
    ) == [
        .text("¥"),
        .text("©"),
        .text("™"),
        .text("€"),
        .text("/"),
        .text("°"),
        .text("±"),
        .text("…")
    ])
}

@Test
func `parses other ghost talk and surface change commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![otherghosttalk,Emily,\0\s[0]こんにちは]\![othersurfacechange,Emily,0,10]"#
    ) == [
        .otherGhostTalk(target: "Emily", script: #"\0\s[0]こんにちは"#),
        .otherSurfaceChange(target: "Emily", scope: 0, surfaceID: 10)
    ])
}

@Test
func `parses communicatebox and teachbox commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![open,communicatebox,おはよう]\![open,teachbox]"#
    ) == [
        .communicateBox(initialValue: "おはよう"),
        .teachBox(initialValue: "")
    ])
}

@Test
func `parses reload content actions and createnar commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![reload,ghost]\![reload,shell]\![reload,balloon]\![reloadsurface]\![reload,surface]\![reload,shiori]\![reload,descript]\![reload,descript,shell balloon]\![execute,createnar,/tmp/out.nar,/tmp/target,--event=OnExported]"#
    ) == [
        .contentAction(.reloadGhost),
        .contentAction(.reloadShell),
        .contentAction(.reloadBalloon),
        .contentAction(.reloadShell),
        .contentAction(.reloadShell),
        .contentAction(.reloadGhost),
        .contentAction(.reloadGhost),
        .contentAction(.reloadShell),
        .contentAction(.reloadBalloon),
        .archive(.createNar(
            narPath: "/tmp/out.nar",
            sourceDirectoryPath: "/tmp/target",
            eventID: "OnExported"
        ))
    ])
}

@Test
func `parses negative balloon surface ID for hiding balloon`() {
    #expect(SakuraScriptParser().parse(#"\b[-1]"#) == [
        .balloonSurface(-1)
    ])
}

@Test
func `parses character separation and approach commands`() {
    #expect(SakuraScriptParser().parse(#"\4\5"#) == [
        .separateCharacters,
        .approachCharacters
    ])
}

@Test
func `parses old format choice commands with and without marker`() {
    #expect(SakuraScriptParser().parse(#"\q[0][はい]\q*[1][いいえ]\q2[talkinterval][普通]"#) == [
        .choice(label: "はい", id: "0", arguments: []),
        .lineBreak(scale: nil),
        .marker,
        .choice(label: "いいえ", id: "1", arguments: []),
        .lineBreak(scale: nil),
        .choice(label: "普通", id: "talkinterval", arguments: []),
        .lineBreak(scale: nil)
    ])
}

@Test
func `parses move commands`() {
    #expect(SakuraScriptParser().parse(#"\![move,100,200,1000]\![moveasync,--X=50,--Y=60,--time=500]"#) == [
        .moveSurface(x: 100, y: 200, time: 1000, isAsync: false, options: ["100", "200", "1000"]),
        .moveSurface(x: 50, y: 60, time: 500, isAsync: true, options: ["--X=50", "--Y=60", "--time=500"])
    ])
}

@Test
func `parses collision display mode commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![enter,collisionmode]\![enter,collisionmode,rect]\![leave,collisionmode]"#
    ) == [
        .collisionMode(enabled: true, showsNames: true),
        .collisionMode(enabled: true, showsNames: false),
        .collisionMode(enabled: false, showsNames: true)
    ])
}

@Test
func `parses passive and induction mode commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![enter,passivemode]\![leave,passivemode]\![enter,inductionmode]\![leave,inductionmode]"#
    ) == [
        .interactionMode(.passive, enabled: true),
        .interactionMode(.passive, enabled: false),
        .interactionMode(.induction, enabled: true),
        .interactionMode(.induction, enabled: false)
    ])
}

@Test
func `parses open ui dialog and utility commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![open,configurationdialog]\![open,readme]\![open,help]\![open,file,/tmp/a.txt]\![open,folder,/tmp]\![execute,dumpsurface,/tmp/out.png,--event=OnDumped]\![execute,createupdatedata,/tmp/dir,--event=OnUpdated]"#
    ) == [
        .contentAction(.openConfigurationDialog),
        .contentAction(.openReadme),
        .contentAction(.openHelp),
        .contentAction(.openFile("/tmp/a.txt")),
        .contentAction(.openFolder("/tmp")),
        .archive(.dumpSurface(path: "/tmp/out.png", eventID: "OnDumped")),
        .archive(.createUpdateData(directoryPath: "/tmp/dir", eventID: "OnUpdated"))
    ])
}

@Test
func `parses system dialog commands and options`() {
    #expect(SakuraScriptParser().parse(
        #"\![open,dialog,open,--title=辞書,--dir=/tmp,--filter=辞書|*.dic,--id=OnPick]\![open,dialog,save,--name=test,--ext=txt,--id=save1]\![open,dialog,folder,--id=folder1]\![open,dialog,color,--color=255 0 128,--id=color1]\![close,dialog,__SYSTEM_ALL_DIALOG__]"#
    ) == [
        .systemDialog(.init(
            kind: .open, id: "OnPick", title: "辞書", directory: "/tmp", filter: "辞書|*.dic"
        )),
        .systemDialog(.init(kind: .save, id: "save1", fileExtension: "txt", name: "test")),
        .systemDialog(.init(kind: .folder, id: "folder1")),
        .systemDialog(.init(kind: .color, id: "color1", color: "255 0 128")),
        .closeSystemDialog(id: "__SYSTEM_ALL_DIALOG__")
    ])
}

@Test
func `parses createupdatedata without arguments for the current ghost`() {
    #expect(SakuraScriptParser().parse(#"\![execute,createupdatedata]"#) == [
        .archive(.createUpdateData(directoryPath: nil, eventID: nil))
    ])
}

@Test
func `parses async sound playback and sound wait commands`() {
    #expect(SakuraScriptParser().parse(#"\_v[test.wav]\_V"#) == [
        .sound(.play(file: "test.wav", loop: false, options: [])),
        .sound(.wait)
    ])
}

@Test
func `parses inline balloon image commands`() {
    #expect(SakuraScriptParser().parse(#"\_b[test.png,inline]\_b[sample.png,inline,opaque]"#) == [
        .inlineImage(path: "test.png", isOpaque: false, options: []),
        .inlineImage(path: "sample.png", isOpaque: true, options: ["opaque"])
    ])
    #expect(SakuraScriptParser().parse(#"\_b[test.png,50,100]\_b[sample.png,-5,20,--option=opaque]"#) == [
        .positionedImage(path: "test.png", x: 50, y: 100, isOpaque: false, options: []),
        .positionedImage(path: "sample.png", x: -5, y: 20, isOpaque: true, options: ["--option=opaque"])
    ])
}

@Test
func `parses zorder and sticky window commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,zorder,1,0]\![reset,zorder]\![set,sticky-window,1,0]\![reset,sticky-window]"#
    ) == [
        .setZOrder(["1", "0"]),
        .resetZOrder,
        .setStickyWindows([1, 0]),
        .resetStickyWindows
    ])
}

@Test
func `parses fixed position commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![set,position,120,-30,1]\![reset,position]"#
    ) == [
        .setPosition(x: 120, y: -30, scope: 1),
        .resetPosition
    ])
}

@Test
func `parses plugin raise and notify commands`() {
    #expect(SakuraScriptParser().parse(
        #"\![raiseplugin,clock,OnAlarm,one,two]\![notifyplugin,clock,OnQuiet]"#
    ) == [
        .pluginEvent(target: "clock", id: "OnAlarm", arguments: ["one", "two"], reflectsResponse: true),
        .pluginEvent(target: "clock", id: "OnQuiet", arguments: [], reflectsResponse: false)
    ])
}

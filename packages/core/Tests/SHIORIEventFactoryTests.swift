import Testing
@testable import UtataneCore

@Test func `startup and switch events follow UKADOC references`() {
    #expect(SHIORIEventFactory.firstBoot(vanishCount: 2) == .shiori(
        id: "OnFirstBoot", references: [0: "2"]
    ))
    #expect(SHIORIEventFactory.boot(shellName: "master") == .shiori(
        id: "OnBoot", references: [0: "master"]
    ))
    #expect(SHIORIEventFactory.ghostChanged(
        previousCharacterName: "Previous",
        previousScript: #"\0bye\e"#,
        previousGhostName: "Previous Ghost",
        previousGhostPath: "/ghost/previous",
        shellName: "master"
    ) == .shiori(id: "OnGhostChanged", references: [
        0: "Previous", 1: #"\0bye\e"#, 2: "Previous Ghost", 3: "/ghost/previous", 7: "master"
    ]))
    #expect(SHIORIEventFactory.ghostChanging(
        characterName: "Next",
        mode: "automatic",
        ghostName: "Next Ghost",
        ghostPath: "/ghost/next"
    ) == .shiori(id: "OnGhostChanging", references: [
        0: "Next", 1: "automatic", 2: "Next Ghost", 3: "/ghost/next"
    ]))
}

@Test func `ghost call and vanish events follow UKADOC references`() {
    #expect(SHIORIEventFactory.ghostCalled(
        callerCharacterName: "Caller",
        callerScript: "",
        callerGhostName: "Caller Ghost",
        callerGhostPath: "/ghost/caller",
        shellName: "master"
    ) == .shiori(id: "OnGhostCalled", references: [
        0: "Caller", 1: "", 2: "Caller Ghost", 3: "/ghost/caller", 7: "master"
    ]))
    #expect(SHIORIEventFactory.ghostCalling(
        characterName: "Called",
        mode: "manual",
        ghostName: "Called Ghost",
        ghostPath: "/ghost/called"
    ) == .shiori(id: "OnGhostCalling", references: [
        0: "Called", 1: "manual", 2: "Called Ghost", 3: "/ghost/called"
    ]))
    #expect(SHIORIEventFactory.ghostCallComplete(
        characterName: "Called",
        startupScript: #"\0hello\e"#,
        ghostName: "Called Ghost",
        shellName: "master"
    ) == .shiori(id: "OnGhostCallComplete", references: [
        0: "Called", 1: #"\0hello\e"#, 2: "Called Ghost", 7: "master"
    ]))
    #expect(SHIORIEventFactory.otherGhostBooted(
        characterName: "Called",
        startupScript: #"\0hello\e"#,
        ghostName: "Called Ghost",
        shellName: "master"
    ) == .shiori(id: "OnOtherGhostBooted", references: [
        0: "Called", 1: #"\0hello\e"#, 2: "Called Ghost", 7: "master"
    ]))
    #expect(SHIORIEventFactory.otherGhostClosed(
        characterName: "Called",
        finalScript: #"\0bye\e"#,
        ghostName: "Called Ghost",
        shellName: "master"
    ) == .shiori(id: "OnOtherGhostClosed", references: [
        0: "Called", 1: #"\0bye\e"#, 2: "Called Ghost", 7: "master"
    ]))
    #expect(SHIORIEventFactory.vanished(
        characterName: "Gone",
        vanishScript: #"\0bye\e"#,
        ghostName: "Gone Ghost",
        shellName: "master"
    ) == .shiori(id: "OnVanished", references: [
        0: "Gone", 1: #"\0bye\e"#, 2: "Gone Ghost", 7: "master"
    ]))
}

@Test func `shell change events follow UKADOC reference order`() {
    #expect(SHIORIEventFactory.shellChanging(
        newShellName: "new",
        previousShellName: "old",
        newShellPath: "/ghost/shell/new"
    ) == .shiori(id: "OnShellChanging", references: [
        0: "new", 1: "old", 2: "/ghost/shell/new"
    ]))
    #expect(SHIORIEventFactory.shellChanged(
        shellName: "new",
        ghostName: "ghost",
        shellPath: "/ghost/shell/new"
    ) == .shiori(id: "OnShellChanged", references: [
        0: "new", 1: "ghost", 2: "/ghost/shell/new"
    ]))
}

@Test func `text drop replaces line feeds with byte one`() {
    #expect(SHIORIEventFactory.textDrop("first\nsecond", scope: 2) == .shiori(
        id: "OnTextDrop",
        references: [0: "first\u{1}second", 1: "2"]
    ))
}

@Test func `teach and communicate events follow UKADOC references`() {
    #expect(SHIORIEventFactory.communicateInputCancel == .shiori(
        id: "OnCommunicateInputCancel",
        references: [0: "", 1: "cancel"]
    ))
    #expect(SHIORIEventFactory.teachStart == .shiori(id: "OnTeachStart", references: [:]))
    #expect(SHIORIEventFactory.teachInputCancel == .shiori(
        id: "OnTeachInputCancel",
        references: [0: "", 1: "cancel"]
    ))
    #expect(SHIORIEventFactory.teach(history: ["one", "two"]) == .shiori(
        id: "OnTeach",
        references: [0: "one", 1: "two"]
    ))
}

@Test func `update lifecycle events follow UKADOC references`() {
    #expect(SHIORIEventFactory.updateProcessExec(reason: "script") == .shiori(
        id: "OnUpdateProcessExec",
        references: [0: "script"]
    ))
    #expect(SHIORIEventFactory.updateBegin(
        name: "ghost",
        path: "/ghost",
        updateType: "ghost",
        reason: "manual"
    ) == .shiori(id: "OnUpdateBegin", references: [
        0: "ghost", 1: "/ghost", 3: "ghost", 4: "manual"
    ]))
    #expect(SHIORIEventFactory.updateReady(
        files: ["ghost/master/dictionary.dic", "shell/master/surface0.png"],
        updateType: "ghost",
        reason: "manual"
    ) == .shiori(id: "OnUpdateReady", references: [
        0: "1",
        1: "ghost/master/dictionary.dic,shell/master/surface0.png",
        3: "ghost",
        4: "manual"
    ]))
    #expect(SHIORIEventFactory.updateComplete(
        changedFiles: ["ghost/master/dictionary.dic"],
        updateType: "ghost",
        reason: "auto"
    ) == .shiori(id: "OnUpdateComplete", references: [
        0: "changed", 1: "ghost/master/dictionary.dic", 3: "ghost", 4: "auto"
    ]))
    #expect(SHIORIEventFactory.updateComplete(
        changedFiles: [],
        updateType: "ghost",
        reason: "auto"
    ) == .shiori(id: "OnUpdateComplete", references: [
        0: "none", 1: "", 3: "ghost", 4: "auto"
    ]))
    #expect(SHIORIEventFactory.updateFailure(
        failureReason: "404",
        failurePath: "ghost/master/dictionary.dic",
        updateType: "ghost",
        reason: "manual"
    ) == .shiori(id: "OnUpdateFailure", references: [
        0: "404", 1: "ghost/master/dictionary.dic", 3: "ghost", 4: "manual"
    ]))
}

@Test func `update file progress events follow UKADOC references`() {
    #expect(SHIORIEventFactory.updateDownloadBegin(
        path: "ghost/master/dictionary.dic",
        index: 1,
        total: 3,
        updateType: "ghost",
        reason: "manual"
    ) == .shiori(id: "OnUpdate.OnDownloadBegin", references: [
        0: "ghost/master/dictionary.dic", 1: "1", 2: "2", 3: "ghost", 4: "manual"
    ]))

    let path = "ghost/master/dictionary.dic"
    let expected = "expected-md5"
    let actual = "actual-md5"
    let updateType = "ghost"
    let reason = "manual"
    let expectedReferences = [0: path, 1: expected, 2: actual, 3: updateType, 4: reason]
    #expect(SHIORIEventFactory.updateMD5CompareBegin(
        path: path,
        expected: expected,
        actual: actual,
        updateType: updateType,
        reason: reason
    ) == .shiori(id: "OnUpdate.OnMD5CompareBegin", references: expectedReferences))
    #expect(SHIORIEventFactory.updateMD5CompareComplete(
        path: path,
        expected: expected,
        actual: actual,
        updateType: updateType,
        reason: reason
    ) == .shiori(id: "OnUpdate.OnMD5CompareComplete", references: expectedReferences))
    #expect(SHIORIEventFactory.updateMD5CompareFailure(
        path: path,
        expected: expected,
        actual: actual,
        updateType: updateType,
        reason: reason
    ) == .shiori(id: "OnUpdate.OnMD5CompareFailure", references: expectedReferences))
}

@Test func `other update lifecycle events follow UKADOC references`() {
    #expect(SHIORIEventFactory.updateOtherBegin(
        name: "Balloon",
        path: "/balloon",
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOtherBegin", references: [
        0: "Balloon", 1: "/balloon", 3: "balloon", 4: "manual"
    ]))
    #expect(SHIORIEventFactory.updateOtherReady(
        files: ["balloons0.png", "descript.txt"],
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOtherReady", references: [
        0: "1", 1: "balloons0.png,descript.txt", 3: "balloon", 4: "manual"
    ]))
    #expect(SHIORIEventFactory.updateOtherComplete(
        changedFiles: [],
        updateType: "balloon",
        reason: "auto"
    ) == .shiori(id: "OnUpdateOtherComplete", references: [
        0: "none", 1: "", 3: "balloon", 4: "auto"
    ]))
    #expect(SHIORIEventFactory.updateOtherFailure(
        failureReason: "md5 miss",
        failurePath: "balloons0.png",
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOtherFailure", references: [
        0: "md5 miss", 1: "balloons0.png", 3: "balloon", 4: "manual"
    ]))
}

@Test func `other update file progress follows UKADOC reference differences`() {
    #expect(SHIORIEventFactory.updateOtherDownloadBegin(
        path: "balloons0.png",
        index: 0,
        total: 2,
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOther.OnDownloadBegin", references: [
        0: "balloons0.png", 1: "0", 2: "1", 3: "balloon", 4: "manual"
    ]))
    #expect(SHIORIEventFactory.updateOtherMD5CompareBegin(
        path: "balloons0.png",
        expected: "expected",
        actual: "actual",
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOther.OnMD5CompareBegin", references: [
        0: "balloons0.png", 1: "expected", 2: "actual", 3: "balloon", 4: "manual"
    ]))

    let resultReferences = [1: "expected", 2: "actual", 3: "balloon", 4: "manual"]
    #expect(SHIORIEventFactory.updateOtherMD5CompareComplete(
        expected: "expected",
        actual: "actual",
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOther.OnMD5CompareComplete", references: resultReferences))
    #expect(SHIORIEventFactory.updateOtherMD5CompareFailure(
        expected: "expected",
        actual: "actual",
        updateType: "balloon",
        reason: "manual"
    ) == .shiori(id: "OnUpdateOther.OnMD5CompareFailure", references: resultReferences))
}

@Test func `update check events use the script reason required by UKADOC`() {
    #expect(SHIORIEventFactory.updateCheckComplete(
        changedFiles: ["ghost/master/dictionary.dic"],
        updateType: "ghost"
    ) == .shiori(id: "OnUpdateCheckComplete", references: [
        0: "changed",
        1: "ghost/master/dictionary.dic",
        3: "ghost",
        4: "script"
    ]))
    #expect(SHIORIEventFactory.updateCheckComplete(
        changedFiles: [],
        updateType: "balloon"
    ) == .shiori(id: "OnUpdateCheckComplete", references: [
        0: "none",
        1: "",
        3: "balloon",
        4: "script"
    ]))
    #expect(SHIORIEventFactory.updateCheckFailure(failureReason: "timeout") == .shiori(
        id: "OnUpdateCheckFailure",
        references: [0: "timeout", 4: "script"]
    ))
}

@Test func `aggregate update results occupy consecutive references`() {
    let extended = [
        "Ghost\u{1}ghost\u{1}OK\u{1}2",
        "Balloon\u{1}balloon\u{1}NG\u{1}md5 miss\u{1}balloons0.png"
    ]
    #expect(SHIORIEventFactory.updateResultExtended(
        records: extended,
        checkOnly: false
    ) == .shiori(id: "OnUpdateResultEx", references: [0: extended[0], 1: extended[1]]))
    #expect(SHIORIEventFactory.updateResultExtended(
        records: extended,
        checkOnly: true
    ) == .shiori(id: "OnUpdateCheckResultEx", references: [0: extended[0], 1: extended[1]]))

    let legacy = ["ghost\u{1}OK\u{1}2", "balloon\u{1}NG\u{1}md5 miss\u{1}balloons0.png"]
    #expect(SHIORIEventFactory.updateResultLegacy(
        records: legacy,
        checkOnly: false
    ) == .shiori(id: "OnUpdateResult", references: [0: legacy[0], 1: legacy[1]]))
    #expect(SHIORIEventFactory.updateResultLegacy(
        records: legacy,
        checkOnly: true
    ) == .shiori(id: "OnUpdateCheckResult", references: [0: legacy[0], 1: legacy[1]]))
    #expect(SHIORIEventFactory.updateResultExplorer(records: legacy) == .shiori(
        id: "OnUpdateResultExplorer",
        references: [0: legacy[0], 1: legacy[1]]
    ))
}

@Test func `recommend site choice identifies the menu source and selected scope`() {
    #expect(SHIORIEventFactory.recommendsiteChoice(
        title: "Site",
        target: "https://example.test/",
        banner: "banner.png",
        kind: "recommend",
        scope: 1,
        index: 2
    ) == .shiori(id: "OnRecommendsiteChoice", references: [
        0: "Site",
        1: "https://example.test/",
        2: "banner.png",
        3: "recommend",
        4: "1",
        5: "2"
    ]))
}

@Test func `anchor selection events follow the extended then legacy reference shapes`() {
    #expect(SHIORIEventFactory.anchorSelectExtended(
        label: "アンカー",
        id: "keyword",
        arguments: ["extra", "value"]
    ) == .shiori(id: "OnAnchorSelectEx", references: [
        0: "アンカー", 1: "keyword", 2: "extra", 3: "value"
    ]))
    #expect(SHIORIEventFactory.anchorSelect(id: "keyword") == .shiori(
        id: "OnAnchorSelect",
        references: [0: "keyword"]
    ))
}

@Test func `choice selection events preserve the label ID and arguments`() {
    #expect(SHIORIEventFactory.choiceSelectExtended(
        label: "秋",
        id: "LikeSeason",
        arguments: ["月見", "菊"]
    ) == .shiori(id: "OnChoiceSelectEx", references: [
        0: "秋", 1: "LikeSeason", 2: "月見", 3: "菊"
    ]))
    #expect(SHIORIEventFactory.choiceSelect(
        id: "LikeSeason",
        arguments: ["月見", "菊"]
    ) == .choice(id: "LikeSeason", arguments: ["月見", "菊"]))
}

@Test func `input events preserve SSP IDs values and cancellation reasons`() {
    #expect(SHIORIEventFactory.userInput(
        id: "name",
        value: "Ria",
        supplementalValue: "detail",
        additionalReferences: ["extra"]
    ) == .shiori(id: "OnUserInput", references: [
        0: "name", 1: "Ria", 2: "detail", 3: "extra"
    ]))
    #expect(SHIORIEventFactory.userInput(
        id: "OnNameInput",
        value: "Ria",
        additionalReferences: ["extra"]
    ) == .shiori(id: "OnNameInput", references: [
        0: "Ria", 1: "", 2: "extra"
    ]))
    #expect(SHIORIEventFactory.userInputCancel(id: "name", timedOut: true) == .shiori(
        id: "OnUserInputCancel",
        references: [0: "name", 1: "timeout", 2: ""]
    ))
}

@Test func `balloon and name lookup events follow UKADOC references`() {
    #expect(SHIORIEventFactory.balloonChange(
        name: "Test Balloon",
        path: "/Users/test/balloon/test"
    ) == .shiori(id: "OnBalloonChange", references: [
        0: "Test Balloon", 1: "/Users/test/balloon/test"
    ]))
    #expect(SHIORIEventFactory.nsLookup(
        id: "OnNSLookupComplete",
        eventLabel: "lookup-test",
        host: "example.test",
        reverse: false,
        result: "192.0.2.1"
    ) == .shiori(id: "OnNSLookupComplete", references: [
        0: "lookup-test", 1: "example.test", 2: "lookup", 3: "192.0.2.1"
    ]))
    #expect(SHIORIEventFactory.nsLookup(
        id: "OnNSLookupFailure",
        eventLabel: "reverse-test",
        host: "192.0.2.1",
        reverse: true,
        result: nil
    ) == .shiori(id: "OnNSLookupFailure", references: [
        0: "reverse-test", 1: "192.0.2.1", 2: "reverse"
    ]))
}

@Test func `headline events follow UKADOC references`() {
    #expect(SHIORIEventFactory.headlinesenseBegin(
        name: "News",
        url: "https://example.test/"
    ) == .shiori(id: "OnHeadlinesenseBegin", references: [
        0: "News", 1: "https://example.test/"
    ]))
    #expect(SHIORIEventFactory.headlinesenseFind(
        name: "News",
        url: "https://example.test/1",
        phase: "First and Last",
        headline: "Headline"
    ) == .shiori(id: "OnHeadlinesense.OnFind", references: [
        0: "News", 1: "https://example.test/1", 2: "First and Last", 3: "Headline"
    ]))
    #expect(SHIORIEventFactory.headlinesenseComplete == .shiori(
        id: "OnHeadlinesenseComplete",
        references: [0: "no update"]
    ))
    #expect(SHIORIEventFactory.headlinesenseFailure(reason: "can't analyze") == .shiori(
        id: "OnHeadlinesenseFailure",
        references: [0: "can't analyze"]
    ))
}

@Test func `RSS events follow UKADOC references`() {
    let records = [
        0: "News",
        1: "https://example.test/",
        2: "First\u{1}https://example.test/1\u{1}2026,9,16,12,30,0\u{1}Author\u{1}Summary"
    ]
    #expect(SHIORIEventFactory.rssBegin(
        name: "News",
        url: "https://example.test/feed.xml"
    ) == .shiori(id: "OnRSSBegin", references: [
        0: "News", 1: "https://example.test/feed.xml"
    ]))
    #expect(SHIORIEventFactory.rssComplete(references: records) == .shiori(
        id: "OnRSSComplete", references: records
    ))
    #expect(SHIORIEventFactory.rssNoUpdate == .shiori(
        id: "OnRSSComplete", references: [0: "no update"]
    ))
    #expect(SHIORIEventFactory.rssFailure(reason: "can't analyze") == .shiori(
        id: "OnRSSFailure", references: [0: "can't analyze"]
    ))
}

@Test func `execute HTTP events select default and custom IDs`() throws {
    let references = [
        0: "get",
        1: "download",
        2: "https://example.test/data",
        3: "/ghost/master/var/data",
        4: "200",
        5: "session=1",
        6: "Content-Type: text/plain"
    ]
    #expect(try SHIORIEventFactory.executeHTTPComplete(
        eventID: "download",
        method: "GET",
        url: #require(references[2]),
        result: #require(references[3]),
        statusCode: #require(references[4]),
        cookie: #require(references[5]),
        headers: #require(references[6])
    ) == .shiori(id: "OnExecuteHTTPComplete", references: references))

    var failureReferences = references
    failureReferences[1] = "OnDownload"
    failureReferences[3] = ""
    failureReferences[4] = "timeout"
    failureReferences[5] = ""
    failureReferences[6] = ""
    #expect(try SHIORIEventFactory.executeHTTPFailure(
        eventID: "OnDownload",
        method: "GET",
        url: #require(references[2]),
        reason: "timeout"
    ) == .shiori(id: "OnDownloadFailure", references: failureReferences))
}

@Test func `execute RSS events preserve record order and parse failures`() {
    let records = [
        "First\u{1}https://example.test/1\u{1}2026,9,16,12,30,0\u{1}Author\u{1}Summary",
        "Second\u{1}https://example.test/2\u{1}\u{1}\u{1}"
    ]
    #expect(SHIORIEventFactory.executeRSSComplete(
        eventID: "feed",
        records: records
    ) == .shiori(id: "OnExecuteRSSComplete", references: [0: records[0], 1: records[1]]))
    #expect(SHIORIEventFactory.executeRSSComplete(
        eventID: "OnFeed",
        records: records
    ) == .shiori(id: "OnFeed", references: [0: records[0], 1: records[1]]))
    #expect(SHIORIEventFactory.executeRSSFailure(
        eventID: "OnFeed",
        method: "POST",
        url: "https://example.test/feed.xml",
        reason: "parse"
    ) == .shiori(id: "OnFeedFailure", references: [
        0: "post", 1: "OnFeed", 2: "https://example.test/feed.xml", 3: "", 4: "parse", 5: "", 6: ""
    ]))
}

@Test func `SNTP events preserve comparison references`() {
    let extended = [0: "https://time.example", 3: "1.500", 4: "1500"]
    let legacy = [0: "https://time.example", 3: "1", 4: "1500"]
    #expect(SHIORIEventFactory.sntpBegin(server: "https://time.example") == .shiori(
        id: "OnSNTPBegin", references: [0: "https://time.example"]
    ))
    #expect(SHIORIEventFactory.sntpCompareExtended(references: extended) == .shiori(
        id: "OnSNTPCompareEx", references: extended
    ))
    #expect(SHIORIEventFactory.sntpCompare(references: legacy) == .shiori(
        id: "OnSNTPCompare", references: legacy
    ))
    #expect(SHIORIEventFactory.sntpFailure(server: "https://time.example") == .shiori(
        id: "OnSNTPFailure", references: [0: "https://time.example"]
    ))
}

@Test func `other ghost delivery failures preserve the attempted event`() {
    #expect(SHIORIEventFactory.otherEventFailure(
        target: "Emily",
        eventID: "OnPing",
        arguments: ["one", "two"],
        reflectsResponse: true,
        reason: "notfound"
    ) == .shiori(id: "OnRaiseOtherFailure", references: [
        0: "notfound", 1: "Emily", 2: "OnPing", 3: "one", 4: "two"
    ]))
    #expect(SHIORIEventFactory.otherEventFailure(
        target: "Emily",
        eventID: "OnNotice",
        arguments: [],
        reflectsResponse: false,
        reason: "notfound"
    ) == .shiori(id: "OnNotifyOtherFailure", references: [
        0: "notfound", 1: "Emily", 2: "OnNotice"
    ]))
}

@Test func `archive events select standard and custom IDs`() {
    #expect(SHIORIEventFactory.extractArchiveComplete(
        eventID: "extract-task",
        fileCount: 3,
        compressedBytes: 120,
        uncompressedBytes: 450
    ) == .shiori(id: "OnExtractArchiveComplete", references: [
        0: "extract-task", 1: "3", 2: "120", 3: "450"
    ]))
    #expect(SHIORIEventFactory.extractArchiveFailure(
        eventID: "OnExtractDone",
        reason: "corrupted"
    ) == .shiori(id: "OnExtractDoneFailure", references: [
        0: "OnExtractDone", 1: "corrupted"
    ]))
    #expect(SHIORIEventFactory.compressArchiveComplete(
        eventID: "OnCompressed",
        fileCount: 2,
        compressedBytes: 100,
        uncompressedBytes: 300
    ) == .shiori(id: "OnCompressed", references: [
        0: "OnCompressed", 1: "2", 2: "100", 3: "300"
    ]))
    #expect(SHIORIEventFactory.compressArchiveFailure(
        eventID: "compress-task",
        reason: "directory not found"
    ) == .shiori(id: "OnCompressArchiveFailure", references: [
        0: "compress-task", 1: "directory not found"
    ]))
}

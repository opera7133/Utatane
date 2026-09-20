import Foundation
import Testing
import UtataneCore
@testable import UtataneFirstNative

@Test func `extracts Delphi CP932 strings from an i386 DLL code section`() throws {
    let script = "\\0\\s0さくら\\1うにゅう"
    let fixture = makePEDLL(strings: [script, "ordinary text"])

    let strings = try FirstDLLAnalyzer(data: fixture).embeddedStrings()

    #expect(strings.map(\.value) == [script, "ordinary text"])
    #expect(strings[0].containsSakuraScript)
    #expect(!strings[1].containsSakuraScript)
    #expect(strings[0].codeReferenceOffsets.count == 1)
    #expect(strings[1].codeReferenceOffsets.isEmpty)
}

@Test func `rejects non PE input`() {
    #expect(throws: FirstDLLAnalysisError.notPortableExecutable) {
        try FirstDLLAnalyzer(data: Data(repeating: 0, count: 128))
    }
}

@Test func `ignores malformed Delphi string candidates`() throws {
    var fixture = makePEDLL(strings: [])
    fixture.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])

    let strings = try FirstDLLAnalyzer(data: fixture).embeddedStrings()

    #expect(strings.isEmpty)
}

@Test func `analyzes an explicitly supplied FIRST DLL`() async throws {
    guard let path = ProcessInfo.processInfo.environment["UTATANE_FIRST_DLL"] else {
        return
    }

    let analyzer = try FirstDLLAnalyzer(contentsOf: URL(filePath: path))
    let strings = try analyzer.embeddedStrings()

    // Keep the fixture outside the repository. These broad checks detect parser
    // regressions without copying or snapshotting any Materia-owned text.
    #expect(strings.count > 1000)
    #expect(strings.count(where: \.containsSakuraScript) > 500)

    let lines = try analyzer.decodedAITXTLines()
    #expect(lines.count == 4845)
    #expect(try analyzer.decodedAITXTRecords().count == 1615)
    #expect(try analyzer.fragments(for: .onBoot).count == 28)
    let baseline = try analyzer.baselineScript(for: .onBoot)
    #expect(baseline.contains("\\0"))
    #expect(baseline.contains("\\1"))

    let master = URL(filePath: path).deletingLastPathComponent()
    let session = try FirstNativeSession(masterDirectoryURL: master)
    #expect(try session.script(forEventID: "OnBoot")?.contains("\\0") == true)
    let firstBoot = try session.firstBootScript()
    #expect(firstBoot.contains("\\0"))
    #expect(!firstBoot.isEmpty)
    #expect(try session.script(forEventID: "OnFirstBoot") == firstBoot)
    #expect(try session.script(forEventID: "OnUnknownEvent") == nil)
    let quizTutorial = try session.quizTutorialScript()
    #expect(!quizTutorial.isEmpty)
    #expect(try session.script(forEventID: "OnQuizTutorial") == quizTutorial)
    #expect(try session.script(forEventID: "OnQuizLeave") == session.quizLeaveScript())
    let quizEntries = try [nil, "return"].map(session.quizEnterScript(reference:))
    #expect(Set(quizEntries).count == 2)
    #expect(quizEntries.allSatisfy { $0.components(separatedBy: "OnQuizStart").count == 7 })
    #expect(try session.script(forEventID: "OnQuizEnter") == quizEntries[0])
    for category in 0 ..< 6 {
        let question = try session.quizQuestion(category: category)
        #expect(question.category == category)
        #expect(question.script.contains("OnQuizInput"))
        #expect(question.script.contains("\\![open,inputbox,OnQuizInput,30000]"))
        #expect(!question.script.contains("OnOpenquizInputBox"))
        if category != 3 {
            #expect(question.script.contains(String(category + 1)))
        }
        #expect(!question.acceptedAnswers.isEmpty)
        #expect(question.acceptedAnswers.allSatisfy { !$0.isEmpty })
        let correct = try session.quizInputScript(
            answer: question.acceptedAnswers[0],
            question: question,
            feedbackChoice: 0
        )
        let incorrect = try session.quizInputScript(
            answer: "UtataneDefinitelyWrong",
            question: question,
            feedbackChoice: 0
        )
        let timeout = try session.quizInputScript(
            answer: "",
            question: question,
            feedbackChoice: 0
        )
        #expect(!correct.isEmpty)
        #expect(!incorrect.isEmpty)
        #expect(!timeout.isEmpty)
        #expect(correct != incorrect)
        #expect(timeout != incorrect)
    }
    #expect(throws: FirstDLLAnalysisError.invalidAITXTChoice(6)) {
        try session.quizQuestion(category: 6)
    }
    let quizEngine = try NativeFirstPersonalityEngine(masterDirectoryURL: master)
    // Balloon links arrive through GhostEvent.choice, while raised and input
    // events arrive through GhostEvent.shiori. Exercise the real mixed route.
    #expect(try await quizEngine.handle(event: .choice(
        id: "OnQuizStart",
        arguments: ["0"]
    )) != nil)
    #expect(try await quizEngine.handle(event: .shiori(
        id: "OnQuizNext",
        references: [:]
    )) != nil)
    #expect(try await quizEngine.handle(event: .shiori(
        id: "OnQuizInput",
        references: [0: session.quizQuestion(category: 0).acceptedAnswers[0]]
    )) != nil)
    #expect(try await quizEngine.handle(event: .shiori(
        id: "OnQuizStart",
        references: [0: "1"]
    )) != nil)
    #expect(try await quizEngine.handle(event: .shiori(
        id: "OnQuizNext",
        references: [:]
    )) != nil)
    #expect(try await quizEngine.handle(event: .shiori(
        id: "OnUserInputCancel",
        references: [0: "OnQuizInput"]
    )) != nil)
    #expect(try await quizEngine.handle(event: .shiori(
        id: "OnQuizLeave",
        references: [:]
    )) != nil)
    let typingMenu = try session.typingGameEnterScript(reference: nil)
    #expect(typingMenu.components(separatedBy: "OnTypinggameStart").count == 4)
    #expect(try session.script(forEventID: "OnTypinggameEnter") == typingMenu)
    #expect(try session.script(forEventID: "OnTypinggameTutorial") == session.typingGameTutorialScript())
    #expect(try session.script(forEventID: "OnTypinggameLeave") == session.typingGameLeaveScript())
    var typingAnswers = Set<String>()
    for level in 0 ..< 3 {
        #expect(try !session.typingGameStartScript(level: level).isEmpty)
        for attempt in 0 ..< 10 {
            let question = try session.typingGameQuestion(
                level: level,
                attempt: attempt,
                totalMilliseconds: attempt * 1000
            )
            #expect(question.level == level)
            #expect(question.attempt == attempt)
            #expect(!question.expectedAnswer.isEmpty)
            #expect(question.script.contains(question.expectedAnswer))
            #expect(question.script.contains("\\![open,inputbox,OnTypinggameInput,15000]"))
            #expect(!question.script.contains("OnOpenTypingbox"))
            typingAnswers.insert(question.expectedAnswer)
        }
    }
    #expect(typingAnswers.count == 30)
    let finalTypingQuestion = try session.typingGameQuestion(level: 0, attempt: 9, totalMilliseconds: 90000)
    let perfectTypingResult = try session.typingGameInputScript(
        answer: finalTypingQuestion.expectedAnswer,
        question: finalTypingQuestion,
        correctCount: 10,
        totalMilliseconds: 100_000,
        feedbackChoice: 0
    )
    let missedTypingResult = try session.typingGameInputScript(
        answer: "",
        question: finalTypingQuestion,
        correctCount: 0,
        totalMilliseconds: 150_000,
        feedbackChoice: 0
    )
    #expect(!perfectTypingResult.isEmpty)
    #expect(!missedTypingResult.isEmpty)
    #expect(perfectTypingResult != missedTypingResult)
    let typingStateRoot = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: typingStateRoot) }
    let typingEngine = try NativeFirstPersonalityEngine(
        masterDirectoryURL: master,
        stateRootURL: typingStateRoot
    )
    #expect(try await typingEngine.handle(event: .choice(
        id: "OnTypinggameStart",
        arguments: ["0"]
    )) != nil)
    for attempt in 0 ..< 10 {
        #expect(try await typingEngine.handle(event: .shiori(
            id: "OnTypinggameNext",
            references: [:]
        )) != nil)
        #expect(try await typingEngine.handle(event: .shiori(
            id: "OnTypinggameInput",
            references: [0: session.typingGameQuestion(
                level: 0,
                attempt: attempt,
                totalMilliseconds: 0
            ).expectedAnswer]
        )) != nil)
    }
    let typingStore = FirstNativeStateStore(
        masterDirectoryURL: master,
        stateRootURL: typingStateRoot
    )
    let savedTypingRecord = try #require(typingStore.load()?.typingRecords?[0])
    #expect(savedTypingRecord.correctCount == 10)
    #expect(savedTypingRecord.totalMilliseconds >= 0)
    #expect(try session.typingGameEnterScript(
        reference: "return",
        records: typingStore.load()?.typingRecords ?? []
    ).contains(String(savedTypingRecord.totalMilliseconds)))
    #expect(try session.aitxtRecords().count == 1615)
    let emptyGoogle = try session.googleSearchScript(query: "", choice: 0)
    let googleVariants = try (0 ..< 2).map {
        try session.googleSearchScript(query: "Utatane test&value", choice: $0)
    }
    #expect(!emptyGoogle.contains("open,browser"))
    #expect(Set(googleVariants).count == 2)
    #expect(googleVariants.allSatisfy { $0.contains("open,browser") })
    #expect(googleVariants.allSatisfy { $0.contains("Utatane%20test%26value") })
    #expect(try session.script(
        forEventID: "OnGoogle",
        references: [0: "Utatane test&value"]
    )?.contains("Utatane%20test%26value") == true)
    let googleEngine = try NativeFirstPersonalityEngine(masterDirectoryURL: master)
    #expect(try await googleEngine.handle(event: .shiori(
        id: "OnGoogle",
        references: [0: "Utatane test&value"]
    ))?.rawValue.contains("Utatane%20test%26value") == true)
    let balloonChange = try session.balloonChangeScript(name: "UtataneTestBalloon")
    #expect(balloonChange.contains("UtataneTestBalloon"))
    #expect(try session.script(
        forEventID: "OnBalloonChange",
        references: [0: "UtataneTestBalloon"]
    ) == balloonChange)
    #expect(try !session.shellChangingScript(name: "UtataneTestShell").isEmpty)
    #expect(try session.script(
        forEventID: "OnShellChanging",
        references: [0: "UtataneTestShell"]
    ) != nil)
    let ghostChanging = try (0 ..< 2).map {
        try session.ghostChangingScript(
            name: "UtataneTestGhost",
            isSleeping: false,
            isBathing: false,
            fallbackChoice: $0
        )
    }
    #expect(Set(ghostChanging).count == 2)
    let knownGhostChanges = try [
        "陽子", "愛理", "あると", "花ちゃん", "毒子",
        "美耳", "さくら", "サンバーレイン"
    ].compactMap {
        try session.ghostChangedScript(name: $0, previousScript: nil, hildrChoice: 0)
    }
    #expect(knownGhostChanges.count == 8)
    #expect(Set(knownGhostChanges).count == 8)
    let hildrChanges = try (0 ..< 3).compactMap {
        try session.ghostChangedScript(name: "ヒルデ", previousScript: nil, hildrChoice: $0)
    }
    #expect(Set(hildrChanges).count == 3)
    #expect(try session.ghostChangedScript(
        name: "unknown",
        previousScript: nil,
        hildrChoice: 0
    ) == nil)
    let blackChange = try session.ghostChangedScript(
        name: "unknown",
        previousScript: "黒",
        hildrChoice: 0
    )
    #expect(blackChange != nil)
    #expect(try session.script(
        forEventID: "OnGhostChanged",
        references: [0: "陽子"]
    ) == knownGhostChanges[0])
    let fixedLifecycleEvents = try [
        "OnVanishSelected", "OnVanishSelecting", "OnVanished",
        "OnUpdatedataCreating", "OnUpdatedataCreated"
    ].compactMap { try session.script(forEventID: $0) }
    #expect(fixedLifecycleEvents.count == 5)
    #expect(Set(fixedLifecycleEvents).count == 5)
    #expect(fixedLifecycleEvents.allSatisfy { $0.contains("\\0") || $0.contains("\\1") })
    let installFailures = try ["unlha32", "unzip32", "other"].map {
        try session.installFailureScript(reason: $0)
    }
    #expect(Set(installFailures).count == 3)
    #expect(try session.script(
        forEventID: "OnInstallFailure",
        references: [0: "unzip32"]
    ) == installFailures[1])
    let installRefusals = try (0 ..< 2).map {
        try session.installRefuseScript(name: "UtataneTest", consequenceChoice: $0)
    }
    #expect(Set(installRefusals).count == 2)
    #expect(installRefusals.allSatisfy { script in
        script.components(separatedBy: "UtataneTest").count == 3
    })
    #expect(try session.script(
        forEventID: "OnInstallRefuse",
        references: [0: "UtataneTest"]
    )?.contains("UtataneTest") == true)
    let anchorScripts = try [
        session.anchorSelectScript(id: "いたる", itaruChoice: 0),
        session.anchorSelectScript(id: "いたる", itaruChoice: 1),
        session.anchorSelectScript(id: "木野さん", itaruChoice: 0),
        session.anchorSelectScript(id: "ガッツ石松", itaruChoice: 0),
        session.anchorSelectScript(id: "AIBO", itaruChoice: 0),
        session.anchorSelectScript(id: "VAIO", itaruChoice: 0),
        session.anchorSelectScript(id: "ラグナロク", itaruChoice: 0),
        session.anchorSelectScript(id: "海原雄山", itaruChoice: 0),
        session.anchorSelectScript(id: "unknown", itaruChoice: 0)
    ]
    #expect(Set(anchorScripts).count == anchorScripts.count)
    #expect(anchorScripts.allSatisfy { $0.contains("\\0") || $0.contains("\\1") })
    #expect(try session.anchorSelectScript(id: "あかほり", itaruChoice: 0) == anchorScripts[0])
    #expect(try session.script(
        forEventID: "OnAnchorSelect",
        references: [0: "AIBO"]
    ) == anchorScripts[4])
    #expect(try session.script(forEventID: "OnSSTPBlacklisting")?.contains("\\0") == true)
    let headlineFailures = try [
        session.headlineFailureScript(reason: "can't download", isBathing: false),
        session.headlineFailureScript(reason: "can't analyze", isBathing: false),
        session.headlineFailureScript(reason: "unknown", isBathing: true)
    ].compactMap(\.self)
    #expect(Set(headlineFailures).count == 3)
    #expect(try session.headlineFailureScript(reason: "unknown", isBathing: false) == nil)
    let headlineCompletions = try [false, true].map {
        try session.headlineCompleteScript(isBathing: $0)
    }
    #expect(Set(headlineCompletions).count == 2)
    let headlineBegins = try [false, true].map {
        try session.headlineBeginScript(name: "UtataneTestSensor", isBathing: $0)
    }
    #expect(Set(headlineBegins).count == 2)
    #expect(headlineBegins.allSatisfy { $0.contains("UtataneTestSensor") })
    let fixedNetworkEvents = try ["OnUpdateBegin", "OnNetworkHeavy", "OnSNTPFailure"].compactMap {
        try session.script(forEventID: $0)
    }
    #expect(fixedNetworkEvents.count == 3)
    #expect(Set(fixedNetworkEvents).count == 3)
    let updateCompletions = try [nil, "none"].map {
        try session.updateCompleteScript(result: $0)
    }
    #expect(Set(updateCompletions).count == 2)
    let updateFailures = try ["too slow", "md5 miss", "timeout"].compactMap {
        try session.updateFailureScript(reason: $0, requiredVersion: nil)
    }
    #expect(Set(updateFailures).count == 3)
    let tooOld = try session.updateFailureScript(reason: "too old", requiredVersion: "UtataneTestVersion")
    #expect(tooOld?.contains("UtataneTestVersion") == true)
    #expect(try session.updateFailureScript(reason: "unknown", requiredVersion: nil) == nil)
    #expect(try session.script(
        forEventID: "OnUpdateFailure",
        references: [0: "too old", 1: "UtataneTestVersion"]
    ) == tooOld)
    let downloadBegins = try (0 ..< 6).map {
        try session.updateDownloadBeginScript(
            path: "UtataneTestDownload",
            choice: $0,
            aitxtChoice: 0
        )
    }
    #expect(Set(downloadBegins).count == 6)
    #expect(downloadBegins.allSatisfy { $0.contains("UtataneTestDownload") })
    #expect(try session.script(
        forEventID: "OnUpdate.OnDownloadBegin",
        references: [0: "UtataneTestDownload"]
    )?.contains("UtataneTestDownload") == true)
    let md5Begin = try session.updateMD5CompareBeginScript(path: "UtataneTestPath")
    #expect(md5Begin.contains("UtataneTestPath"))
    #expect(try session.script(
        forEventID: "OnUpdate.OnMD5CompareBegin",
        references: [0: "UtataneTestPath"]
    ) == md5Begin)
    let md5Results = try [true, false].map {
        try session.updateMD5CompareResultScript(
            localMD5: "UtataneLocalMD5",
            remoteMD5: "UtataneRemoteMD5",
            matches: $0
        )
    }
    #expect(Set(md5Results).count == 2)
    #expect(md5Results.allSatisfy { $0.contains("UtataneLocalMD5") && $0.contains("UtataneRemoteMD5") })
    #expect(try session.script(
        forEventID: "OnUpdate.OnMD5CompareFailure",
        references: [1: "UtataneRemoteMD5", 2: "UtataneLocalMD5"]
    ) == md5Results[1])
    let sntpSame = try session.sntpCompareScript(
        serverComponents: "2026,9,4,12,34,56",
        localComponents: "2026,9,4,12,34,56",
        offsetSeconds: "0"
    )
    let sntpDifferent = try session.sntpCompareScript(
        serverComponents: "2026,9,4,12,35,1",
        localComponents: "2026,9,4,12,34,56",
        offsetSeconds: "5"
    )
    #expect(sntpSame != nil)
    #expect(sntpDifferent != nil)
    #expect(sntpSame != sntpDifferent)
    #expect(try session.sntpCompareScript(
        serverComponents: "invalid",
        localComponents: "2026,9,4,12,34,56",
        offsetSeconds: "0"
    ) == nil)
    #expect(try session.script(
        forEventID: "OnSNTPCompare",
        references: [
            1: "2026,9,4,12,35,1",
            2: "2026,9,4,12,34,56",
            3: "5"
        ]
    ) == sntpDifferent)
    let sntpBegins = try [0, 3].map {
        try session.sntpBeginScript(server: "https://time.example", daysSinceLastUpdate: $0)
    }
    #expect(Set(sntpBegins).count == 2)
    #expect(sntpBegins[0].contains("https://time.example"))
    #expect(!sntpBegins[1].contains("https://time.example"))
    #expect(try session.script(
        forEventID: "OnSNTPBegin",
        references: [0: "https://time.example"]
    ) == sntpBegins[0])
    let stateRoot = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: stateRoot) }
    let updateDate = try #require(Calendar.current.date(
        from: DateComponents(year: 2026, month: 9, day: 4, hour: 12)
    ))
    let laterDate = try #require(Calendar.current.date(
        from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)
    ))
    let updatingEngine = try NativeFirstPersonalityEngine(
        masterDirectoryURL: master,
        now: { updateDate },
        stateRootURL: stateRoot
    )
    #expect(try await updatingEngine.handle(event: .shiori(
        id: "OnUpdateComplete",
        references: [0: "none"]
    )) != nil)
    let restartedEngine = try NativeFirstPersonalityEngine(
        masterDirectoryURL: master,
        now: { laterDate },
        stateRootURL: stateRoot
    )
    let persistedSNTPBegin = try #require(await restartedEngine.handle(event: .shiori(
        id: "OnSNTPBegin",
        references: [0: "https://time.example"]
    )))
    #expect(!persistedSNTPBegin.rawValue.contains("https://time.example"))
    let biffFailures = try ["timeout", "defect", "kick"].compactMap {
        try session.biffFailureScript(reason: $0, detail: "UtataneTestMail")
    }
    #expect(Set(biffFailures).count == 3)
    #expect(biffFailures[0].contains("UtataneTestMail"))
    #expect(!biffFailures[1].contains("UtataneTestMail"))
    #expect(biffFailures[2].contains("UtataneTestMail"))
    #expect(try session.biffFailureScript(reason: "unknown", detail: nil) == nil)
    let biffBegins = try (0 ..< 2).map {
        try session.biffBeginScript(detail: "UtataneTestMail", choice: $0)
    }
    #expect(Set(biffBegins).count == 2)
    #expect(biffBegins.allSatisfy { $0.contains("UtataneTestMail") })
    let emptyMailbox = try session.biffCompleteScript(messageCount: "0")
    #expect(emptyMailbox?.isEmpty == false)
    #expect(try session.script(
        forEventID: "OnBIFFComplete",
        references: [0: "0"]
    ) == emptyMailbox)
    #expect(try session.biffCompleteScript(messageCount: "1") == nil)
    #expect(try session.biffCompleteScript(messageCount: nil) == nil)
    let installs = try [
        session.installCompleteScript(type: "ghost", name: "UtataneTestGhost,UtataneTestDirectory"),
        session.installCompleteScript(type: "ghost", name: "UtataneTestGhost"),
        session.installCompleteScript(type: "shell", name: "UtataneTestShell"),
        session.installCompleteScript(type: "balloon", name: "UtataneTestBalloon"),
        session.installCompleteScript(type: "plugin", name: "UtataneTestPlugin"),
        session.installCompleteScript(type: "unknown", name: "UtataneTestUnknown")
    ]
    #expect(Set(installs).count == installs.count)
    #expect(installs[0].contains("UtataneTestGhost"))
    #expect(installs[0].contains("UtataneTestDirectory"))
    #expect(try session.script(forEventID: "OnInstallBegin")?.contains("\\0") == true)
    #expect(try session.script(
        forEventID: "OnInstallComplete",
        references: [0: "plugin", 1: "UtataneTestPlugin"]
    ) == installs[4])
    let utilityScripts = try ["On_RefreshMemory", "On_IP"].compactMap {
        try session.script(forEventID: $0)
    }
    #expect(utilityScripts.count == 2)
    #expect(Set(utilityScripts).count == 2)
    #expect(try session.script(forEventID: "On_RefreshMemory") == session.refreshMemoryScript())
    let refreshComplete = try session.refreshMemoryCompleteScript()
    #expect(!refreshComplete.isEmpty)
    #expect(try session.script(forEventID: "On_RefreshMemoryExecute") == refreshComplete)
    let ipResults = try [nil, "192.0.2.1"].map(session.ipResultScript(ipAddress:))
    #expect(Set(ipResults).count == 2)
    #expect(ipResults[1].contains("192.0.2.1"))
    #expect(try session.script(forEventID: "On_IP_got") == ipResults[0])
    let debugScripts = try [
        "On_debug_reloadsurface", "On_debug_houchi1200",
        "On_debug_nemuku", "On_debug_nemukunai"
    ].compactMap { try session.script(forEventID: $0) }
    #expect(debugScripts.count == 4)
    #expect(Set(debugScripts).count == 4)
    let urlDropping = try (0 ..< 2).map(session.urlDroppingScript(choice:))
    #expect(Set(urlDropping).count == 2)
    #expect(try urlDropping.contains(session.script(forEventID: "OnURLDropping") ?? ""))
    let systemPrompts = try [session.exitWindowsPromptScript(), session.rebootWindowsPromptScript()]
    #expect(Set(systemPrompts).count == 2)
    let portal = try session.portalMenuScript()
    #expect(!portal.isEmpty)
    let portalSelections = try ["sakuranavi", "moonphase", "activesonar", "nnn", "saimoe", "ngc"]
        .compactMap(session.portalSelectedScript(id:))
    #expect(portalSelections.count == 6)
    #expect(Set(portalSelections).count == 6)
    #expect(try session.portalSelectedScript(id: "unknown") == nil)
    #expect(try session.script(forEventID: "On_BIFF")?.contains("\\![biff]") == true)
    let debugMenu = try session.debugMenuScript()
    #expect(debugMenu.contains("On_debug_reloadsurface"))
    #expect(try session.script(forEventID: "On_debug") == debugMenu)
    let recommendMenu = try session.recommendMenuScript()
    #expect(recommendMenu.contains("On_RecommendSelected"))
    #expect(try session.script(forEventID: "On_Recommend") == recommendMenu)
    let recommendationSelections = try ["airi", "333", "sakura"]
        .compactMap(session.recommendSelectedScript(id:))
    #expect(recommendationSelections.count == 3)
    #expect(Set(recommendationSelections).count == 3)
    #expect(try session.recommendSelectedScript(id: "unknown") == nil)
    #expect(try session.script(
        forEventID: "On_RecommendSelected",
        references: [0: "333"]
    ) == recommendationSelections[1])
    #expect(try session.script(forEventID: "OnWallpaperChange")?.contains("\\0") == true)
    let restoreScripts = try [
        session.windowRestoreSleepingScript(shortAbsence: true),
        session.windowRestoreSleepingScript(shortAbsence: false),
        session.windowRestoreDrowsyScript(),
        session.windowRestoreBathingScript(),
        session.windowRestoreNormalShortAbsenceScript(),
        session.windowRestoreSleepTransitionScript()
    ]
    #expect(Set(restoreScripts).count == 6)
    #expect(restoreScripts.allSatisfy { $0.contains("\\0") || $0.contains("\\1") })

    let morning = try session.onBootScript(hour: 8, topLevelChoice: 0)
    let daytime = try session.onBootScript(hour: 12, topLevelChoice: 0)
    let evening = try session.onBootScript(hour: 17, topLevelChoice: 0)
    let night = try session.onBootScript(hour: 22, topLevelChoice: 0)
    #expect(Set([morning, daytime, evening, night]).count == 4)
    #expect([morning, daytime, evening, night].allSatisfy { $0.contains("\\e") })
    let midnightScripts = try (0 ... 12).compactMap { choice -> String? in
        let script = try session.onBootScript(hour: 3, topLevelChoice: 0, midnightChoice: choice)
        return script == baseline ? nil : script
    }
    #expect(midnightScripts.count == 13)
    #expect(midnightScripts.allSatisfy { $0.contains("\\0") })
    let composedMidnight = try (2 ... 5).map { choice in
        try session.onBootScript(
            hour: 3,
            topLevelChoice: 0,
            midnightChoice: choice,
            aitxtChoices: [0, 1]
        )
    }
    #expect(composedMidnight.allSatisfy { $0.contains("\\0") && $0.contains("\\e") })
    #expect(Set(composedMidnight).count == 4)
    let schedules = try (0 ... 3).map { template in
        try session.onBootScript(
            hour: 12,
            topLevelChoice: 1,
            aitxtChoices: [0],
            day: 23,
            scheduleKindChoice: 0,
            scheduleTemplateChoice: template
        )
    }
    #expect(Set(schedules).count == 4)
    #expect(schedules.allSatisfy { $0.contains("23") && $0.contains("\\0") })
    let generatedSchedule = try session.onBootScript(
        hour: 12,
        topLevelChoice: 2,
        aitxtChoices: [0, 0, 0],
        day: 23,
        scheduleKindChoice: 1,
        scheduleTemplateChoice: 0,
        generatedScheduleChoices: [1, 2, 3, 1, 0, 14]
    )
    #expect(generatedSchedule.contains("23"))
    #expect(generatedSchedule.contains("14"))
    #expect(!generatedSchedule.contains("%ms"))
    #expect(!generatedSchedule.contains("%mz"))
    #expect(try session.onBootScript(hour: 12, topLevelChoice: 1) == baseline)

    let engine = try NativeFirstPersonalityEngine(masterDirectoryURL: master)
    let bootScript = try #require(await engine.handle(event: .boot))
    #expect(!bootScript.rawValue.contains("\\1\\s0"))
    let talks = try (0 ..< 34).map { choice in
        try session.randomTalkScript(choice: choice, aitxtChoices: [0, 1, 2])
    }
    #expect(talks.allSatisfy { $0.contains("\\0") })
    #expect(talks.allSatisfy { !$0.contains("%ms") && !$0.contains("%mz") })
    // FIRST intentionally points two switch entries at the same dialogue.
    #expect(Set(talks).count == 33)
    let randomTalk = try #require(await engine.handle(event: .randomTalk))
    #expect(randomTalk.rawValue.contains("\\0"))
    #expect(!randomTalk.rawValue.contains("\\1\\s0"))
    let keroReactions = try (0 ..< 7).map { try session.keroDoubleClickScript(choice: $0) }
    #expect(Set(keroReactions).count == 7)
    #expect(keroReactions.allSatisfy { $0.contains("\\1") })
    let keroDoubleClick = try #require(await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 1,
        region: nil,
        x: 0,
        y: 0
    ))))
    #expect(keroDoubleClick.rawValue.contains("\\1"))
    let sakuraDoubleClick = try #require(await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 0,
        region: "face",
        x: 0,
        y: 0
    ))))
    #expect(sakuraDoubleClick.rawValue.contains("\\q["))
    let faceMenus = try (0 ..< 2).map {
        try session.sakuraDoubleClickMenuScript(region: "Face", faceReactionChoice: $0)
    }
    #expect(Set(faceMenus).count == 2)
    #expect(faceMenus.allSatisfy { $0.contains("\\q[") })
    let bodyMenu = try session.sakuraDoubleClickMenuScript(region: "Bust", faceReactionChoice: 0)
    #expect(bodyMenu.contains("\\q["))
    #expect(!faceMenus.contains(bodyMenu))
    let restored = try #require(await engine.handle(event: .shiori(id: "OnSurfaceRestore", references: [:])))
    #expect(restored.rawValue.contains("\\0\\s[20]"))
    #expect(restored.rawValue.contains("\\1\\s[10]"))
    #expect(session.choiceScript(id: "stayontop")?.contains("stayontop") == true)
    #expect(session.choiceScript(id: "!stayontop")?.contains("!stayontop") == true)
    #expect(session.choiceScript(id: "ghostexplorer") == nil)
    #expect(try session.firstMenuChoiceScript(id: "sleepylevel", energy: 20) != nil)
    #expect(try session.firstMenuChoiceScript(id: "game", energy: 180)?.contains("\\q[") == true)
    #expect(try session.firstMenuChoiceScript(id: "commandbymouse", energy: 180)?.contains("\\q[") == true)
    let cancel = try #require(await engine.handle(event: .choice(id: "cancel", arguments: [])))
    #expect(cancel.rawValue == "\\e")
    let update = try #require(await engine.handle(event: .choice(id: "On_Update", arguments: [])))
    #expect(update.rawValue.contains("updatebymyself"))
    let choiceTimeouts = try (0 ..< 2).map { try session.choiceTimeoutScript(choice: $0) }
    #expect(Set(choiceTimeouts).count == 2)
    #expect(choiceTimeouts.allSatisfy { $0.contains("\\0") })
    #expect(try await engine.handle(event: .shiori(id: "OnChoiceTimeout", references: [:])) != nil)
    let quickClose = try session.onCloseScript(elapsedSeconds: 30, choice: 0)
    let regularCloses = try (0 ..< 2).map {
        try session.onCloseScript(elapsedSeconds: 180, choice: $0)
    }
    #expect(regularCloses.allSatisfy { $0.contains("\\-") })
    #expect(Set(regularCloses + [quickClose]).count == 3)
    let stateCloses = try [session.sleepingCloseScript(), session.bathingCloseScript()]
    #expect(Set(stateCloses).count == 2)
    #expect(stateCloses.allSatisfy { $0.contains("\\-") })
    let stateSurfaceRestores = try [
        session.sleepingSurfaceRestoreScript(),
        session.bathingSurfaceRestoreScript()
    ]
    #expect(Set(stateSurfaceRestores).count == 2)
    #expect(stateSurfaceRestores.allSatisfy { $0.contains("\\s") })
    #expect(try await engine.handle(event: .close)?.rawValue.contains("\\-") == true)
    #expect(try session.script(forEventID: "OnSSTPBreak")?.contains("\\e") == true)
    let bustResponses = try (1 ... 3).map { try session.sakuraBustClickScript(clickCount: $0) }
    #expect(Set(bustResponses).count == 3)
    #expect(bustResponses[2].contains("\\-"))
    let firstBustClick = try #require(await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .click,
        scope: 0,
        region: "Bust",
        x: 0,
        y: 0
    ))))
    let secondBustClick = try #require(await engine.handle(event: .mouseClick(scope: 0, region: "bust")))
    #expect(firstBustClick != secondBustClick)
    let drowsyScripts = try (0 ..< 4).map { try session.drowsyTransitionScript(choice: $0) }
    let sleepScripts = try (0 ..< 3).map { try session.sleepTransitionScript(choice: $0) }
    #expect(Set(drowsyScripts).count == 4)
    #expect(Set(sleepScripts).count == 3)
    #expect(sleepScripts.allSatisfy { $0.contains("enter,inductionmode") })
    let sleepingPokes = try (0 ..< 6).map { try session.sleepingPokeScript(choice: $0) }
    let wakeScripts = try (0 ..< 4).map { try session.wakeFromSleepScript(choice: $0) }
    #expect(Set(sleepingPokes).count == 6)
    #expect(Set(wakeScripts).count == 2)
    #expect(wakeScripts.allSatisfy { $0.contains("leave,inductionmode") })
    #expect(try !session.sakuraBathingDoubleClickScript().isEmpty)
    #expect(try session.keroSleepingDoubleClickMenuScript().contains("\\q["))
    #expect(try session.keroBathingDoubleClickMenuScript().contains("\\q["))
    #expect(try session.bathTransitionScript().contains("enter,inductionmode"))
    let bathReturns = try (0 ..< 2).map { try session.returnFromBathScript(choice: $0) }
    #expect(Set(bathReturns).count == 2)
    #expect(bathReturns.allSatisfy { $0.contains("leave,inductionmode") })
}

@Test func `decodes a known AITXT resource vector`() {
    let plaintext = Data("first aitxt\r\nthree-line record\r\n".utf8)
    let encoded = Data(hex: "41368333fce04db6a2557036bda86388af473ee18d7dcb648e0205692cea5d28")

    #expect(FirstAITXTDecoder.decodeResource(encoded) == plaintext)
}

@Test func `persists native FIRST state outside the supplied master`() throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    let stateRoot = temporaryRoot.appending(path: "state", directoryHint: .isDirectory)
    let store = FirstNativeStateStore(masterDirectoryURL: master, stateRootURL: stateRoot)
    let state = FirstNativePersistentState(
        energy: 123,
        lastBathDate: Date(timeIntervalSince1970: 100),
        lastUpdateDate: Date(timeIntervalSince1970: 200),
        typingRecords: [
            FirstTypingRecord(correctCount: 8, totalMilliseconds: 42000),
            nil,
            FirstTypingRecord(correctCount: 10, totalMilliseconds: 30000)
        ]
    )

    try store.save(state)

    #expect(store.load() == state)
    #expect(!FileManager.default.fileExists(atPath: master.path))
}

@Test func `loads FIRST state written before update dates were persisted`() throws {
    let legacy = Data(#"{"energy":123,"lastBathDate":null}"#.utf8)
    let state = try JSONDecoder().decode(FirstNativePersistentState.self, from: legacy)

    #expect(state.energy == 123)
    #expect(state.lastBathDate == nil)
    #expect(state.lastUpdateDate == nil)
    #expect(state.typingRecords == nil)
}

@Test func `FIRST typing records prefer accuracy and then shorter time`() {
    let previous = FirstTypingRecord(correctCount: 8, totalMilliseconds: 42000)

    #expect(NativeFirstPersonalityEngine.shouldReplaceTypingRecord(
        nil,
        with: previous
    ))
    #expect(NativeFirstPersonalityEngine.shouldReplaceTypingRecord(
        previous,
        with: FirstTypingRecord(correctCount: 9, totalMilliseconds: 150_000)
    ))
    #expect(NativeFirstPersonalityEngine.shouldReplaceTypingRecord(
        previous,
        with: FirstTypingRecord(correctCount: 8, totalMilliseconds: 41999)
    ))
    #expect(!NativeFirstPersonalityEngine.shouldReplaceTypingRecord(
        previous,
        with: FirstTypingRecord(correctCount: 8, totalMilliseconds: 42000)
    ))
    #expect(!NativeFirstPersonalityEngine.shouldReplaceTypingRecord(
        previous,
        with: FirstTypingRecord(correctCount: 7, totalMilliseconds: 1000)
    ))
}

@Test func `FIRST bath cooldown uses twelve elapsed hours instead of calendar day`() {
    let lastBath = Date(timeIntervalSince1970: 1000)

    #expect(!NativeFirstPersonalityEngine.canBathe(
        lastBathDate: lastBath,
        at: Date(timeIntervalSince1970: 44199)
    ))
    #expect(NativeFirstPersonalityEngine.canBathe(
        lastBathDate: lastBath,
        at: Date(timeIntervalSince1970: 44200)
    ))
    #expect(NativeFirstPersonalityEngine.canBathe(lastBathDate: nil, at: lastBath))
}

@Test func `FIRST minute state updates energy and sleeping wake effort`() {
    #expect(NativeFirstPersonalityEngine.energyAfterMinute(10, state: .normal) == 9)
    #expect(NativeFirstPersonalityEngine.energyAfterMinute(0, state: .drowsy) == 0)
    #expect(NativeFirstPersonalityEngine.energyAfterMinute(
        10,
        state: .normal,
        isMinimized: true
    ) == 10)
    #expect(NativeFirstPersonalityEngine.energyAfterMinute(359, state: .sleeping) == 360)
    #expect(NativeFirstPersonalityEngine.energyAfterMinute(120, state: .bathing) == 120)
    #expect(NativeFirstPersonalityEngine.sleepingPokesAfterMinute(2) == 3)
    #expect(NativeFirstPersonalityEngine.sleepingPokesAfterMinute(4) == 4)
}

@Test func `FIRST restore uses state duration and energy idle threshold`() {
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .sleeping,
        minimizedSeconds: 119,
        energy: 360,
        secondsSinceTalk: 0
    ) == .sleeping(shortAbsence: true))
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .sleeping,
        minimizedSeconds: 120,
        energy: 360,
        secondsSinceTalk: 0
    ) == .sleeping(shortAbsence: false))
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .drowsy,
        minimizedSeconds: 0,
        energy: 360,
        secondsSinceTalk: 0
    ) == .drowsy)
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .bathing,
        minimizedSeconds: 0,
        energy: 360,
        secondsSinceTalk: 0
    ) == .bathing)
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .normal,
        minimizedSeconds: 119,
        energy: 360,
        secondsSinceTalk: 3600
    ) == .normalShortAbsence)
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .normal,
        minimizedSeconds: 120,
        energy: 30,
        secondsSinceTalk: 30
    ) == .sleepTransition)
    #expect(NativeFirstPersonalityEngine.windowRestoreAction(
        state: .normal,
        minimizedSeconds: 120,
        energy: 31,
        secondsSinceTalk: 30
    ) == .randomTalk)
}

@Test func `FIRST close action follows activity state`() {
    #expect(NativeFirstPersonalityEngine.closeAction(
        state: .normal,
        elapsedSeconds: 119
    ) == .normal(elapsedSeconds: 119))
    #expect(NativeFirstPersonalityEngine.closeAction(
        state: .sleeping,
        elapsedSeconds: 0
    ) == .sleeping)
    #expect(NativeFirstPersonalityEngine.closeAction(
        state: .bathing,
        elapsedSeconds: 0
    ) == .bathing)
    #expect(NativeFirstPersonalityEngine.closeAction(
        state: .drowsy,
        elapsedSeconds: 0
    ) == .noResponse)
}

@Test func `FIRST native scripts do not leave the player in induction mode`() {
    let source = "\\0before\\![enter,inductionmode]sleep\\![leave,inductionmode]after\\e"

    let normalized = NativeFirstPersonalityEngine.normalizeFIRSTScript(source)

    #expect(normalized == "\\0beforesleepafter\\e")
}

@Test func `groups AITXT lines into three field records`() throws {
    let records = try FirstAITXTDecoder.records(from: [
        "subject", "\\ms,\\k", "related,-,term",
        "other", "\\dg", ""
    ])

    #expect(records == [
        FirstAITXTRecord(
            phrase: "subject",
            directives: ["\\ms", "\\k"],
            relatedTerms: ["related", "-", "term"]
        ),
        FirstAITXTRecord(phrase: "other", directives: ["\\dg"], relatedTerms: [])
    ])
}

@Test func `rejects an incomplete AITXT record`() {
    #expect(throws: FirstDLLAnalysisError.invalidAITXTRecordCount(2)) {
        try FirstAITXTDecoder.records(from: ["subject", "\\ms"])
    }
}

private func makePEDLL(strings: [String]) -> Data {
    let peOffset = 0x80
    let optionalHeaderSize = 0xE0
    let sectionHeader = peOffset + 4 + 20 + optionalHeaderSize
    let codeOffset = 0x200
    let imageBase: UInt32 = 0x0040_0000
    let codeVirtualAddress: UInt32 = 0x1000
    var code = Data()
    for (index, string) in strings.enumerated() {
        let stringOffset = code.count
        let bytes = string.data(using: .shiftJIS)!
        append(UInt32.max, to: &code)
        append(UInt32(bytes.count), to: &code)
        code.append(bytes)
        code.append(0)
        if index == 0 {
            code.append(0xB8) // mov eax, <Delphi string data address>
            append(imageBase + codeVirtualAddress + UInt32(stringOffset + 8), to: &code)
        }
    }
    code.append(Data(repeating: 0, count: 16))

    var data = Data(repeating: 0, count: codeOffset + code.count)
    data[0] = 0x4D
    data[1] = 0x5A
    write(UInt32(peOffset), to: &data, at: 0x3C)
    data.replaceSubrange(peOffset ..< peOffset + 4, with: [0x50, 0x45, 0, 0])
    write(UInt16(0x014C), to: &data, at: peOffset + 4)
    write(UInt16(1), to: &data, at: peOffset + 6)
    write(UInt16(optionalHeaderSize), to: &data, at: peOffset + 20)
    write(UInt16(0x2000), to: &data, at: peOffset + 22)
    write(UInt16(0x010B), to: &data, at: peOffset + 24)
    write(imageBase, to: &data, at: peOffset + 24 + 28)
    data.replaceSubrange(sectionHeader ..< sectionHeader + 8, with: Array("CODE".utf8) + [0, 0, 0, 0])
    write(codeVirtualAddress, to: &data, at: sectionHeader + 12)
    write(UInt32(code.count), to: &data, at: sectionHeader + 16)
    write(UInt32(codeOffset), to: &data, at: sectionHeader + 20)
    data.replaceSubrange(codeOffset ..< codeOffset + code.count, with: code)
    return data
}

private func append(_ value: some FixedWidthInteger, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

private func write(_ value: some FixedWidthInteger, to data: inout Data, at offset: Int) {
    var bytes = Data()
    append(value, to: &bytes)
    data.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start ..< end], radix: 16)!
        })
    }
}

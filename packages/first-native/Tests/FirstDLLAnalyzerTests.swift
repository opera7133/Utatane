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
    #expect(try session.script(forEventID: "OnUnknownEvent") == nil)
    #expect(try session.aitxtRecords().count == 1615)
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
    let state = FirstNativePersistentState(energy: 123, lastBathDate: Date(timeIntervalSince1970: 100))

    try store.save(state)

    #expect(store.load() == state)
    #expect(!FileManager.default.fileExists(atPath: master.path))
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

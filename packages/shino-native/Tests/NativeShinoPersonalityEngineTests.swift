import Foundation
import Testing
import UtataneCore
import UtataneGhostKit
import UtataneNativeSaori
@testable import UtataneShinoNative

@Test func `loads installed kodama shino ghost`() async throws {
    let master = repositoryRoot.appending(path: "Content/Local/Ghosts/kodama_alpha/ghost/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    #expect(NativeShinoPersonalityEngine.supports(shioriFilename: "shino.dll"))
    let state = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "state.json")
    let engine = try NativeShinoPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    #expect(engine.loadedDictionaryFileCount == 11)
    #expect(engine.loadedEventEntryCount > 20)
    #expect(engine.loadedJumpEntryCount > 20)
    let firstBoot = try await engine.handle(event: .shiori(id: "OnFirstBoot", references: [0: "0"]))
    #expect(firstBoot?.rawValue.contains("ここはどこ") == true)
    #expect(firstBoot?.rawValue.contains("\\s_jmp") == false)
    let boot = try await engine.handle(event: .shiori(id: "OnBoot", references: [:]))
    #expect(boot?.rawValue.contains("\\0") == true)
    let talk = try await engine.handle(event: .randomTalk)
    #expect(talk?.rawValue.contains("\\e") == true)
    let choice = try await engine.handle(event: .choice(id: "firstboot", arguments: []))
    #expect(choice?.rawValue.contains("\\q0[") == true)
    let mouseEvent = GhostMouseEvent(kind: .click, scope: 0, region: "Bust", x: 40, y: 40)
    let bustClick = try await engine.handle(event: .mouse(mouseEvent))
    #expect(bustClick?.rawValue.contains("むに") == true)
    for _ in 0 ..< 5 {
        _ = try await engine.handle(event: .mouse(mouseEvent))
    }
    let repeatedBustClick = try await engine.handle(event: .mouse(mouseEvent))
    #expect(repeatedBustClick?.rawValue.contains("何やってるんですか") == true)
    let menu = try await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 0,
        region: "Bust",
        x: 40,
        y: 40
    )))
    #expect(menu?.rawValue.contains("テストメニュー") == true)
}

@Test func `installed kodama metadata selects shino`() throws {
    let root = repositoryRoot.appending(path: "Content/Local/Ghosts/kodama_alpha", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    let ghost = try GhostPackageLoader().loadGhost(at: root)
    #expect(ghost.shioriFilename == "shino.dll")
    #expect(NativeShinoPersonalityEngine.supports(shioriFilename: ghost.shioriFilename))
}

private let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func `installed kodama boot only`() async throws {
    let master = repositoryRoot.appending(path: "Content/Local/Ghosts/kodama_alpha/ghost/master", directoryHint: .isDirectory)
    let engine = try NativeShinoPersonalityEngine(
        masterDirectoryURL: master,
        stateStoreURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "state.json")
    )
    let boot = try await engine.handle(event: .shiori(id: "OnBoot", references: [:]))
    #expect(boot?.rawValue.contains("\\0") == true)
}

@Test func `installed kodama random talk only`() async throws {
    let master = repositoryRoot.appending(path: "Content/Local/Ghosts/kodama_alpha/ghost/master", directoryHint: .isDirectory)
    let engine = try NativeShinoPersonalityEngine(masterDirectoryURL: master)
    let talk = try await engine.handle(event: .randomTalk)
    #expect(talk?.rawValue.contains("\\e") == true)
}

@Test func `evaluates shino functions arithmetic categories and same line alternatives`() async throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    let descriptionData = try #require("sakura.name,Test\nkero.name,Kero\n".data(using: .utf8))
    try descriptionData.write(to: master.appending(path: "descript.txt"))
    let dictionary = """
    \\fn[twice], {%argv[0]*2}
    \\ms, Alpha, Beta
    \\mz, Gamma
    \\ev[OnFunction], %twice[3]
    \\ev[OnWord], %ms9
    \\ev[OnFakeAI], %mと%m2は関係がありますよね？
    \\ev[OnStrings], %len[あA]|%left[あA,2]|%right[Aあ,2]|%substr[AあB,1,2]|%instr[AあB,あ]|%isupper[ＡB]|%islower[ａb]|%tohankaku[ＡＢ]|%tozenkaku[AB]
    \\ev[OnLoop], %for[$i=0,$i<3,$i+=1,x]
    \\ev[OnSystem], %siover|%ver|%plathome|%et
    \\ev[OnSaori], %saori[test.dll,one,two]|%saoriresult[1]
    \\ev[OnAlternative], first, second
    \\ev[OnParenthesizedCondition,(%hour%2==%hour%2) && (3*2==6)], works
    """
    let dictionaryData = try #require(dictionary.data(using: .utf8))
    try dictionaryData.write(to: master.appending(path: "ai_test.txt"))
    let saori = ShinoSaoriStub()
    let engine = try NativeShinoPersonalityEngine(masterDirectoryURL: master, saoriCaller: saori)

    let function = try await engine.handle(event: .shiori(id: "OnFunction", references: [:]))
    let word = try await engine.handle(event: .shiori(id: "OnWord", references: [:]))
    let fakeAI = try await engine.handle(event: .shiori(id: "OnFakeAI", references: [:]))
    let strings = try await engine.handle(event: .shiori(id: "OnStrings", references: [:]))
    let loop = try await engine.handle(event: .shiori(id: "OnLoop", references: [:]))
    let system = try await engine.handle(event: .shiori(id: "OnSystem", references: [:]))
    let saoriResult = try await engine.handle(event: .shiori(id: "OnSaori", references: [:]))
    let alternative = try await engine.handle(event: .shiori(id: "OnAlternative", references: [:]))
    let parenthesized = try await engine.handle(event: .shiori(id: "OnParenthesizedCondition", references: [:]))
    #expect(function?.rawValue == "6")
    #expect(["Alpha", "Beta"].contains(word?.rawValue))
    #expect(fakeAI?.rawValue.contains("%m") == false)
    #expect(fakeAI?.rawValue.hasPrefix("とは") == false)
    #expect(strings?.rawValue == "3|あ|あ|あ|1|1|1|AB|ＡＢ")
    #expect(loop?.rawValue == "xxx")
    #expect(system?.rawValue.contains("%") == false)
    #expect(saori.loaded == ["test.dll"])
    #expect(saori.arguments == ["one", "two"])
    #expect(saoriResult?.rawValue == "result|value1")
    #expect(["first", "second"].contains(alternative?.rawValue))
    #expect(parenthesized?.rawValue == "works")
}

private final class ShinoSaoriStub: NativeSaoriCalling, @unchecked Sendable {
    var loaded: [String] = []
    var arguments: [String] = []

    func load(_ path: String) {
        loaded.append(path)
    }

    func unload(_: String) {}

    func call(_: String, arguments: [String]) -> String {
        self.arguments = arguments
        return "result\u{1}value1"
    }
}

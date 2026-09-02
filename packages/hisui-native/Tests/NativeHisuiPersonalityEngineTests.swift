import Foundation
import Testing
import UtataneCore
@testable import UtataneHisuiNative

@Test(.enabled(if: hasInstalledGosji)) func `loads installed gosji hisui ghost`() async throws {
    let master = installedGosjiMaster
    #expect(NativeHisuiPersonalityEngine.supports(shioriFilename: "hisui.dll"))
    let state = FileManager.default.temporaryDirectory.appending(path: "hisui-state-\(UUID()).json")
    let engine = try NativeHisuiPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    let boot = try await engine.handle(event: .shiori(id: "OnBoot", references: [:]))
    #expect(boot?.rawValue.isEmpty == false)
    #expect(boot?.rawValue.contains("%if(") == false)
    #expect(boot?.rawValue.contains("¥") == false)
    #expect(boot?.rawValue.contains("\\s[") == true)
    #expect(boot?.rawValue.contains("\n") == false)
    #expect(boot?.rawValue.contains("i[360]") == false)

    let face = try await engine.handle(event: .mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: "face",
        x: 20,
        y: 30
    )))
    #expect(face?.rawValue.contains("目突き") == true || face?.rawValue.contains("女性に手を") == true)
    #expect(face?.rawValue.contains("%strcmp") == false)

    let menu = try await engine.handle(event: .mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: nil,
        x: 20,
        y: 30
    )))
    #expect(menu?.rawValue.contains("#ghosttalk") == true)
    #expect(menu?.rawValue.contains("\\q0[") == true)
    #expect(menu?.rawValue.contains("¥q") == false)
    #expect(menu?.rawValue.contains("\n") == false)

    let profile = try await engine.handle(event: .choice(id: "#fir_prof", arguments: []))
    #expect(profile?.rawValue.contains("自己紹介") == true)
    #expect(profile?.rawValue.contains("%token") == false)

    let talk = try await engine.handle(event: .randomTalk)
    #expect(talk?.rawValue.isEmpty == false)
    #expect(talk?.rawValue.contains("\\formula") == false)

    let interval = try await engine.handle(event: .choice(id: "freq1", arguments: []))
    #expect(interval?.rawValue.contains("i[360]") == false)
    let restored = try NativeHisuiPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    let intervalMenu = try await restored.handle(event: .choice(id: "#talkratio", arguments: []))
    #expect(intervalMenu?.rawValue.contains("現在値：360秒間隔") == true)

    let homeURL = try await engine.handle(event: .shiori(id: "homeurl", references: [:]))
    #expect(homeURL?.rawValue.contains("http://www.kyoto.zaq.ne.jp/burst/update/") == true)
    #expect(FileManager.default.fileExists(atPath: state.path))
}

@Test func `loads configuration words expressions emotion limits and learning dictionaries`() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(path: "hisui-fixture-\(UUID())", directoryHint: .isDirectory)
    let vendor = root.appending(path: "vendor", directoryHint: .isDirectory)
    let learning = root.appending(path: "learning", directoryHint: .isDirectory)
    try manager.createDirectory(at: vendor, withIntermediateDirectories: true)
    try manager.createDirectory(at: learning, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }

    try "sakura.name,翡翠\nkero.name,相方\n".write(
        to: root.appending(path: "descript.txt"),
        atomically: true,
        encoding: .utf8
    )
    try """
    <HisuiConfiguration>
      <GhostProfile birthday="2001/05/03" emotion_border="50" talk_interval="45" />
      <RunEnvironment>
        <Directory type="vender" name="vendor/" />
        <Directory type="learning" name="learning/" />
      </RunEnvironment>
      <DefaultCategory><Define type="ms" category="固定" /></DefaultCategory>
    </HisuiConfiguration>
    """.write(to: root.appending(path: "hisuiconf.xml"), atomically: true, encoding: .utf8)
    try """
    {
    token:OnConfigure
    script:\\formula[__Emotion = (20 + 15) * 2]configured
    }
    {
    token:OnLimited
    emotionlimiter:30
    script:blocked
    }
    {
    token:OnLimited
    script:fallback:%[__Emotion]
    }
    {
    token:OnRead
    conditional:%[__Emotion] == 50
    script:%[__TalkInterval]|%[__EmotionBorder]|%[__GhostBirthday]|%ms|%ref1Byte
    }
    """.write(to: vendor.appending(path: "fixture.tlk"), atomically: true, encoding: .utf8)
    try """
    {
    token:OnLearned
    script:learned
    }
    """.write(to: learning.appending(path: "learned.tlk"), atomically: true, encoding: .utf8)
    let words = "[HISUI DICTIONARY]\r\n[固定]\r\n単語\r\n"
    try #require(words.data(using: .utf16)).write(to: vendor.appending(path: "words.mem"))

    let state = root.appending(path: "state.json")
    let engine = try NativeHisuiPersonalityEngine(masterDirectoryURL: root, stateStoreURL: state)
    _ = try await engine.handle(event: .shiori(id: "OnConfigure", references: [:]))
    let limited = try await engine.handle(event: .shiori(id: "OnLimited", references: [:]))
    #expect(limited?.rawValue == "fallback:50")
    let read = try await engine.handle(event: .shiori(id: "OnRead", references: [1: "あ"]))
    #expect(read?.rawValue == "45|50|2001/05/03|単語|2")
    let learned = try await engine.handle(event: .shiori(id: "OnLearned", references: [:]))
    #expect(learned?.rawValue == "learned")

    let restored = try NativeHisuiPersonalityEngine(masterDirectoryURL: root, stateStoreURL: state)
    let restoredLimit = try await restored.handle(event: .shiori(id: "OnLimited", references: [:]))
    #expect(restoredLimit?.rawValue == "fallback:50")
}

@Test func `loads legacy preference configuration without XML`() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(path: "hisui-preference-\(UUID())", directoryHint: .isDirectory)
    let vendor = root.appending(path: "legacy_vendor", directoryHint: .isDirectory)
    let learning = root.appending(path: "legacy_learning", directoryHint: .isDirectory)
    try manager.createDirectory(at: vendor, withIntermediateDirectories: true)
    try manager.createDirectory(at: learning, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }

    try "sakura.name,翡翠\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    try """
    emotion_ghost_birthday="2002/01/02"
    emotion_border="12"
    dir_venderDic="legacy_vendor\\"
    dir_lernDic="legacy_learning\\"
    talk_interval="77"
    dic_ms="固定"
    """.write(to: root.appending(path: "hisui_preference.def"), atomically: true, encoding: .utf8)
    try """
    {
    token:OnBoot
    script:%[__TalkInterval]|%[__EmotionBorder]|%[__GhostBirthday]|%ms
    }
    """.write(to: vendor.appending(path: "fixture.tlk"), atomically: true, encoding: .utf8)
    try "[HISUI DICTIONARY]\n[固定]\n旧設定\n".write(
        to: vendor.appending(path: "words.mem"),
        atomically: true,
        encoding: .utf8
    )

    let engine = try NativeHisuiPersonalityEngine(
        masterDirectoryURL: root,
        stateStoreURL: root.appending(path: "state.json")
    )
    let boot = try await engine.handle(event: .boot)
    #expect(boot?.rawValue == "77|12|2002/01/02|旧設定")
}

private let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let installedGosjiMaster = repositoryRoot.appending(
    path: "Content/Local/Ghosts/gosji_06/ghost/master",
    directoryHint: .isDirectory
)
private let hasInstalledGosji = FileManager.default.fileExists(atPath: installedGosjiMaster.path)

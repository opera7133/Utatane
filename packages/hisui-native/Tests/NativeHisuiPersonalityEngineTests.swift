import Foundation
import Testing
import UtataneCore
@testable import UtataneHisuiNative

@Test func `loads installed gosji hisui ghost`() async throws {
    let master = repositoryRoot.appending(path: "Content/Local/Ghosts/gosji_06/ghost/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: master.path) else { return }
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

private let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

import Foundation
import Testing
import UtataneCore
import UtataneShiori
@testable import UtataneSatoriNative

@Suite(.serialized)
struct NativeSatoriSessionTests {

@Test func `native SATORI loads memory-na and answers boot`() throws {
    let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
    try #require(FileManager.default.fileExists(atPath: source.path))
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: master)

    let session = try NativeSatoriSession(masterDirectoryURL: master)
    let request = GhostEventShioriAdapter().request(for: .boot)
    let response = try session.request(request)
    #expect((200 ..< 300).contains(response.statusCode))
    #expect(response.value?.isEmpty == false)
}

@Test func `native SATORI decodes mixed encoding in memory-na dialogue`() throws {
    let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: master)

    let session = try NativeSatoriSession(masterDirectoryURL: master)
    let event = GhostEvent.mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: "Head",
        x: 100,
        y: 100,
        button: 0
    ))
    let response = try session.request(GhostEventShioriAdapter().request(for: event))
    #expect(response.value?.contains("�") == false)
    #expect(response.value?.contains("静電防止手袋") == true)
}

@Test func `detects SATORI ghost configuration`() {
    let master = repositoryRoot.appending(path: "Content/Local/Ghosts/twin/ghost/master", directoryHint: .isDirectory)
    #expect(NativeSatoriPersonalityEngine.supports(masterDirectoryURL: master))
}

@Test func `native SATORI personality maps boot to SakuraScript`() async throws {
    let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: master)

    let engine = try NativeSatoriPersonalityEngine(masterDirectoryURL: master)
    let script = try await engine.handle(event: .boot)
    #expect(script?.rawValue.isEmpty == false)
}

@Test(arguments: ["memory-na", "twin", "sake_kami"])
func `installed SATORI ghosts answer boot`(_ ghostDirectoryName: String) throws {
    let source = repositoryRoot.appending(
        path: "Content/Local/Ghosts/\(ghostDirectoryName)/ghost/master",
        directoryHint: .isDirectory
    )
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: master)

    let session = try NativeSatoriSession(masterDirectoryURL: master)
    let response = try session.request(GhostEventShioriAdapter().request(for: .boot))
    #expect((200 ..< 300).contains(response.statusCode))
    if ghostDirectoryName == "twin" {
        #expect(response.value?.contains("\\![embed,OnCallSurface") == true)
        _ = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnSetScope", references: [0: "0"])))
        let surface0 = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnCallSurface", references: [0: "5"])))
        _ = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnSetScope", references: [0: "1"])))
        let surface1 = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnCallSurface", references: [0: "0"])))
        #expect(surface0.value == "\\s[5]")
        #expect(surface1.value == "\\s[10000]")
        let shellChanged = try session.request(GhostEventShioriAdapter().request(for: .shiori(
            id: "OnShellChanged",
            references: [0: "master2nd", 1: "master2nd"]
        )))
        #expect(shellChanged.value?.contains("OnCallSurface") == true)
        let shiftJISContext = ShioriEventContext(charset: "Shift_JIS")
        let setting = try session.request(GhostEventShioriAdapter().request(
            for: .shiori(id: "OnChoiceSelect", references: [0: "追加選択肢設定画面"]),
            context: shiftJISContext
        ))
        #expect(setting.value?.contains("OnSetExTalk") == true)
        let close = try session.request(GhostEventShioriAdapter().request(
            for: .shiori(id: "OnChoiceSelect", references: [0: "閉じる"]),
            context: shiftJISContext
        ))
        #expect(close.value?.isEmpty != false)
    }
}

}

private let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

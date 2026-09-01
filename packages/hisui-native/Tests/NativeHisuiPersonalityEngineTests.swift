import Foundation
import Testing
import UtataneCore
@testable import UtataneHisuiNative

@Test func `loads installed gosji hisui ghost`() async throws {
    let master = repositoryRoot.appending(path: "Content/Local/Ghosts/gosji_06/ghost/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    #expect(NativeHisuiPersonalityEngine.supports(shioriFilename: "hisui.dll"))
    let engine = try NativeHisuiPersonalityEngine(masterDirectoryURL: master)
    let boot = try await engine.handle(event: .shiori(id: "OnBoot", references: [:]))
    #expect(boot?.rawValue.isEmpty == false)
    #expect(boot?.rawValue.contains("%if(") == false)
}

private let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

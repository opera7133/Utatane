import Foundation
import Testing
import UtataneCore
@testable import UtataneMakoto
import UtataneRuntime
import UtataneSakuraScript

@Test
func `selects Korean particles like ParticleMakoto 2_3`() {
    let translator = ParticleMakotoTranslator()

    #expect(translator.translate("사과[은]/는 밥[을]/를 먹는다") == "사과는 밥을 먹는다")
    #expect(translator.translate("사과[이]/가 밥[와]/과 있다") == "사과가 밥과 있다")
    #expect(translator.translate("학교[으]로 가고 밥[이]다") == "학교로 가고 밥이다")
    #expect(translator.translate("서울[으]로 간다") == "서울으로 간다")
}

@Test
func `supports ParticleMakoto 1 compatible semicolon markers`() {
    let translator = ParticleMakotoTranslator()

    #expect(translator.translate("사과[은;는] 밥[을;를] 먹는다") == "사과는 밥을 먹는다")
    #expect(translator.translate("사과[이;가] 밥[와;과] 있다") == "사과가 밥과 있다")
    #expect(translator.translate("학교[으;로] 가고 밥[이;]다") == "학교로 가고 밥이다")
}

@Test
func `matches ParticleMakoto digit and Latin suffix handling`() {
    let translator = ParticleMakotoTranslator()

    #expect(translator.translate("1[이] 2[이] B[이] A[이] Linux[이]") == "1이 2 B이 A Linux이")
}

@Test
func `uses the last alphanumeric character before a marker`() {
    let translator = ParticleMakotoTranslator()

    #expect(translator.translate("\\0밥! [은]/는") == "\\0밥! 은")
    // The original module sees the wait argument's final 8 rather than parsing SakuraScript.
    #expect(translator.translate("\\0사과\\w8[은]/는") == "\\0사과\\w8은")
}

@Test
func `detects the locally installed ParticleMakoto ghost when available`() {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let masterDirectory = repositoryRoot.appending(
        path: "Content/Local/Ghosts/nisesakura_rebirth2_008/ghost/master",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: masterDirectory.path) else { return }

    #expect(ParticleMakotoTranslator.supports(masterDirectoryURL: masterDirectory))
}

@Test
func `detects ParticleMakoto configuration case insensitively`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data().write(to: directory.appending(path: "MAKOTO.DLL"))
    try Data("[ParticleMakoto]\nMakoto1Compatible=1\n".utf8)
        .write(to: directory.appending(path: "MAKOTO.INI"))

    #expect(ParticleMakotoTranslator.supports(masterDirectoryURL: directory))
}

@Test
func `translates handle and response results while preserving references`() async throws {
    let engine = TranslatingPersonalityEngine(
        base: StubPersonalityEngine(),
        translators: [ParticleMakotoTranslator()]
    )

    #expect(try await engine.handle(event: .boot)?.rawValue == "밥이다")
    let response = try await engine.response(for: .randomTalk)
    #expect(response.script?.rawValue == "사과다")
    #expect(response.references == [0: "preserved"])
}

private struct StubPersonalityEngine: PersonalityEngine {
    func handle(event _: GhostEvent) async throws -> SakuraScript? {
        SakuraScript(rawValue: "밥[이]다")
    }

    func response(for _: GhostEvent) async throws -> PersonalityResponse {
        PersonalityResponse(
            script: SakuraScript(rawValue: "사과[이]다"),
            references: [0: "preserved"]
        )
    }
}

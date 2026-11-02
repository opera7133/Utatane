import AppKit
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneShell

@Suite(.serialized)
@MainActor
struct EnvironmentPlaybackTests {
    @Test(arguments: [false, true])
    func `escaped percent survives expansion translation and playback`(notranslate: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makePNG(width: 40, height: 60).write(to: root.appending(path: "surface0.png"))
        try makePNG(width: 500, height: 120).write(to: root.appending(path: "balloons0.png"))
        let (defaults, positions) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let surfaces = SurfaceWindowController(positionStore: positions)
        try surfaces.show(shell: ShellLoader().load(from: root), surfaceID: 0)
        let balloons = BalloonWindowController(positionStore: positions)
        let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
        defer { player.cancel(); surfaces.resetContent(); balloons.hideAll() }
        player.configure(environmentVariables: ["selfname": "さくら", "selfname2": "別名", "month": "11"])
        var translated: String?
        player.onTranslate = { script, _ in translated = script.rawValue; return nil }
        let cases: [(String, String, String)] = [
            (#"\0\%selfname|\%month\e"#, #"\0\%selfname|\%month\e"#, "%selfname|%month"),
            (#"\0%SELFNAME|%selfname2|%month\e"#, #"\0さくら|別名|11\e"#, "さくら|別名|11"),
            (#"\0\\%selfname|\\\%selfname\e"#, #"\0\\さくら|\\\%selfname\e"#, #"\さくら|\%selfname"#)
        ]
        for (source, expanded, text) in cases {
            translated = nil
            await player.playAndWait(.init(rawValue: source), balloon: makeBalloon(directory: root), characterDelayMilliseconds: 0,
                                     context: .init(flags: notranslate ? ["notranslate"] : []))
            #expect(translated == (notranslate ? nil : expanded))
            #expect(balloons.textAndLinks(for: 0)?.0 == text)
        }
        if !notranslate {
            player.onTranslate = { _, _ in .init(rawValue: #"\0\%selfname\e"#) }
            await player.playAndWait(.init(rawValue: #"\0%selfname\e"#), balloon: makeBalloon(directory: root), characterDelayMilliseconds: 0)
            #expect(balloons.textAndLinks(for: 0)?.0 == "%selfname")
        }
    }
}

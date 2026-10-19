import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test @MainActor func `sound loads selected external audio and Windows separated paths`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let master = root.appending(path: "ghost/master")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    // 100 ms of mono 16-bit PCM silence; loading does not play it aloud.
    var wave = Data()
    func text(_ value: String) {
        wave.append(contentsOf: value.utf8)
    }
    func integer(_ value: UInt32, bytes: Int) {
        for offset in 0 ..< bytes {
            wave.append(UInt8(truncatingIfNeeded: value >> (8 * offset)))
        }
    }
    text("RIFF"); integer(1636, bytes: 4); text("WAVEfmt ")
    integer(16, bytes: 4); integer(1, bytes: 2); integer(1, bytes: 2)
    integer(8000, bytes: 4); integer(16000, bytes: 4); integer(2, bytes: 2); integer(16, bytes: 2)
    text("data"); integer(1600, bytes: 4); wave.append(Data(repeating: 0, count: 1600))
    let external = root.appending(path: "外部 ソング.wav")
    try wave.write(to: external)
    try wave.write(to: master.appending(path: "bundled.wav"))
    let player = SakuraScriptSoundPlayer()
    player.resourceBaseDirectory = master
    defer { player.discard() }
    var stopped: [String] = []
    var errors: [String] = []
    player.onStop = { file, _ in stopped.append(file) }
    player.onError = { file, _ in errors.append(file) }
    let paths = ["bundled.wav", external.path, external.path.replacingOccurrences(of: "/", with: "\\")]
    for path in paths {
        try await player.execute(.load(file: path, options: []))
        #expect(player.propertyValue(for: "currentghost.sound.index(0).name") == path)
        #expect(player.propertyValue(for: "currentghost.sound(\(path)).duration") == "100")
        #expect(player.propertyValue(for: "currentghost.sound.index(1).name") == nil)
        try await player.execute(.stop)
    }
    #expect(errors.isEmpty)
    #expect(stopped.isEmpty)
    try await player.execute(.load(file: "../../外部 ソング.wav", options: []))
    #expect(errors == ["../../外部 ソング.wav"])

    // Force mute independently of ghost options, including subsequent changes.
    player.isMuted = true
    try await player.execute(.play(file: external.path, loop: true, options: ["--volume=100"]))
    #expect(player.outputVolume == 0)
    #expect(player.propertyValue(for: "currentghost.sound.count") == "1")
    #expect(player.propertyValue(for: "currentghost.sound.index(0).playing") == "1")
    try await player.execute(.option(file: nil, options: ["--volume=100", "--seektime=50"]))
    #expect(player.outputVolume == 0)
    try await player.execute(.pause)
    #expect(player.propertyValue(for: "currentghost.sound.index(0).pause") == "1")
    #expect(player.propertyValue(for: "currentghost.sound.index(0).playing") == "1")
    #expect(Int(player.propertyValue(for: "currentghost.sound.index(0).position") ?? "") ?? 0 >= 50)
    try await player.execute(.resume)
    #expect(player.outputVolume == 0)
    try await player.execute(.stop)
    #expect(stopped.isEmpty)
    #expect(player.propertyValue(for: "currentghost.sound.count") == "0")
    try await player.execute(.load(file: external.path, options: []))
    var countOnCompletion: String?
    player.onStop = { file, reason in
        stopped.append(file)
        #expect(reason == "end")
        countOnCompletion = player.propertyValue(for: "currentghost.sound.count")
    }
    player.handlePlaybackFinished(successfully: true)
    #expect(stopped == [external.path])
    #expect(countOnCompletion == "0")
}

@Test @MainActor func `sound completion distinguishes loop stop and error`() {
    #expect(SakuraScriptSoundPlayer.completionAction(isLooping: true, successfully: true) == .loop)
    #expect(SakuraScriptSoundPlayer.completionAction(isLooping: false, successfully: true) == .stop)
    #expect(SakuraScriptSoundPlayer.completionAction(isLooping: true, successfully: false) == .error)
}

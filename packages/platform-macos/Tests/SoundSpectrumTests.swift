import AVFoundation
import Foundation
import Testing
@testable import UtatanePlatformMacOS

private func makeSpectrumWave() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "spectrum-\(UUID()).wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000))
    buffer.frameLength = buffer.frameCapacity
    let samples = try #require(buffer.floatChannelData)
    for index in 0 ..< Int(buffer.frameLength) {
        samples[0][index] = 0.5 * sin(2 * .pi * 1000 * Float(index) / 48000)
        samples[1][index] = 0.25 * sin(2 * .pi * 4000 * Float(index) / 48000)
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

@Test func `spectrum measures stereo levels and ISO bands without audio output`() throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let analyzer = try SoundSpectrumAnalyzer(url: url)
    for count in [5, 10, 15, 31] {
        let levels = try analyzer.levels(at: 1, bands: count)
        #expect(levels.count == count + 2)
        #expect(abs(levels[0] - 90) < 1)
        #expect(abs(levels[1] - 80) < 1)
        let ranges = SoundSpectrumAnalyzer.bandRanges(count)
        let thousand = try #require(ranges.firstIndex { $0.contains(1000) })
        let fourThousand = try #require(ranges.firstIndex { $0.contains(4000) })
        #expect(abs(levels[thousand + 2] - 80) < 1) // channels averaged before FFT
        #expect(abs(levels[fourThousand + 2] - 70) < 1)
    }
    #expect(try analyzer.levels(at: 1, bands: 0).count == 2)
}

@Test func `spectrum envelopes release and hold according to elapsed time`() {
    var envelope = SoundSpectrumEnvelope()
    #expect(envelope.update([90], at: 0, hold: 0.5).levels == [90])
    let falling = envelope.update([0], at: 0.1, hold: 0.5)
    #expect(falling.levels == [70])
    #expect(falling.peaks == [90])
    #expect(envelope.update([0], at: 0.6, hold: 0.5).peaks == [80])
    #expect(envelope.update([0], at: 0.7, hold: 0).peaks == [0])
}

@Test @MainActor func `sound spectrum cadence position pause and stop use one muted source`() async throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let player = SakuraScriptSoundPlayer()
    player.isMuted = true
    defer { player.discard() }
    var frames: [[Int: String]] = []
    player.onSpectrum = { frames.append($0) }
    try await player.execute(.play(file: url.path, loop: true, options: ["--volume=100", "--spectrum=50", "--spectrum-bands=31"]))
    try await requireEventually { frames.count >= 5 }
    #expect(player.outputVolume == 0)
    let frame = try #require(frames.last)
    #expect(frame[0] == url.path)
    #expect(frame[1] == "31")
    #expect(frame[2]?.split(separator: "\u{1}").count == 2)
    #expect(frame[4]?.split(separator: "\u{1}").count == 31)
    let position = try #require(Int(frame[6] ?? ""))
    #expect(position >= 0)
    #expect(frames.contains { (Int($0[6] ?? "") ?? 0) > 0 })
    try await player.execute(.pause)
    let pausedCount = frames.count
    let deadline = ContinuousClock.now + .milliseconds(150)
    try await requireEventually { ContinuousClock.now >= deadline }
    #expect(frames.count == pausedCount)
    try await player.execute(.resume)
    try await requireEventually { frames.count > pausedCount }
    try await player.execute(.option(file: nil, options: ["--spectrum=0"]))
    #expect(frames.last?[4]?.split(separator: "\u{1}").allSatisfy { $0 == "0" } == true)
    let disabledCount = frames.count
    try await player.execute(.stop)
    #expect(frames.count == disabledCount)
}

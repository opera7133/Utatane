import AVFoundation
import Foundation
import Testing
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

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

@Test @MainActor func `same sound filename in different plugin folders never reuses the other audio`() async throws {
    let source = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: source) }
    let root = FileManager.default.temporaryDirectory.appending(path: "plugin-sound-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["ghost", "first", "second"] {
        let directory = root.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: directory.appending(path: "same.wav"))
    }
    let player = SakuraScriptSoundPlayer(); player.isMuted = true
    defer { player.discard() }
    player.resourceBaseDirectory = root.appending(path: "ghost")
    for name in ["first", "second", "ghost"] {
        try await player.execute(.play(file: "same.wav", loop: false, options: []), resourceDirectory: name == "ghost" ? nil : root.appending(path: name))
        #expect(player.propertyValue(for: "currentghost.sound.index(0).path") == root.appending(path: name + "/same.wav").path)
    }
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

private func makeSpectrumSignal(sampleRate: Double = 48000, channels: Int = 1,
                                sample: (Int, Int) -> Float) throws -> URL
{
    let url = FileManager.default.temporaryDirectory.appending(path: "spectrum-signal-\(UUID()).wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate)))
    buffer.frameLength = buffer.frameCapacity
    let data = try #require(buffer.floatChannelData)
    for channel in 0 ..< channels {
        for index in 0 ..< Int(buffer.frameLength) {
            data[channel][index] = sample(channel, index)
        }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

@Test func `spectrum never reads audio ahead of the playback cursor`() throws {
    let url = try makeSpectrumSignal { _, index in
        index < 1920 ? 0 : 0.5 * sin(2 * .pi * 1000 * Float(index) / 48000)
    }
    defer { try? FileManager.default.removeItem(at: url) }
    let analyzer = try SoundSpectrumAnalyzer(url: url)
    #expect(try analyzer.levels(at: 0, bands: 31) == [Double](repeating: 0, count: 32))
    #expect(try analyzer.levels(at: 0.02, bands: 31) == [Double](repeating: 0, count: 32))
    #expect(try analyzer.levels(at: 0.5, bands: 31)[0] > 89)
}

@Test(arguments: [44100.0, 48000.0])
func `spectrum mono frequency and gain agree with calibrated sine levels`(sampleRate: Double) throws {
    for (frequency, amplitude, expected) in [(1000.0, 1.0, 100.0), (4000.0, 0.1, 200.0 / 3), (8000.0, 0.01, 100.0 / 3)] {
        let url = try makeSpectrumSignal(sampleRate: sampleRate) { _, index in
            Float(amplitude * sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let analyzer = try SoundSpectrumAnalyzer(url: url)
        let band = try #require(SoundSpectrumAnalyzer.bandRanges(31).firstIndex { $0.contains(frequency) })
        let levels = try analyzer.levels(at: 0.8, bands: 31)
        #expect(abs(levels[0] - expected) < 1)
        #expect(abs(levels[band + 1] - expected) < 1)
    }
}

@Test func `spectrum averages opposite phase stereo before band analysis`() throws {
    let url = try makeSpectrumSignal(channels: 2) { channel, index in
        (channel == 0 ? 0.5 : -0.5) * sin(2 * .pi * 1000 * Float(index) / 48000)
    }
    defer { try? FileManager.default.removeItem(at: url) }
    let levels = try SoundSpectrumAnalyzer(url: url).levels(at: 0.8, bands: 31)
    #expect(abs(levels[0] - 90) < 1)
    #expect(abs(levels[1] - 90) < 1)
    #expect(levels.dropFirst(2).allSatisfy { $0 == 0 })
}

@Test @MainActor func `spectrum stop silences audio before a slow final SHIORI response`() async throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let player = SakuraScriptSoundPlayer()
    player.isMuted = true
    var finishZero: CheckedContinuation<Void, Never>?
    var ended = false
    defer { finishZero?.resume(); player.discard() }
    player.onSpectrumEnd = { ended = true }
    player.onSpectrum = { references in
        #expect(references[4]?.split(separator: "\u{1}").allSatisfy { $0 == "0" } == true)
        await withCheckedContinuation { finishZero = $0 }
    }
    try await player.execute(.play(file: url.path, loop: true, options: ["--spectrum=1000"]))
    try await player.execute(.pause)
    let stop = Task { @MainActor in try await player.execute(.stop) }
    try await requireEventually { finishZero != nil }
    #expect(ended)
    #expect(player.propertyValue(for: "currentghost.sound.count") == "0")
    #expect(player.outputVolume == nil)
    finishZero?.resume(); finishZero = nil
    try await stop.value
}

@Test @MainActor func `spectrum natural completion clears audio and sends zero before stop notification`() async throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let player = SakuraScriptSoundPlayer()
    player.isMuted = true
    defer { player.discard() }
    var events: [String] = []
    player.onSpectrumEnd = { events.append("clear") }
    player.onSpectrum = { references in
        #expect(references[4]?.split(separator: "\u{1}").allSatisfy { $0 == "0" } == true)
        #expect(player.propertyValue(for: "currentghost.sound.count") == "0")
        events.append("zero")
    }
    player.onStop = { file, reason in
        #expect(file == url.path && reason == "end")
        events.append("stop")
    }
    try await player.execute(.play(file: url.path, loop: false, options: ["--spectrum=1000"]))
    player.handlePlaybackFinished(successfully: true)
    try await requireEventually { events.contains("stop") }
    #expect(events == ["clear", "zero", "stop"])
}

@Test @MainActor func `starting a new sound cancels a pending old spectrum completion`() async throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let player = SakuraScriptSoundPlayer()
    player.isMuted = true
    var finishZero: CheckedContinuation<Void, Never>?
    defer { finishZero?.resume(); player.discard() }
    var acceptedZero = false
    var callbackReturned = false
    var stopped = false
    player.onSpectrum = { _ in
        await withCheckedContinuation { finishZero = $0 }
        callbackReturned = true
        guard !Task.isCancelled else { return }
        acceptedZero = true
    }
    player.onStop = { _, _ in stopped = true }
    try await player.execute(.play(file: url.path, loop: false, options: ["--spectrum=1000"]))
    player.handlePlaybackFinished(successfully: true)
    try await requireEventually { finishZero != nil }
    try await player.execute(.play(file: url.path, loop: true, options: []))
    let identifier = player.propertyValue(for: "currentghost.sound.index(0).id")
    finishZero?.resume(); finishZero = nil
    try await requireEventually { callbackReturned }
    #expect(!acceptedZero)
    #expect(!stopped)
    #expect(player.propertyValue(for: "currentghost.sound.index(0).id") == identifier)
    #expect(player.propertyValue(for: "currentghost.sound.count") == "1")
}

@Test @MainActor func `ending spectrum drops stale display work and continues unrelated queued scripts`() async throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaces = SurfaceWindowController(positionStore: positions)
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    player.isSoundMuted = true
    defer { player.cancel(); player.discardSoundPlayback() }
    let balloon = makeBalloon(directory: url.deletingLastPathComponent())
    await player.playAndWait(SakuraScript(rawValue: "\\![sound,load,\(url.path),--spectrum=1000]\\e"), balloon: balloon)
    #expect(player.runtimePropertyValue(for: "currentghost.sound.count") == "1")
    var pending: CheckedContinuation<SakuraScript?, Never>?
    defer { pending?.resume(returning: nil) }
    var events: [String] = []
    player.onGetProperties = { _, _ in await withCheckedContinuation { pending = $0 } }
    player.onEmbeddedNotification = { id, _ in events.append(id) }
    player.play(SakuraScript(rawValue: #"\![get,property,OnBlocked,system.second]\![notify,OnOldFrame]\e"#), balloon: balloon, context: .init(eventID: "OnSoundSpectrum"))
    try await requireEventually { pending != nil }
    player.enqueuePeriodic(SakuraScript(rawValue: #"\![notify,OnStaleFrame]\e"#), balloon: balloon, eventID: "OnSoundSpectrum")
    player.enqueue(SakuraScript(rawValue: #"\![notify,OnOtherEvent]\e"#), balloon: balloon)
    player.discardSoundPlayback()
    try await requireEventually { events.contains("OnOtherEvent") }
    pending?.resume(returning: nil); pending = nil
    #expect(events == ["OnOtherEvent"])
}

@Test @MainActor func `disabling paused spectrum emits one zero frame and clears display ownership`() async throws {
    let url = try makeSpectrumWave()
    defer { try? FileManager.default.removeItem(at: url) }
    let player = SakuraScriptSoundPlayer()
    player.isMuted = true
    defer { player.discard() }
    var cleared = 0
    var frames: [[Int: String]] = []
    player.onSpectrumEnd = { cleared += 1 }
    player.onSpectrum = { frames.append($0) }
    try await player.execute(.play(file: url.path, loop: true, options: ["--spectrum=1000"]))
    try await player.execute(.pause)
    try await player.execute(.option(file: nil, options: ["--spectrum=0"]))
    #expect(cleared == 1)
    #expect(frames.count == 1)
    #expect(frames.first?[4]?.split(separator: "\u{1}").allSatisfy { $0 == "0" } == true)
    #expect(player.propertyValue(for: "currentghost.sound.index(0).pause") == "1")
}

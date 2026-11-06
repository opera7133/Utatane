import AVFoundation
import Foundation
import Testing
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

private func eqSignal(channels: AVAudioChannelCount = 1, sampleRate: Double = 48000) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "eq-\(UUID()).wav")
    let format = try #require(soundPCMFormat(sampleRate: sampleRate, channels: Int(channels)))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * 2)))
    buffer.frameLength = buffer.frameCapacity
    for channel in 0 ..< Int(channels) {
        for sample in 0 ..< Int(buffer.frameLength) {
            buffer.floatChannelData![channel][sample] = Float(0.01 * sin(2 * .pi * (channel == 0 ? 1000 : 4000) * Double(sample) / sampleRate))
        }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

@Suite(.serialized)
struct SoundEqualizerTests {
    @Test func `EQ accepts complete finite colon lists clamps gains and independently resets bands`() {
        var settings = SoundEqualizerSettings()
        for count in [5, 10, 15, 31] {
            settings.apply("--eq=" + Array(repeating: "-30", count: count).joined(separator: ":"))
            #expect(settings.gains == Array(repeating: -24, count: count))
        }
        settings.apply("--eq=25:+1.5:0:-1.5:-25")
        #expect(settings.gains == [24, 1.5, 0, -1.5, -24])
        let previous = settings
        for value in ["1:2", "1:2::4:5", "1:2:nan:4:5", "1:2:inf:4:5", "1:2:text:4:5"] {
            settings.apply("--eq=" + value); #expect(settings == previous)
        }
        settings.apply("--eq-preamp=-99"); #expect(settings.preamp == -24)
        settings.apply("--eq-preamp=nan"); #expect(settings.preamp == -24)
        settings.apply("--eq="); #expect(settings.gains.isEmpty && settings.preamp == -24)
    }

    @Test(arguments: [44100.0, 48000.0])
    func `graphic EQ compensates overlap at every active ISO centre even for alternating extremes`(sampleRate: Double) {
        for count in [5, 10, 15, 31] {
            var settings = SoundEqualizerSettings()
            settings.gains = (0 ..< count).map { $0.isMultiple(of: 2) ? 24 : -24 }
            let coefficients = settings.coefficients(sampleRate: sampleRate)
            for (index, frequency) in SoundEqualizerSettings.frequencies(count).enumerated() where frequency < sampleRate * 0.45 {
                let gain = coefficients.reduce(0) { $0 + $1.decibels(at: frequency, sampleRate: sampleRate) }
                #expect(abs(gain - settings.gains[index]) < 0.01)
            }
            settings.gains = Array(repeating: 0, count: count)
            #expect(settings.coefficients(sampleRate: sampleRate).allSatisfy { $0 == .identity })
        }
        var high = SoundEqualizerSettings()
        high.gains = [0, 0, 0, 0, 24]
        #expect(high.coefficients(sampleRate: 22050).allSatisfy { $0 == .identity })
    }

    @Test func `audio processor changes volume over ten milliseconds with no instantaneous step`() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let coefficients = Array(repeating: SoundEQBiquad.identity, count: 31)
        let processor = SoundEqualizerProcessor()
        processor.configure(sampleRate: 48000, channels: 1)
        processor.set(coefficients: coefficients, gain: 1)
        buffer.floatChannelData?[0].initialize(repeating: 1, count: 480)
        processor.process(UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), frames: 480)
        processor.set(coefficients: coefficients, gain: 0)
        buffer.floatChannelData?[0].update(repeating: 1, count: 480)
        processor.process(UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), frames: 480)
        let data = try #require(buffer.floatChannelData?[0])
        #expect(data[0] > 0.99)
        #expect(abs(data[479]) < 0.00001)
        for index in 1 ..< 480 {
            #expect(abs(data[index] - data[index - 1]) < 0.0021)
        }
    }

    @Test @MainActor func `offline engine output and captured spectrum share EQ volume but exclude pan and mute`() async throws {
        let url = try eqSignal(channels: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try SoundAudioSource(contentsOf: url, manualRendering: true)
        defer { source.stop() }
        var settings = SoundEqualizerSettings(); settings.gains = [0, 0, 12, 0, 0]; settings.preamp = -6
        source.settings = settings; source.volume = 0.5; source.pan = 1; source.isMuted = true; source.capturesSpectrum = true
        #expect(source.play())
        let format = source.engine.manualRenderingFormat
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        for _ in 0 ..< 8 {
            #expect(try source.engine.renderOffline(4096, to: buffer) == .success)
        }
        #expect((0 ..< Int(buffer.frameLength)).allSatisfy { buffer.floatChannelData![0][$0] == 0 && buffer.floatChannelData![1][$0] == 0 })
        let worker = SoundSpectrumWorker(samples: source.spectrumSamples)
        let frame = try await worker.analyze(url: url, position: source.currentTime, bands: 5)
        #expect(abs(frame.levels[0] - 33.3) < 1)
        #expect(abs(frame.levels[1] - 13.3) < 1)
        source.isMuted = false
        for _ in 0 ..< 2 {
            #expect(try source.engine.renderOffline(4096, to: buffer) == .success)
        }
        let left = (0 ..< Int(buffer.frameLength)).reduce(0.0) { $0 + Double(buffer.floatChannelData![0][$1] * buffer.floatChannelData![0][$1]) }
        let right = (0 ..< Int(buffer.frameLength)).reduce(0.0) { $0 + Double(buffer.floatChannelData![1][$1] * buffer.floatChannelData![1][$1]) }
        #expect(left < right * 0.001)
        #expect(right > 0)
        let after = try await worker.analyze(url: url, position: source.currentTime, bands: 5)
        #expect(abs(after.levels[0] - frame.levels[0]) < 1)
        source.pause(); source.currentTime = 0.5
        #expect(!source.isPlaying && source.currentTime == 0.5)
        #expect(source.play())
        #expect(try source.engine.renderOffline(4096, to: buffer) == .success)
        #expect(source.currentTime >= 0.5)
    }

    @Test @MainActor func `live sound options apply EQ volume reset and paused seek to actual spectrum`() async throws {
        let url = try eqSignal()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = SakuraScriptSoundPlayer(); player.isMuted = true
        defer { player.discard() }
        var levels: [Int] = []
        player.onSpectrum = { fields in levels.append(Int(fields[2] ?? "") ?? -1) }
        try await player.execute(.play(file: url.path, loop: true, options: ["--eq=0:0:12:0:0", "--volume=50", "--spectrum=20", "--spectrum-bands=5"]))
        try await requireEventually { levels.count >= 5 && (40 ... 47).contains(levels.last ?? -1) }
        try await player.execute(.option(file: nil, options: ["--volume=0", "--eq="]))
        try await requireEventually { levels.last == 0 }
        try await player.execute(.pause)
        try await player.execute(.option(file: nil, options: ["--seektime=500", "--eq-preamp=6", "--volume=100"]))
        #expect(player.propertyValue(for: "currentghost.sound.index(0).pause") == "1")
        #expect(player.propertyValue(for: "currentghost.sound.index(0).position") == "500")
        levels.removeAll()
        try await player.execute(.resume)
        try await requireEventually { levels.count >= 5 && (40 ... 47).contains(levels.last ?? -1) }
        try await player.execute(.stop)
        levels.removeAll()
        try await player.execute(.play(file: url.path, loop: false, options: ["--spectrum=20", "--spectrum-bands=0"]))
        try await requireEventually { levels.count >= 5 && (31 ... 35).contains(levels.last ?? -1) }
    }

    @Test func `EQ topology changes remain finite and smooth across the ten millisecond transition`() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192))
        buffer.frameLength = 8192
        let processor = SoundEqualizerProcessor()
        processor.configure(sampleRate: 48000, channels: 1)
        var settings = SoundEqualizerSettings(); settings.gains = [0, 0, 24, 0, 0]
        processor.set(coefficients: settings.coefficients(sampleRate: 48000), gain: 1)
        func fill(start: Int) {
            for index in 0 ..< 8192 {
                buffer.floatChannelData![0][index] = Float(0.01 * sin(2 * .pi * 1000 * Double(start + index) / 48000))
            }
        }
        fill(start: 0)
        processor.process(UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), frames: 8192)
        let previous = try #require(buffer.floatChannelData?[0][8191])
        settings.gains = (0 ..< 31).map { $0.isMultiple(of: 2) ? 24 : -24 }
        processor.set(coefficients: settings.coefficients(sampleRate: 48000), gain: 1)
        fill(start: 8192)
        processor.process(UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), frames: 8192)
        let data = try #require(buffer.floatChannelData?[0])
        #expect(abs(data[0] - previous) < 0.05)
        #expect((0 ..< 8192).allSatisfy { data[$0].isFinite && abs(data[$0]) < 0.5 })
        #expect((1 ..< 480).allSatisfy { abs(data[$0] - data[$0 - 1]) < 0.05 })
    }

    @Test @MainActor func `playing a preloaded seek at EOF completes instead of leaving a silent running source`() async throws {
        let url = try eqSignal()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = SakuraScriptSoundPlayer(); player.isMuted = true
        defer { player.discard() }
        var stops = 0
        player.onStop = { _, reason in #expect(reason == "end"); stops += 1 }
        try await player.execute(.load(file: url.path, options: ["--seektime=2000"]))
        #expect(player.propertyValue(for: "currentghost.sound.index(0).position") == "2000")
        try await player.execute(.play(file: url.path, loop: false, options: []))
        try await requireEventually { stops == 1 }
        #expect(player.propertyValue(for: "currentghost.sound.count") == "0")
    }

    @Test @MainActor func `offline EQ preserves all eight source channels before output mixing`() async throws {
        let url = try eqSignal(channels: 8)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try SoundAudioSource(contentsOf: url, manualRendering: true)
        defer { source.stop() }
        source.capturesSpectrum = true
        #expect(source.play())
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.engine.manualRenderingFormat, frameCapacity: 4096))
        for _ in 0 ..< 4 {
            #expect(try source.engine.renderOffline(4096, to: buffer) == .success)
        }
        let frame = try await SoundSpectrumWorker(samples: source.spectrumSamples).analyze(url: url, position: source.currentTime, bands: 0)
        #expect(frame.channels == 8 && frame.levels.count == 8)
        #expect(frame.levels.allSatisfy { abs($0 - 33.33) < 1 })
    }

    @Test @MainActor func `audio source resume keeps its playback cursor without a seek`() throws {
        let url = try eqSignal()
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try SoundAudioSource(contentsOf: url, manualRendering: true)
        defer { source.stop() }
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.engine.manualRenderingFormat, frameCapacity: 4096))
        #expect(source.play())
        for _ in 0 ..< 3 {
            #expect(try source.engine.renderOffline(4096, to: buffer) == .success)
        }
        let before = source.currentTime
        source.pause()
        #expect(source.currentTime == before)
        #expect(source.play())
        for _ in 0 ..< 2 {
            #expect(try source.engine.renderOffline(4096, to: buffer) == .success)
        }
        #expect(source.currentTime > before)
    }

    @Test @MainActor func `seeking a running sound to EOF emits its completion`() async throws {
        let url = try eqSignal()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = SakuraScriptSoundPlayer(); player.isMuted = true
        defer { player.discard() }
        var completed = false
        player.onStop = { _, reason in #expect(reason == "end"); completed = true }
        try await player.execute(.play(file: url.path, loop: false, options: []))
        try await player.execute(.option(file: nil, options: ["--seektime=2000"]))
        try await requireEventually { completed }
        #expect(player.propertyValue(for: "currentghost.sound.count") == "0")
    }
}

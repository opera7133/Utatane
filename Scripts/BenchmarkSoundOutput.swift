// Build with SoundAudioSource, SoundEqualizer, SoundEqualizerAudioUnit,
// SoundSpectrumSampleStore and SoundSpectrumAnalyzer using swiftc -O.
// Offline real engine graph: 20ms PCM blocks plus live-window FFT; no device output.
import AVFoundation
import Darwin
import Foundation

@main struct BenchmarkSoundOutput {
    @MainActor static func main() async throws {
        let count = Int(CommandLine.arguments[1])!, eqBands = Int(CommandLine.arguments[2])!
        let spectrumBands = Int(CommandLine.arguments[3])!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = soundPCMFormat(sampleRate: 48000, channels: 2)!
        try autoreleasepool {
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 192_000)!
            pcm.frameLength = pcm.frameCapacity
            for channel in 0 ..< 2 {
                for frame in 0 ..< Int(pcm.frameLength) {
                    pcm.floatChannelData![channel][frame] = Float(0.01 * sin(2 * .pi * Double(channel == 0 ? 1000 : 4000) * Double(frame) / 48000))
                }
            }
            var settings = format.settings; settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: pcm)
        }
        let sources = try (0 ..< count).map { _ in try SoundAudioSource(contentsOf: url, manualRendering: true) }
        defer { sources.forEach { $0.stop() } }
        let buffers = sources.map { AVAudioPCMBuffer(pcmFormat: $0.engine.manualRenderingFormat, frameCapacity: 960)! }
        let workers = sources.map { SoundSpectrumWorker(samples: $0.spectrumSamples) }
        for source in sources {
            var settings = SoundEqualizerSettings()
            settings.gains = (0 ..< eqBands).map { $0.isMultiple(of: 2) ? 6 : -6 }
            source.applyProcessing(settings, volume: 0.5)
            source.isMuted = true; source.capturesSpectrum = true
            guard source.play() else { throw CocoaError(.fileReadCorruptFile) }
        }
        for _ in 0 ..< 10 {
            for index in sources.indices {
                _ = try sources[index].engine.renderOffline(960, to: buffers[index])
                _ = try await workers[index].analyze(url: url, position: sources[index].currentTime, bands: spectrumBands)
            }
        }
        func cpu() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        let before = cpu(), start = ContinuousClock.now
        var checksum = 0.0
        for _ in 0 ..< 100 {
            for index in sources.indices {
                guard try sources[index].engine.renderOffline(960, to: buffers[index]) == .success else { throw CocoaError(.fileReadCorruptFile) }
                let frame = try await workers[index].analyze(url: url, position: sources[index].currentTime, bands: spectrumBands)
                checksum += frame.levels.reduce(0, +)
            }
        }
        let parts = start.duration(to: .now).components
        let result: [String: Any] = ["sources": count, "eqBands": eqBands, "spectrumBands": spectrumBands,
                                     "audioSecondsPerSource": 2, "notificationsPerSource": 100,
                                     "cpuSeconds": cpu() - before,
                                     "wallSeconds": Double(parts.seconds) + Double(parts.attoseconds) / 1e18, "checksum": checksum]
        try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }
}

// Compile with SoundSpectrumAnalyzer.swift using swiftc -O -parse-as-library.
// Synthetic input only; no audio output. Each process measures one scenario.
import AVFoundation
import Darwin
import Foundation

@main
struct BenchmarkSoundSpectrum {
    @MainActor static func main() async throws {
        let streams = Int(CommandLine.arguments.dropFirst().first ?? "1") ?? 1
        let bands = Int(CommandLine.arguments.dropFirst(2).first ?? "31") ?? 31
        let frames = 3000
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0 ..< 2 {
            for sample in 0 ..< 96000 {
                buffer.floatChannelData![channel][sample] = Float(sin(Double(sample) * 2 * .pi * (channel == 0 ? 1000 : 4000) / 48000)) * (channel == 0 ? 0.5 : 0.25)
            }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true])
            try file.write(from: buffer)
        }
        if CommandLine.arguments.contains("--cadence") {
            try await cadence(url: url, streams: streams, bands: bands,
                              background: CommandLine.arguments.contains("--worker"))
            return
        }
        let analyzers = try (0 ..< streams).map { _ in try SoundSpectrumAnalyzer(url: url) }
        for index in 0 ..< 100 {
            for analyzer in analyzers {
                _ = try analyzer.levels(at: 0.1 + Double(index % 80) * 0.02, bands: bands)
            }
        }
        func cpu() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        typealias ProbeAction = @convention(c) () -> Void
        typealias ProbeCount = @convention(c) () -> UInt64
        let process = dlopen(nil, RTLD_NOW)
        func action(_ name: String) -> ProbeAction? {
            dlsym(process, name).map { unsafeBitCast($0, to: ProbeAction.self) }
        }
        func counter(_ name: String) -> ProbeCount? {
            dlsym(process, name).map { unsafeBitCast($0, to: ProbeCount.self) }
        }
        let begin = action("spectrum_alloc_begin")
        let end = action("spectrum_alloc_end")
        let calls = counter("spectrum_alloc_calls")
        let bytes = counter("spectrum_alloc_bytes")
        let startCPU = cpu()
        let start = ContinuousClock.now
        begin?()
        var checksum = 0.0
        for index in 0 ..< frames {
            for analyzer in analyzers {
                checksum += try analyzer.levels(at: 0.1 + Double(index % 80) * 0.02, bands: bands).reduce(0, +)
            }
        }
        end?()
        let duration = start.duration(to: .now).components
        var result: [String: Any] = ["streams": streams, "bands": bands, "frames": frames,
                                     "cpuSeconds": cpu() - startCPU,
                                     "wallSeconds": Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                                     "checksum": checksum]
        if let calls, let bytes {
            result["observedAllocationCalls"] = calls()
            result["observedRequestedBytes"] = bytes()
        }
        try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }

    /// MainActor heartbeat delay is a synthetic scheduling measurement, not GUI acceptance.
    @MainActor static func cadence(url: URL, streams: Int, bands: Int, background: Bool) async throws {
        let analyzers = background ? [] : try (0 ..< streams).map { _ in try SoundSpectrumAnalyzer(url: url) }
        let workers = (0 ..< streams).map { _ in CadenceWorker(url: url) }
        if background {
            for worker in workers {
                try await worker.analyze(position: 0.1, bands: bands)
            }
        } else {
            for analyzer in analyzers {
                _ = try analyzer.levels(at: 0.1, bands: bands)
            }
        }
        let start = ContinuousClock.now
        let end = start + .seconds(2)
        var delays: [Double] = []
        let heartbeat = Task { @MainActor in
            var deadline = ContinuousClock.now + .milliseconds(1)
            while deadline < end {
                try await Task.sleep(until: deadline, clock: .continuous)
                let delay = deadline.duration(to: .now).components
                delays.append(max(0, Double(delay.seconds) * 1000 + Double(delay.attoseconds) / 1e15))
                deadline = .now + .milliseconds(1)
            }
        }
        var usageStart = rusage()
        getrusage(RUSAGE_SELF, &usageStart)
        let jobs = (0 ..< streams).map { index in
            Task { @MainActor in
                var deadline = start + .milliseconds(20)
                var count = 0
                while deadline < end {
                    try await Task.sleep(until: deadline, clock: .continuous)
                    let position = 0.1 + Double(count % 80) * 0.02
                    if background {
                        try await workers[index].analyze(position: position, bands: bands)
                    } else {
                        _ = try analyzers[index].levels(at: position, bands: bands)
                    }
                    count += 1
                    deadline += .milliseconds(20)
                    if deadline < .now {
                        deadline = .now + .milliseconds(20)
                    }
                }
                return count
            }
        }
        var frames = 0
        for job in jobs {
            frames += try await job.value
        }
        try await heartbeat.value
        var usageEnd = rusage()
        getrusage(RUSAGE_SELF, &usageEnd)
        func cpu(_ usage: rusage) -> Double {
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        delays.sort()
        let result: [String: Any] = ["streams": streams, "bands": bands, "frames": frames,
                                     "worker": background, "cpuSeconds": cpu(usageEnd) - cpu(usageStart),
                                     "heartbeatP95ms": delays[min(delays.count - 1, Int(Double(delays.count) * 0.95))],
                                     "heartbeatMaxms": delays.last ?? 0]
        try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }
}

private actor CadenceWorker {
    let url: URL
    private var analyzer: SoundSpectrumAnalyzer?
    init(url: URL) {
        self.url = url
    }

    func analyze(position: Double, bands: Int) throws {
        if analyzer == nil {
            analyzer = try SoundSpectrumAnalyzer(url: url)
        }
        _ = try analyzer?.levels(at: position, bands: bands)
    }
}

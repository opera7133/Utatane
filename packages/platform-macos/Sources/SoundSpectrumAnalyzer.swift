import Accelerate
import AVFoundation
import Foundation

/// Reads a small window at the playback cursor. It never opens an audio output.
/// File reads are used for offline calibration; live playback supplies post-EQ/volume PCM.
final class SoundSpectrumAnalyzer {
    private let file: AVAudioFile?
    private let sampleRate: Double
    private let inputChannels: Int
    private let buffer: AVAudioPCMBuffer
    private let size: Int
    private let transform: OpaquePointer
    private var window: [Float]
    private var mix: [Float]
    private let zero: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private let scale: Double
    private struct Band {
        let bins: Range<Int>
        let fractionalBin: Double?
    }

    private let bandsByCount: [Int: [Band]]

    convenience init(url: URL) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        try self.init(sampleRate: file.processingFormat.sampleRate, channels: Int(file.processingFormat.channelCount), file: file)
    }

    init(sampleRate: Double, channels: Int, file: AVAudioFile? = nil) throws {
        self.file = file; self.sampleRate = sampleRate; inputChannels = channels
        size = 1 << Int(log2(sampleRate * 0.085).rounded())
        guard let format = soundPCMFormat(sampleRate: sampleRate, channels: channels),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(size)),
              let transform = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.buffer = buffer
        self.transform = transform
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        mix = [Float](repeating: 0, count: size)
        zero = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size)
        imaginary = [Float](repeating: 0, count: size)
        scale = 4 / (Double(size) * window.reduce(0.0) { $0 + Double($1 * $1) })
        let step = sampleRate / Double(size)
        let nyquist = sampleRate / 2
        let binLimit = size / 2
        bandsByCount = Dictionary(uniqueKeysWithValues: [5, 10, 15, 31].map { bands in
            (bands, Self.bandRanges(bands).map { range in
                let center = (range.lowerBound + range.upperBound) / 2
                guard center < nyquist else { return Band(bins: 0 ..< 0, fractionalBin: nil) }
                let first = max(1, Int(ceil(range.lowerBound / step)))
                let end = min(binLimit, Int(ceil(range.upperBound / step)))
                let bins = first ..< max(first, end)
                // Narrow bass bands can fall entirely between two FFT bins.
                let fractionalBin = bins.isEmpty ? min(Double(binLimit - 1), max(1, center / step)) : nil
                return Band(bins: bins, fractionalBin: fractionalBin)
            })
        })
    }

    deinit { vDSP_DFT_DestroySetup(transform) }

    var channelCount: Int {
        min(8, inputChannels)
    }

    func levels(at seconds: Double, bands: Int) throws -> [Double] {
        guard let file else { throw CocoaError(.fileReadCorruptFile) }
        let cursor = min(file.length, max(0, AVAudioFramePosition(seconds * sampleRate)))
        file.framePosition = max(0, cursor - AVAudioFramePosition(size))
        let available = min(Int64(size), cursor - file.framePosition)
        guard available > 0 else { return [Double](repeating: 0, count: channelCount + bands) }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(available))
        return levels(buffer: buffer, bands: bands)
    }

    func levels(buffer: AVAudioPCMBuffer, bands: Int) -> [Double] {
        guard buffer.frameLength <= size, Int(buffer.format.channelCount) == inputChannels,
              let channels = buffer.floatChannelData else { return [Double](repeating: 0, count: channelCount + bands) }
        let count = Int(buffer.frameLength)
        if bands > 0 {
            vDSP_vclr(&mix, 1, vDSP_Length(size))
        }
        var levels: [Double] = []
        levels.reserveCapacity(channelCount + bands)
        let allChannels = inputChannels
        mix.withUnsafeMutableBufferPointer { mix in
            for channel in 0 ..< allChannels {
                var power = 0.0
                for sample in 0 ..< count {
                    let value = channels[channel][sample]
                    power += Double(value * value)
                    if bands > 0 {
                        mix[size - count + sample] += value / Float(allChannels)
                    }
                }
                if channel < channelCount {
                    levels.append(Self.level(power: 2 * power / Double(max(1, count))))
                }
            }
        }
        guard bands > 0 else { return levels }
        mix.withUnsafeMutableBufferPointer { mix in
            vDSP_vmul(mix.baseAddress!, 1, window, 1, mix.baseAddress!, 1, vDSP_Length(size))
        }
        vDSP_DFT_Execute(transform, mix, zero, &real, &imaginary)
        real.withUnsafeBufferPointer { real in
            imaginary.withUnsafeBufferPointer { imaginary in
                func binPower(at index: Int) -> Double {
                    Double(real[index] * real[index] + imaginary[index] * imaginary[index])
                }
                for band in bandsByCount[bands] ?? bandsByCount[10]! {
                    let power: Double
                    if let bin = band.fractionalBin {
                        let lower = Int(bin)
                        let fraction = bin - Double(lower)
                        power = (1 - fraction) * binPower(at: lower) + fraction * binPower(at: Int(ceil(bin)))
                    } else {
                        power = band.bins.reduce(0) { $0 + binPower(at: $1) }
                    }
                    levels.append(Self.level(power: power * scale))
                }
            }
        }
        return levels
    }

    static func level(power: Double) -> Double {
        guard power > 0 else { return 0 }
        return min(100, max(0, (10 * log10(power) + 60) * 100 / 60))
    }

    static func bandRanges(_ count: Int) -> [Range<Double>] {
        let edges: [Double] = switch count {
        case 5: [32, 125, 500, 2000, 8000, 32000]
        case 15: [20, 32, 50, 79, 126, 200, 316, 502, 794, 1265, 2000, 3162, 5020, 7937, 12649, 20239]
        case 31: [18, 22, 28, 36, 45, 56, 71, 89, 112, 141, 179, 224, 281, 355, 447, 561, 710, 894,
                  1118, 1414, 1789, 2236, 2806, 3550, 4472, 5612, 7099, 8944, 11180, 14142, 17889, 22361]
        default: [23, 45, 89, 177, 354, 707, 1414, 2828, 5657, 11314, 22627]
        }
        return zip(edges, edges.dropFirst()).map { $0 ..< $1 }
    }
}

struct SoundSpectrumFrame: Sendable {
    let channels: Int
    let levels: [Double]
}

protocol SoundSpectrumAnalyzing: Sendable {
    func analyze(url: URL, position: Double, bands: Int) async throws -> SoundSpectrumFrame
}

/// One worker per loaded sound. File opening, decoding and FFT stay on this actor.
actor SoundSpectrumWorker: SoundSpectrumAnalyzing {
    private var analyzer: SoundSpectrumAnalyzer?
    private let samples: SoundSpectrumSampleStore?
    private var snapshot: AVAudioPCMBuffer?

    init(samples: SoundSpectrumSampleStore? = nil) {
        self.samples = samples
    }

    func analyze(url: URL, position: Double, bands: Int) throws -> SoundSpectrumFrame {
        try Task.checkCancellation()
        let analyzer: SoundSpectrumAnalyzer
        if let existing = self.analyzer {
            analyzer = existing
        } else {
            if let samples {
                analyzer = try SoundSpectrumAnalyzer(sampleRate: samples.sampleRate, channels: samples.channels)
                let format = soundPCMFormat(sampleRate: samples.sampleRate, channels: samples.channels)!
                snapshot = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.capacity))
            } else {
                analyzer = try SoundSpectrumAnalyzer(url: url)
            }
            self.analyzer = analyzer
        }
        let levels: [Double]
        if let samples, let snapshot {
            samples.copyLatest(into: snapshot)
            levels = analyzer.levels(buffer: snapshot, bands: bands)
        } else {
            levels = try analyzer.levels(at: position, bands: bands)
        }
        try Task.checkCancellation()
        return SoundSpectrumFrame(channels: analyzer.channelCount, levels: levels)
    }
}

struct SoundSpectrumEnvelope {
    private var levels: [Double] = []
    private var peaks: [Double] = []
    private var expires: [Double] = []
    private var previousTime: Double?

    mutating func update(_ values: [Double], at time: Double, hold: Double) -> (levels: [Int], peaks: [Int]) {
        if levels.count != values.count {
            self = .init(); levels = values; peaks = values; expires = values.map { _ in time + hold }
        }
        let elapsed = max(0, time - (previousTime ?? time))
        let previous = previousTime ?? time
        previousTime = time
        for index in values.indices {
            levels[index] = max(values[index], levels[index] - elapsed * 200)
            if hold == 0 {
                peaks[index] = levels[index]
            } else {
                peaks[index] = max(levels[index], peaks[index] - max(0, time - max(previous, expires[index])) * 100)
                if levels[index] >= peaks[index] {
                    expires[index] = time + hold
                }
            }
        }
        return (levels.map { Int($0.rounded()) }, peaks.map { Int($0.rounded()) })
    }
}

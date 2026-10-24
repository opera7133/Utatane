import Accelerate
import AVFoundation
import Foundation

/// Reads a small window at the playback cursor. It never opens an audio output.
/// Levels are measured before volume/pan (including the test-only output mute).
final class SoundSpectrumAnalyzer {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let size: Int
    private let transform: OpaquePointer
    private var window: [Float]

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        size = 1 << Int(log2(file.processingFormat.sampleRate * 0.085).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(size)),
              let transform = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.buffer = buffer
        self.transform = transform
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_DFT_DestroySetup(transform) }

    var channelCount: Int {
        min(8, Int(file.processingFormat.channelCount))
    }

    func levels(at seconds: Double, bands: Int) throws -> [Double] {
        let cursor = min(file.length, max(0, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)))
        file.framePosition = max(0, cursor - AVAudioFramePosition(size))
        let available = min(Int64(size), cursor - file.framePosition)
        guard available > 0 else { return [Double](repeating: 0, count: channelCount + bands) }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(available))
        guard let channels = buffer.floatChannelData else { return [Double](repeating: 0, count: channelCount + bands) }
        let count = Int(buffer.frameLength)
        var mix = [Float](repeating: 0, count: size)
        var levels: [Double] = []
        let allChannels = Int(file.processingFormat.channelCount)
        for channel in 0 ..< allChannels {
            var power = 0.0
            for sample in 0 ..< count {
                let value = channels[channel][sample]
                power += Double(value * value)
                mix[size - count + sample] += value / Float(allChannels)
            }
            if channel < channelCount {
                levels.append(Self.level(power: 2 * power / Double(max(1, count))))
            }
        }
        guard bands > 0 else { return levels }
        for sample in 0 ..< size {
            mix[sample] *= window[sample]
        }
        let zero = [Float](repeating: 0, count: size)
        var real = zero, imaginary = zero
        vDSP_DFT_Execute(transform, mix, zero, &real, &imaginary)
        let windowPower = window.reduce(0.0) { $0 + Double($1 * $1) }
        let scale = 4 / (Double(size) * windowPower)
        let frequencyStep = file.processingFormat.sampleRate / Double(size)
        for range in Self.bandRanges(bands) {
            guard (range.lowerBound + range.upperBound) / 2 <= file.processingFormat.sampleRate / 2 else {
                levels.append(0); continue
            }
            let first = max(1, Int(ceil(range.lowerBound / frequencyStep)))
            let end = min(size / 2, Int(ceil(range.upperBound / frequencyStep)))
            var power = 0.0
            if first < end {
                for index in first ..< end {
                    power += Double(real[index] * real[index] + imaginary[index] * imaginary[index])
                }
            }
            levels.append(Self.level(power: power * scale))
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

import AVFoundation
import Foundation

/// AVAudioFormat's channel-count convenience initializers only accept mono/stereo.
func soundPCMFormat(sampleRate: Double, channels: Int) -> AVAudioFormat? {
    guard channels > 0, channels <= 65535 else { return nil }
    if channels <= 2 {
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
    }
    guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)) else { return nil }
    return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout)
}

/// A bounded, preallocated post-EQ/volume waveform window. The render thread
/// only tries locks and drops an analysis block when a snapshot is being copied.
final class SoundSpectrumSampleStore: @unchecked Sendable {
    let sampleRate: Double
    let channels: Int
    let capacity: Int
    private let lock = NSLock()
    private var samples: [Float]
    private var writeIndex = 0
    private var available = 0
    private var generation: UInt64 = 0
    private var enabled = false

    init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate; self.channels = channels
        capacity = 1 << Int(log2(sampleRate * 0.085).rounded())
        samples = Array(repeating: 0, count: capacity * channels)
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            available = 0; writeIndex = 0; generation &+= 1
        }
    }

    func invalidate() {
        lock.withLock { available = 0; writeIndex = 0; generation &+= 1 }
    }

    func captureToken() -> UInt64? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return enabled ? generation : nil
    }

    func append(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int, token: UInt64) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        guard enabled, generation == token, buffers.count == channels else { return }
        let count = min(capacity, frames), skip = frames - count
        let first = min(count, capacity - writeIndex)
        samples.withUnsafeMutableBufferPointer { destination in
            for channel in 0 ..< channels {
                guard let input = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = destination.baseAddress!.advanced(by: channel * capacity)
                base.advanced(by: writeIndex).update(from: input.advanced(by: skip), count: first)
                if count > first {
                    base.update(from: input.advanced(by: skip + first), count: count - first)
                }
            }
        }
        writeIndex = (writeIndex + count) % capacity
        available = min(capacity, available + count)
    }

    func copyLatest(into buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let output = buffer.floatChannelData else { return }
            let start = (writeIndex - available + capacity) % capacity
            let first = min(available, capacity - start)
            samples.withUnsafeBufferPointer { source in
                for channel in 0 ..< channels {
                    let base = source.baseAddress!.advanced(by: channel * capacity)
                    output[channel].update(from: base.advanced(by: start), count: first)
                    if available > first {
                        output[channel].advanced(by: first).update(from: base, count: available - first)
                    }
                }
            }
            buffer.frameLength = AVAudioFrameCount(available)
        }
    }
}

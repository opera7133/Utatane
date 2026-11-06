import AudioToolbox
import AVFoundation
import Foundation

/// Control writes targets under a lock; the render thread only tries it. Filter
/// state, ramp work arrays and sample processing belong solely to the renderer.
final class SoundEqualizerProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var target = Array(repeating: SoundEQBiquad.identity, count: 31)
    private var targetGain = 1.0
    private var revision: UInt64 = 0
    private var resetRequested = false
    private var seenRevision: UInt64 = .max
    private var current = Array(repeating: SoundEQBiquad.identity, count: 31)
    private var steps = Array(repeating: SoundEQBiquad.identity / Double.infinity, count: 31)
    private var destination = Array(repeating: SoundEQBiquad.identity, count: 31)
    private var gain = 1.0, gainStep = 0.0, destinationGain = 1.0
    private var remaining = 0
    private var initial = true
    private var states: [(Double, Double)] = []
    private var sampleRate = 48000.0
    private var activeBands = Array(repeating: 0, count: 31)
    private var activeCount = 0

    func configure(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        states = Array(repeating: (0, 0), count: channels * 31)
        initial = true; seenRevision = .max
    }

    func set(coefficients: [SoundEQBiquad], gain: Double) {
        lock.withLock { target = coefficients; targetGain = gain; revision &+= 1 }
    }

    func requestReset() {
        lock.withLock { resetRequested = true }
    }

    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        if lock.try() {
            if resetRequested {
                for index in states.indices {
                    states[index] = (0, 0)
                }
                resetRequested = false
            }
            if seenRevision != revision {
                let ramp = initial ? 0 : max(1, Int(sampleRate * 0.010))
                for index in 0 ..< 31 {
                    destination[index] = target[index]
                    steps[index] = ramp == 0 ? .identity / Double.infinity : (target[index] - current[index]) / Double(ramp)
                    if ramp == 0 {
                        current[index] = target[index]
                    }
                }
                destinationGain = targetGain
                gainStep = ramp == 0 ? 0 : (targetGain - gain) / Double(ramp)
                if ramp == 0 {
                    gain = targetGain
                }
                remaining = ramp; seenRevision = revision; initial = false
            }
            lock.unlock()
        }
        activeCount = 0
        for band in 0 ..< 31 where current[band] != .identity || (remaining > 0 && destination[band] != .identity) {
            activeBands[activeCount] = band; activeCount += 1
        }
        current.withUnsafeMutableBufferPointer { coefficients in
            states.withUnsafeMutableBufferPointer { states in
                for frame in 0 ..< frames {
                    if remaining > 0 {
                        for band in 0 ..< 31 {
                            coefficients[band] = coefficients[band] + steps[band]
                        }
                        gain += gainStep
                        remaining -= 1
                        if remaining == 0 {
                            for band in 0 ..< 31 {
                                coefficients[band] = destination[band]
                            }
                            gain = destinationGain
                        }
                    }
                    for channel in buffers.indices {
                        guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        var value = Double(data[frame])
                        for active in 0 ..< activeCount {
                            let band = activeBands[active]
                            let c = coefficients[band], index = channel * 31 + band
                            if c == .identity {
                                states[index] = (0, 0); continue
                            }
                            let output = c.b0 * value + states[index].0
                            states[index] = (c.b1 * value - c.a1 * output + states[index].1, c.b2 * value - c.a2 * output)
                            value = output
                        }
                        data[frame] = Float(value * gain)
                    }
                }
            }
        }
    }
}

private final class SoundEQRenderStorage: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?
    let processor = SoundEqualizerProcessor()
    var samples: SoundSpectrumSampleStore?
}

final class SoundEqualizerAudioUnit: AUAudioUnit, @unchecked Sendable {
    static let component = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                     componentSubType: 0x7574_6571, componentManufacturer: 0x5574_6174,
                                                     componentFlags: 0, componentFlagsMask: 0)
    private static let registered: Void = {
        AUAudioUnit.registerSubclass(SoundEqualizerAudioUnit.self, as: component, name: "Utatane: Sound EQ", version: 1)
    }()

    static func register() {
        _ = registered
    }

    private let storage = SoundEQRenderStorage()
    var processor: SoundEqualizerProcessor {
        storage.processor
    }

    var samples: SoundSpectrumSampleStore? {
        get { storage.samples } set { storage.samples = newValue }
    }

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format); outputBus = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray {
        inputs
    }

    override var outputBusses: AUAudioUnitBusArray {
        outputs
    }

    override func allocateRenderResources() throws {
        let format = inputBus.format
        guard format == outputBus.format, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender) else { throw CocoaError(.coderInvalidValue) }
        storage.buffer = buffer
        processor.configure(sampleRate: format.sampleRate, channels: Int(format.channelCount))
        try super.allocateRenderResources()
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources(); storage.buffer = nil
    }

    override func reset() {
        processor.requestReset()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let storage = storage
        return { flags, timestamp, frameCount, _, output, _, pull in
            guard let pull, let buffer = storage.buffer, frameCount <= buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
            let token = storage.samples?.captureToken()
            buffer.frameLength = frameCount
            let input = buffer.mutableAudioBufferList
            let status = pull(flags, timestamp, frameCount, 0, input)
            guard status == noErr else { return status }
            let source = UnsafeMutableAudioBufferListPointer(input)
            let destination = UnsafeMutableAudioBufferListPointer(output)
            guard source.count == destination.count else { return kAudioUnitErr_FormatNotSupported }
            for channel in destination.indices {
                if let data = destination[channel].mData {
                    memcpy(data, source[channel].mData!, Int(frameCount) * MemoryLayout<Float>.stride)
                } else {
                    destination[channel].mData = source[channel].mData
                }
                destination[channel].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.stride)
            }
            storage.processor.process(destination, frames: Int(frameCount))
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            if let token {
                storage.samples?.append(destination, frames: Int(frameCount), token: token)
            }
            return noErr
        }
    }
}

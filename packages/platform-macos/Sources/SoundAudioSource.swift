import AVFoundation
import Foundation

/// File decoding/scheduling is owned by AVAudioPlayerNode. EQ/volume are applied
/// once in the custom effect; capture precedes pan and the test-only output mute.
@MainActor
final class SoundAudioSource {
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    private let speed = AVAudioUnitTimePitch()
    private let effect: AVAudioUnitEffect
    private let balance = AVAudioMixerNode()
    private let file: AVAudioFile
    let spectrumSamples: SoundSpectrumSampleStore
    private var token = UUID()
    private var scheduled = false
    private var startingFrame: AVAudioFramePosition = 0
    private var parkedTime = 0.0
    private(set) var isPlaying = false
    var onFinished: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var settings = SoundEqualizerSettings() {
        didSet {
            if settings != oldValue, !isUpdatingProcessing {
                updateProcessing()
            }
        }
    }

    var capturesSpectrum = false {
        didSet { spectrumSamples.setEnabled(capturesSpectrum && isPlaying) }
    }

    var volume: Float = 1 {
        didSet {
            if volume != oldValue, !isUpdatingProcessing {
                updateProcessing()
            }
        }
    }

    var isMuted = false {
        didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : 1 }
    }

    var pan: Float {
        get { balance.pan } set { balance.pan = newValue }
    }

    var enableRate = false {
        didSet { speed.bypass = !enableRate || rate == 1 }
    }

    var rate: Float = 1 {
        didSet { speed.rate = rate; speed.bypass = !enableRate || rate == 1 }
    }

    var duration: Double {
        Double(file.length) / file.processingFormat.sampleRate
    }

    var numberOfChannels: Int {
        Int(file.processingFormat.channelCount)
    }

    var currentTime: Double {
        get {
            guard scheduled, isPlaying, let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) else { return parkedTime }
            return min(duration, max(0, Double(startingFrame) / file.processingFormat.sampleRate + Double(max(0, time.sampleTime)) / time.sampleRate))
        }
        set {
            let playing = isPlaying
            token = UUID(); node.stop(); scheduled = false
            parkedTime = min(duration, max(0, newValue))
            spectrumSamples.invalidate()
            equalizer.processor.requestReset()
            schedule()
            if playing {
                node.play()
                finishIfAtEnd()
            }
        }
    }

    private var isUpdatingProcessing = false
    private var coefficientSettings: SoundEqualizerSettings?
    private var cachedCoefficients = Array(repeating: SoundEQBiquad.identity, count: 31)

    private var equalizer: SoundEqualizerAudioUnit {
        effect.auAudioUnit as! SoundEqualizerAudioUnit
    }

    init(contentsOf url: URL, manualRendering: Bool = false) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let format = file.processingFormat
        spectrumSamples = SoundSpectrumSampleStore(sampleRate: format.sampleRate, channels: Int(format.channelCount))
        SoundEqualizerAudioUnit.register()
        effect = AVAudioUnitEffect(audioComponentDescription: SoundEqualizerAudioUnit.component)
        engine.attach(node); engine.attach(speed); engine.attach(effect); engine.attach(balance)
        engine.connect(node, to: speed, format: format)
        engine.connect(speed, to: effect, format: format)
        engine.connect(effect, to: balance, format: format)
        engine.connect(balance, to: engine.mainMixerNode, format: format)
        equalizer.samples = spectrumSamples
        speed.bypass = true
        if manualRendering {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        }
        engine.prepare()
        updateProcessing()
    }

    func prepareToPlay() {
        if !scheduled {
            schedule()
        }
    }

    @discardableResult func play() -> Bool {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            prepareToPlay()
            node.play(); isPlaying = true
            spectrumSamples.setEnabled(capturesSpectrum)
            finishIfAtEnd()
            return true
        } catch { onFailure?(error); return false }
    }

    func pause() {
        parkedTime = currentTime
        node.pause(); engine.pause(); isPlaying = false
        spectrumSamples.setEnabled(false)
    }

    func stop() {
        token = UUID(); parkedTime = currentTime; node.stop()
        isPlaying = false; scheduled = false
        spectrumSamples.setEnabled(false)
        engine.stop()
    }

    func applyProcessing(_ settings: SoundEqualizerSettings, volume: Float) {
        isUpdatingProcessing = true
        self.settings = settings; self.volume = volume
        isUpdatingProcessing = false
        updateProcessing()
    }

    private func updateProcessing() {
        if coefficientSettings != settings {
            cachedCoefficients = settings.coefficients(sampleRate: file.processingFormat.sampleRate)
            coefficientSettings = settings
        }
        equalizer.processor.set(coefficients: cachedCoefficients,
                                gain: Double(volume) * pow(10, settings.preamp / 20))
    }

    private func schedule() {
        guard !scheduled else { return }
        let generation = UUID(); token = generation
        startingFrame = min(file.length, AVAudioFramePosition(parkedTime * file.processingFormat.sampleRate))
        let count = min(file.length - startingFrame, AVAudioFramePosition(UInt32.max))
        guard count > 0 else { scheduled = true; return }
        let endFrame = startingFrame + count
        node.scheduleSegment(file, startingFrame: startingFrame, frameCount: AVAudioFrameCount(count), at: nil,
                             completionCallbackType: .dataPlayedBack)
        { [weak self] _ in
            Task { @MainActor [weak self] in self?.completed(generation: generation, endFrame: endFrame) }
        }
        scheduled = true
    }

    private func finishIfAtEnd() {
        guard startingFrame >= file.length else { return }
        let generation = token, end = file.length
        Task { [weak self] in self?.completed(generation: generation, endFrame: end) }
    }

    private func completed(generation: UUID, endFrame: AVAudioFramePosition) {
        guard token == generation else { return }
        parkedTime = Double(endFrame) / file.processingFormat.sampleRate
        if endFrame < file.length {
            let playing = isPlaying
            node.stop(); scheduled = false; schedule()
            if playing {
                node.play()
            }
        } else {
            token = UUID()
            isPlaying = false
            spectrumSamples.setEnabled(false)
            onFinished?()
        }
    }
}

import AVFoundation
import Foundation
import UtataneSakuraScript

@MainActor
final class SakuraScriptSoundPlayer: NSObject, AVAudioPlayerDelegate {
    enum CompletionAction: Equatable {
        case loop
        case stop
        case error
    }

    var onSpectrum: (([Int: String]) async -> Void)?
    var onStop: ((String, String) -> Void)?
    var onLoop: ((String) -> Void)?
    var onError: ((String, Error) -> Void)?
    var resourceBaseDirectory: URL?
    var isMuted = false {
        didSet { audioPlayer?.volume = isMuted ? 0 : requestedVolume }
    }

    var outputVolume: Float? {
        audioPlayer?.volume
    }

    private var audioPlayer: AVAudioPlayer?
    private var loadedFile: String?
    private var loadedURL: URL?
    private var requestedVolume: Float = 1
    private var hasStartedPlayback = false
    private var isPaused = false
    private var identifier = 0
    private static var nextIdentifier = 0
    private var isLooping = false
    private var isSuspended = false
    private var resumesAfterSuspension = false
    private var pendingCompletion: Bool?

    private var spectrumInterval = 0
    private var spectrumBands = 10
    private var spectrumHold = 500
    private var spectrumTask: Task<Void, Never>?
    private var spectrumGeneration = UUID()
    private var spectrumAnalyzer: SoundSpectrumAnalyzer?
    private var spectrumEnvelope = SoundSpectrumEnvelope()
    private var lastSpectrumPosition = 0

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            resumesAfterSuspension = audioPlayer?.isPlaying == true
            audioPlayer?.pause()
        } else if let completion = pendingCompletion {
            pendingCompletion = nil
            resumesAfterSuspension = false
            handlePlaybackFinished(successfully: completion)
        } else {
            if resumesAfterSuspension {
                audioPlayer?.play()
            }
            resumesAfterSuspension = false
        }
    }

    func discard() {
        spectrumTask?.cancel()
        spectrumTask = nil
        spectrumGeneration = UUID()
        spectrumAnalyzer = nil
        spectrumEnvelope = .init()
        spectrumInterval = 0
        spectrumBands = 10
        spectrumHold = 500
        lastSpectrumPosition = 0
        audioPlayer?.stop()
        audioPlayer = nil
        loadedFile = nil
        loadedURL = nil
        hasStartedPlayback = false
        isPaused = false
        isLooping = false
        resumesAfterSuspension = false
        pendingCompletion = nil
    }

    func execute(_ command: SakuraScriptSoundCommand) async throws {
        switch command {
        case let .play(file, loop, options):
            let player: AVAudioPlayer
            if loadedFile == file, let audioPlayer {
                player = audioPlayer
            } else {
                guard let url = resolvedURL(for: file) else {
                    onError?(file, CocoaError(.fileNoSuchFile))
                    return
                }
                do {
                    player = try AVAudioPlayer(contentsOf: url)
                } catch {
                    onError?(file, error)
                    throw error
                }
                discard()
                audioPlayer = player
                loadedFile = file
                loadedURL = url
                Self.nextIdentifier += 1
                identifier = Self.nextIdentifier
                requestedVolume = 1
            }
            player.delegate = self
            player.numberOfLoops = 0
            apply(options: options, to: player)
            player.prepareToPlay()
            player.play()
            hasStartedPlayback = true
            isPaused = false
            isLooping = loop
            updateSpectrumTimer()
        case let .load(file, options):
            guard let url = resolvedURL(for: file) else {
                onError?(file, CocoaError(.fileNoSuchFile))
                return
            }
            let player: AVAudioPlayer
            do {
                player = try AVAudioPlayer(contentsOf: url)
            } catch {
                onError?(file, error)
                throw error
            }
            player.delegate = self
            discard()
            requestedVolume = 1
            apply(options: options, to: player)
            player.prepareToPlay()
            audioPlayer = player
            loadedFile = file
            loadedURL = url
            Self.nextIdentifier += 1
            identifier = Self.nextIdentifier
            hasStartedPlayback = false
            isPaused = false
            isLooping = false
        case let .option(file, options):
            guard file == nil || file == loadedFile, let audioPlayer else { return }
            let wasEnabled = spectrumInterval > 0
            apply(options: options, to: audioPlayer)
            if wasEnabled, spectrumInterval == 0 {
                await emitSpectrumZero()
            }
            updateSpectrumTimer()
        case .wait:
            while !isLooping, audioPlayer?.isPlaying == true {
                try await Task.sleep(for: .milliseconds(50))
            }
        case .pause:
            audioPlayer?.pause()
            spectrumTask?.cancel()
            spectrumTask = nil
            isPaused = hasStartedPlayback
        case .resume:
            audioPlayer?.play()
            hasStartedPlayback = audioPlayer != nil
            isPaused = false
            updateSpectrumTimer()
        case .stop:
            await emitSpectrumZero()
            discard()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedIdentifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard self?.audioPlayer.map(ObjectIdentifier.init) == finishedIdentifier else { return }
            self?.handlePlaybackFinished(successfully: flag)
        }
    }

    func handlePlaybackFinished(successfully flag: Bool) {
        guard let loadedFile else { return }
        if isSuspended {
            pendingCompletion = flag
            return
        }
        switch Self.completionAction(isLooping: isLooping, successfully: flag) {
        case .loop:
            guard let audioPlayer else { return }
            onLoop?(loadedFile)
            audioPlayer.currentTime = 0
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            return
        case .stop:
            if spectrumInterval > 0 {
                spectrumTask?.cancel()
                let generation = spectrumGeneration
                Task { [weak self] in
                    guard let self else { return }
                    await emitSpectrumZero()
                    guard generation == spectrumGeneration else { return }
                    discard()
                    onStop?(loadedFile, "end")
                }
            } else {
                discard()
                onStop?(loadedFile, "end")
            }
        case .error:
            discard()
            onError?(loadedFile, CocoaError(.fileReadCorruptFile))
        }
    }

    static func completionAction(isLooping: Bool, successfully: Bool) -> CompletionAction {
        guard successfully else { return .error }
        return isLooping ? .loop : .stop
    }

    private func apply(options: [String], to player: AVAudioPlayer) {
        for option in options {
            let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "--spectrum":
                if let value = Int(parts[1]) {
                    spectrumInterval = value == 0 ? 0 : min(1000, max(20, value))
                }
            case "--spectrum-bands":
                if let value = Int(parts[1]) {
                    spectrumBands = [0, 5, 10, 15, 31].min(by: { abs(Double($0) - Double(value)) < abs(Double($1) - Double(value)) }) ?? 10
                }
            case "--spectrum-hold":
                if let value = Int(parts[1]) {
                    spectrumHold = min(10000, max(0, value))
                }
            case "--volume":
                if let value = Float(parts[1]) {
                    requestedVolume = min(1, max(0, value / 100))
                }
            case "--balance":
                if let value = Float(parts[1]) {
                    player.pan = min(1, max(-1, value / 100))
                }
            case "--rate":
                if let value = Float(parts[1]) {
                    player.enableRate = true
                    player.rate = min(2, max(0.5, value / 100))
                }
            case "--seektime":
                if let seconds = seekTime(parts[1], duration: player.duration, currentTime: player.currentTime) {
                    player.currentTime = seconds
                }
            default:
                continue
            }
        }
        player.volume = isMuted ? 0 : requestedVolume
    }

    private func updateSpectrumTimer() {
        spectrumTask?.cancel()
        spectrumTask = nil
        spectrumGeneration = UUID()
        guard spectrumInterval > 0, hasStartedPlayback, !isPaused, let loadedURL else { return }
        if spectrumAnalyzer == nil {
            spectrumAnalyzer = try? SoundSpectrumAnalyzer(url: loadedURL)
        }
        let generation = spectrumGeneration
        let interval = Duration.milliseconds(spectrumInterval)
        spectrumTask = Task { [weak self] in
            var deadline = ContinuousClock.now + interval
            while !Task.isCancelled {
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                guard let self, generation == spectrumGeneration else { return }
                if !isSuspended, audioPlayer?.isPlaying == true {
                    await emitSpectrum()
                }
                deadline += interval
                // Do not accumulate requests if a SHIORI is slower than its requested cadence.
                if deadline < .now {
                    deadline = .now + interval
                }
            }
        }
    }

    private func emitSpectrum() async {
        guard let audioPlayer, let loadedFile else { return }
        let channels = spectrumAnalyzer?.channelCount ?? max(1, min(8, audioPlayer.numberOfChannels))
        let values = (try? spectrumAnalyzer?.levels(at: audioPlayer.currentTime, bands: spectrumBands))
            ?? [Double](repeating: 0, count: channels + spectrumBands)
        let result = spectrumEnvelope.update(values, at: ProcessInfo.processInfo.systemUptime, hold: Double(spectrumHold) / 1000)
        lastSpectrumPosition = Int(audioPlayer.currentTime * 1000)
        await onSpectrum?(spectrumReferences(file: loadedFile, channels: channels, levels: result.levels, peaks: result.peaks))
    }

    private func emitSpectrumZero() async {
        guard spectrumInterval > 0 || spectrumTask != nil, let loadedFile else { return }
        let channels = spectrumAnalyzer?.channelCount ?? max(1, min(8, audioPlayer?.numberOfChannels ?? 1))
        let zeros = [Int](repeating: 0, count: channels + spectrumBands)
        await onSpectrum?(spectrumReferences(file: loadedFile, channels: channels, levels: zeros, peaks: zeros))
        spectrumEnvelope = .init()
    }

    private func spectrumReferences(file: String, channels: Int, levels: [Int], peaks: [Int]) -> [Int: String] {
        func joined(_ values: ArraySlice<Int>) -> String {
            values.map(String.init).joined(separator: "\u{1}")
        }
        return [0: file, 1: String(spectrumBands), 2: joined(levels.prefix(channels)), 3: joined(peaks.prefix(channels)),
                4: joined(levels.dropFirst(channels)), 5: joined(peaks.dropFirst(channels)), 6: String(lastSpectrumPosition)]
    }

    func propertyValue(for property: String) -> String? {
        let key = property.lowercased()
        if key == "currentghost.sound.count" {
            return audioPlayer == nil ? "0" : "1"
        }
        let field: String
        if key.hasPrefix("currentghost.sound.index(0).") {
            field = String(key.dropFirst("currentghost.sound.index(0).".count))
        } else if key.hasPrefix("currentghost.sound("),
                  let end = property.range(of: ").", options: .backwards),
                  String(property[property.index(property.startIndex, offsetBy: "currentghost.sound(".count) ..< end.lowerBound]) == loadedFile
        {
            field = String(property[end.upperBound...]).lowercased()
        } else {
            return nil
        }
        guard let player = audioPlayer else { return nil }
        switch field {
        case "name": return loadedFile
        case "path": return loadedURL?.path
        case "id": return String(identifier)
        case "position": return String(Int(player.currentTime * 1000))
        case "duration": return String(Int(player.duration * 1000))
        case "playing": return hasStartedPlayback ? "1" : "0"
        case "pause": return isPaused ? "1" : "0"
        case "loop": return isLooping ? "1" : "0"
        case "preload": return hasStartedPlayback ? "0" : "1"
        case "error": return ""
        default: return nil
        }
    }

    private func seekTime(_ source: String, duration: TimeInterval, currentTime: TimeInterval) -> TimeInterval? {
        let isRelative = source.hasPrefix("@")
        let value = isRelative ? String(source.dropFirst()) : source
        let seconds: TimeInterval?
        if value.contains(":") {
            let components = value.split(separator: ":").compactMap { Double($0) }
            guard !components.isEmpty, components.count <= 3 else { return nil }
            seconds = components.reversed().enumerated().reduce(0) { result, item in
                result + item.element * pow(60, Double(item.offset))
            }
        } else if let milliseconds = Double(value) {
            seconds = milliseconds / 1000
        } else {
            seconds = nil
        }
        guard let seconds else { return nil }
        return min(duration, max(0, (isRelative ? currentTime : 0) + seconds))
    }

    private func resolvedURL(for path: String) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let candidate: URL
        if normalized.hasPrefix("/") {
            // Music-player ghosts retain absolute paths from selection/drop events.
            candidate = URL(filePath: normalized).standardizedFileURL
        } else {
            guard let base = resourceBaseDirectory?.standardizedFileURL else { return nil }
            candidate = base.appending(path: normalized, directoryHint: .notDirectory).standardizedFileURL
            let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
            guard candidate.path.hasPrefix(basePath) else { return nil }
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
}

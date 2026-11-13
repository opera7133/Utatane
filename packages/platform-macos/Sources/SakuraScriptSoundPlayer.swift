import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UtataneSakuraScript

@MainActor
final class SakuraScriptSoundPlayer: NSObject {
    enum CompletionAction: Equatable {
        case loop
        case stop
        case error
    }

    var isScriptBusy: (() -> Bool)?
    var onSpectrumEnd: (() -> Void)?
    var onSpectrum: (([Int: String]) async -> Void)?
    var onStop: ((String, String) -> Void)?
    var onLoop: ((String) -> Void)?
    var onError: ((String, Error) -> Void)?
    var resourceBaseDirectory: URL?
    var isMuted = false {
        didSet { audioPlayer?.isMuted = isMuted }
    }

    var outputVolume: Float? {
        audioPlayer.map { isMuted ? 0 : $0.volume }
    }

    private var audioPlayer: SoundAudioSource?
    private var loadedFile: String?
    private var loadedURL: URL?
    private var metadata: EmbeddedAudioMetadata?
    private var artworkDirectory: URL?
    private var artworkURL: URL?
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
    private var spectrumSkipBusy = false
    private var spectrumTask: Task<Void, Never>?
    private var spectrumCompletionTask: Task<Void, Never>?
    private var spectrumGeneration = UUID()
    private let makeSpectrumWorker: (@Sendable () -> any SoundSpectrumAnalyzing)?
    private var spectrumWorker: (any SoundSpectrumAnalyzing)?

    init(makeSpectrumWorker: (@Sendable () -> any SoundSpectrumAnalyzing)? = nil) {
        self.makeSpectrumWorker = makeSpectrumWorker
        super.init()
    }

    deinit {
        if let artworkDirectory {
            try? FileManager.default.removeItem(at: artworkDirectory)
        }
    }

    private var spectrumEnvelope = SoundSpectrumEnvelope()
    private var lastSpectrumPosition = 0

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            resumesAfterSuspension = audioPlayer?.isPlaying == true
            audioPlayer?.pause()
            spectrumTask?.cancel()
            spectrumTask = nil
            spectrumGeneration = UUID()
        } else if let completion = pendingCompletion {
            pendingCompletion = nil
            resumesAfterSuspension = false
            handlePlaybackFinished(successfully: completion)
        } else {
            if resumesAfterSuspension {
                audioPlayer?.play()
            }
            resumesAfterSuspension = false
            updateSpectrumTimer()
        }
    }

    func discard() {
        let wasAnalyzing = spectrumInterval > 0 || spectrumTask != nil
        spectrumTask?.cancel()
        spectrumTask = nil
        spectrumCompletionTask?.cancel()
        spectrumCompletionTask = nil
        spectrumGeneration = UUID()
        spectrumWorker = nil
        spectrumEnvelope = .init()
        spectrumInterval = 0
        spectrumBands = 10
        spectrumHold = 500
        spectrumSkipBusy = false
        lastSpectrumPosition = 0
        audioPlayer?.stop()
        audioPlayer = nil
        loadedFile = nil
        loadedURL = nil
        metadata = nil
        artworkURL = nil
        if let artworkDirectory {
            try? FileManager.default.removeItem(at: artworkDirectory)
        }
        artworkDirectory = nil
        hasStartedPlayback = false
        isPaused = false
        isLooping = false
        resumesAfterSuspension = false
        pendingCompletion = nil
        if wasAnalyzing {
            onSpectrumEnd?()
        }
    }

    func execute(_ command: SakuraScriptSoundCommand, resourceDirectory: URL? = nil) async throws {
        switch command {
        case let .play(file, loop, options):
            guard let url = resolvedURL(for: file, resourceDirectory: resourceDirectory) else {
                onError?(file, CocoaError(.fileNoSuchFile))
                return
            }
            let player: SoundAudioSource
            if loadedURL == url, let audioPlayer {
                player = audioPlayer
            } else {
                do {
                    player = try SoundAudioSource(contentsOf: url)
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
            loadedFile = file
            configureCallbacks(player)
            apply(options: options, to: player)
            player.prepareToPlay()
            guard player.play() else { return }
            hasStartedPlayback = true
            isPaused = false
            isLooping = loop
            updateSpectrumTimer()
            await loadMetadata(url)
        case let .load(file, options):
            guard let url = resolvedURL(for: file, resourceDirectory: resourceDirectory) else {
                onError?(file, CocoaError(.fileNoSuchFile))
                return
            }
            let player: SoundAudioSource
            do {
                player = try SoundAudioSource(contentsOf: url)
            } catch {
                onError?(file, error)
                throw error
            }
            configureCallbacks(player)
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
            await loadMetadata(url)
        case let .option(file, options):
            guard file == nil || file == loadedFile, let audioPlayer else { return }
            let wasEnabled = spectrumInterval > 0
            let zero = spectrumZeroReferences()
            apply(options: options, to: audioPlayer)
            updateSpectrumTimer()
            if wasEnabled, spectrumInterval == 0 {
                spectrumEnvelope = .init()
                onSpectrumEnd?()
                if let zero {
                    await onSpectrum?(zero)
                }
            }
        case .wait:
            while !isLooping, audioPlayer?.isPlaying == true {
                try await Task.sleep(for: .milliseconds(50))
            }
        case .pause:
            audioPlayer?.pause()
            spectrumTask?.cancel()
            spectrumTask = nil
            spectrumGeneration = UUID()
            isPaused = hasStartedPlayback
        case .resume:
            guard audioPlayer?.play() == true else { return }
            hasStartedPlayback = audioPlayer != nil
            isPaused = false
            updateSpectrumTimer()
        case .stop:
            let zero = spectrumZeroReferences()
            // Stop the audio and invalidate its old visual work before awaiting SHIORI.
            discard()
            if let zero {
                await onSpectrum?(zero)
            }
        }
    }

    private func configureCallbacks(_ player: SoundAudioSource) {
        player.isMuted = isMuted
        player.onFinished = { [weak self, weak player] in
            guard let self, let player, audioPlayer === player else { return }
            handlePlaybackFinished(successfully: true)
        }
        player.onFailure = { [weak self, weak player] error in
            guard let self, let player, audioPlayer === player, let loadedFile else { return }
            discard()
            onError?(loadedFile, error)
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
            updateSpectrumTimer()
            return
        case .stop, .error:
            let zero = spectrumZeroReferences()
            let successfully = flag
            discard()
            let generation = spectrumGeneration
            if let zero {
                spectrumCompletionTask = Task { [weak self] in
                    guard let self else { return }
                    await onSpectrum?(zero)
                    guard generation == spectrumGeneration else { return }
                    if successfully {
                        onStop?(loadedFile, "end")
                    } else {
                        onError?(loadedFile, CocoaError(.fileReadCorruptFile))
                    }
                }
            } else if successfully {
                onStop?(loadedFile, "end")
            } else {
                onError?(loadedFile, CocoaError(.fileReadCorruptFile))
            }
        }
    }

    static func completionAction(isLooping: Bool, successfully: Bool) -> CompletionAction {
        guard successfully else { return .error }
        return isLooping ? .loop : .stop
    }

    private func apply(options: [String], to player: SoundAudioSource) {
        var equalizer = player.settings
        for option in options {
            equalizer.apply(option)
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
            case "--spectrum-skipbusy":
                switch parts[1].lowercased() {
                case "true", "on", "1": spectrumSkipBusy = true
                case "false", "off", "0": spectrumSkipBusy = false
                default: break
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
        player.applyProcessing(equalizer, volume: requestedVolume)
        player.isMuted = isMuted
    }

    private func updateSpectrumTimer() {
        spectrumTask?.cancel()
        spectrumTask = nil
        spectrumGeneration = UUID()
        audioPlayer?.capturesSpectrum = spectrumInterval > 0
        guard spectrumInterval > 0, hasStartedPlayback, !isPaused, !isSuspended, loadedURL != nil else { return }
        if spectrumWorker == nil {
            if let makeSpectrumWorker {
                spectrumWorker = makeSpectrumWorker()
            } else if let audioPlayer {
                spectrumWorker = SoundSpectrumWorker(samples: audioPlayer.spectrumSamples)
            }
        }
        let generation = spectrumGeneration
        let interval = Duration.milliseconds(spectrumInterval)
        spectrumTask = Task { [weak self] in
            var deadline = ContinuousClock.now + interval
            while !Task.isCancelled {
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                guard let self, generation == spectrumGeneration else { return }
                if !isSuspended, audioPlayer?.isPlaying == true {
                    await emitSpectrum(generation: generation)
                }
                deadline += interval
                // Do not accumulate requests if a SHIORI is slower than its requested cadence.
                if deadline < .now {
                    deadline = .now + interval
                }
            }
        }
    }

    private func emitSpectrum(generation: UUID) async {
        guard !spectrumSkipBusy || isScriptBusy?() != true else { return }
        guard let audioPlayer, let loadedFile, let loadedURL, let spectrumWorker else { return }
        let position = audioPlayer.currentTime
        let bands = spectrumBands
        let frame = try? await spectrumWorker.analyze(url: loadedURL, position: position, bands: bands)
        // An actor hop can overlap pause, seek, reload, stop or a new sound.
        guard !Task.isCancelled, generation == spectrumGeneration,
              self.audioPlayer === audioPlayer, !isPaused, !isSuspended, audioPlayer.isPlaying else { return }
        guard !spectrumSkipBusy || isScriptBusy?() != true else { return }
        let channels = frame?.channels ?? max(1, min(8, audioPlayer.numberOfChannels))
        let values = frame?.levels ?? [Double](repeating: 0, count: channels + bands)
        let result = spectrumEnvelope.update(values, at: ProcessInfo.processInfo.systemUptime, hold: Double(spectrumHold) / 1000)
        lastSpectrumPosition = Int(position * 1000)
        await onSpectrum?(spectrumReferences(file: loadedFile, channels: channels, levels: result.levels, peaks: result.peaks))
    }

    private func spectrumZeroReferences() -> [Int: String]? {
        guard spectrumInterval > 0 || spectrumTask != nil, let loadedFile else { return nil }
        let channels = max(1, min(8, audioPlayer?.numberOfChannels ?? 1))
        let zeros = [Int](repeating: 0, count: channels + spectrumBands)
        return spectrumReferences(file: loadedFile, channels: channels, levels: zeros, peaks: zeros)
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
        case "meta.artwork": return artworkPath()
        case _ where field.hasPrefix("meta."): return metadata?.tags[String(field.dropFirst(5))]
        default: return nil
        }
    }

    private func loadMetadata(_ url: URL) async {
        guard metadata == nil else { return }
        let loadingID = identifier
        let result = await MacOSMediaInfoReader.soundMetadata(url)
        guard identifier == loadingID, loadedURL == url else { return }
        metadata = result
    }

    private func artworkPath() -> String? {
        if let artworkURL {
            return artworkURL.path
        }
        guard let bytes = metadata?.artwork,
              let image = CGImageSourceCreateWithData(bytes as CFData, nil),
              let identifier = CGImageSourceGetType(image), let type = UTType(identifier as String),
              let suffix = type.preferredFilenameExtension,
              CGImageSourceCopyPropertiesAtIndex(image, 0, nil) != nil
        else { return nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-artwork-\(UUID())", directoryHint: .isDirectory)
        let url = directory.appending(path: "cover").appendingPathExtension(suffix)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try bytes.write(to: url, options: .atomic)
            artworkDirectory = directory
            artworkURL = url
            return url.path
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
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

    private func resolvedURL(for path: String, resourceDirectory: URL?) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let candidate: URL
        if normalized.hasPrefix("/") {
            // Music-player ghosts retain absolute paths from selection/drop events.
            candidate = URL(filePath: normalized).standardizedFileURL
        } else {
            guard let base = (resourceDirectory ?? resourceBaseDirectory)?.standardizedFileURL.resolvingSymlinksInPath() else { return nil }
            candidate = base.appending(path: normalized, directoryHint: .notDirectory).standardizedFileURL.resolvingSymlinksInPath()
            let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
            guard candidate.path.hasPrefix(basePath) else { return nil }
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
}

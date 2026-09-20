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

    var onStop: ((String, String) -> Void)?
    var onLoop: ((String) -> Void)?
    var onError: ((String, Error) -> Void)?
    var resourceBaseDirectory: URL?
    private var audioPlayer: AVAudioPlayer?
    private var loadedFile: String?
    private var isLooping = false

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
                audioPlayer = player
                loadedFile = file
            }
            player.delegate = self
            player.numberOfLoops = 0
            apply(options: options, to: player)
            player.prepareToPlay()
            player.play()
            isLooping = loop
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
            apply(options: options, to: player)
            player.prepareToPlay()
            audioPlayer = player
            loadedFile = file
            isLooping = false
        case let .option(file, options):
            guard file == nil || file == loadedFile, let audioPlayer else { return }
            apply(options: options, to: audioPlayer)
        case .wait:
            while !isLooping, audioPlayer?.isPlaying == true {
                try await Task.sleep(for: .milliseconds(50))
            }
        case .pause:
            audioPlayer?.pause()
        case .resume:
            audioPlayer?.play()
        case .stop:
            let stoppedFile = loadedFile
            audioPlayer?.stop()
            audioPlayer = nil
            loadedFile = nil
            isLooping = false
            if let stoppedFile {
                onStop?(stoppedFile, "close")
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.handlePlaybackFinished(successfully: flag)
        }
    }

    func handlePlaybackFinished(successfully flag: Bool) {
        guard let loadedFile else { return }
        switch Self.completionAction(isLooping: isLooping, successfully: flag) {
        case .loop:
            guard let audioPlayer else { return }
            onLoop?(loadedFile)
            audioPlayer.currentTime = 0
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            return
        case .stop:
            onStop?(loadedFile, "end")
        case .error:
            onError?(loadedFile, CocoaError(.fileReadCorruptFile))
        }
        audioPlayer = nil
        self.loadedFile = nil
        isLooping = false
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
            case "--volume":
                if let value = Float(parts[1]) {
                    player.volume = min(1, max(0, value / 100))
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
        guard let base = resourceBaseDirectory?.standardizedFileURL else { return nil }
        let candidate = base.appending(path: path, directoryHint: .notDirectory).standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path.hasPrefix(basePath), FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }
}

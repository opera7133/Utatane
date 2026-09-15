import AVFoundation
import Foundation
import Speech

public enum SpeechSynthesisProvider: String, Codable, CaseIterable, Sendable {
    case macOS
    case voicevoxCompatible
    case coeiroink
    case voicepeak
    case voisonaTalk
    case openAI
    case openAICompatibleLocal
    case elevenLabs
    case aivisCloud
    case azureSpeech
    case googleCloudTTS
}

public struct SpeechSynthesisVoice: Identifiable, Sendable, Equatable {
    public let identifier: String
    public let groupIdentifier: String?
    public let languageIdentifier: String?
    public let name: String
    public let language: String

    public var id: String {
        [groupIdentifier, identifier, languageIdentifier].compactMap(\.self).joined(separator: ":")
    }

    public init(
        identifier: String,
        groupIdentifier: String? = nil,
        languageIdentifier: String? = nil,
        name: String,
        language: String
    ) {
        self.identifier = identifier
        self.groupIdentifier = groupIdentifier
        self.languageIdentifier = languageIdentifier
        self.name = name
        self.language = language
    }
}

public struct SpeechSynthesisConfiguration: Sendable, Equatable {
    public var provider: SpeechSynthesisProvider
    public var voiceIdentifier: String?
    public var voiceGroupIdentifier: String?
    public var voiceLanguageIdentifier: String?
    public var serviceURL: URL?
    public var modelIdentifier: String?
    public var styleIdentifier: String?
    public var instructions: String?
    public var rate: Float
    public var volume: Float
    public var pitchMultiplier: Float

    public init(
        provider: SpeechSynthesisProvider = .macOS,
        voiceIdentifier: String? = nil,
        voiceGroupIdentifier: String? = nil,
        voiceLanguageIdentifier: String? = nil,
        serviceURL: URL? = nil,
        modelIdentifier: String? = nil,
        styleIdentifier: String? = nil,
        instructions: String? = nil,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        volume: Float = 1,
        pitchMultiplier: Float = 1
    ) {
        self.provider = provider
        self.voiceIdentifier = voiceIdentifier
        self.voiceGroupIdentifier = voiceGroupIdentifier
        self.voiceLanguageIdentifier = voiceLanguageIdentifier
        self.serviceURL = serviceURL
        self.modelIdentifier = modelIdentifier
        self.styleIdentifier = styleIdentifier
        self.instructions = instructions
        self.rate = rate
        self.volume = volume
        self.pitchMultiplier = pitchMultiplier
    }
}

public struct SpeechSynthesisRequest: Sendable, Equatable {
    public let text: String
    public let scope: Int
    public let configuration: SpeechSynthesisConfiguration

    public init(text: String, scope: Int, configuration: SpeechSynthesisConfiguration) {
        self.text = text
        self.scope = scope
        self.configuration = configuration
    }
}

@MainActor
public protocol SpeechSynthesizing: AnyObject {
    func speak(_ request: SpeechSynthesisRequest) async throws
    func stop()
}

public enum SpeechServiceError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case recognitionPermissionDenied
    case recognitionUnavailable
    case audioInputUnavailable
    case synthesisCancelled
    case invalidServiceURL
    case invalidVoiceIdentifier
    case invalidModelIdentifier
    case serviceCredentialsUnavailable
    case serviceResponse(Int)
    case invalidServiceResponse
    case audioPlaybackFailed
    case externalProcessFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            String(localized: "マイクの使用が許可されていません。")
        case .recognitionPermissionDenied:
            String(localized: "音声認識の使用が許可されていません。")
        case .recognitionUnavailable:
            String(localized: "現在、音声認識を利用できません。")
        case .audioInputUnavailable:
            String(localized: "音声入力を開始できません。")
        case .synthesisCancelled:
            String(localized: "音声合成が中止されました。")
        case .invalidServiceURL:
            String(localized: "音声合成サービスのURLが正しくありません。")
        case .invalidVoiceIdentifier:
            String(localized: "音声合成サービスの話者IDが正しくありません。")
        case .invalidModelIdentifier:
            String(localized: "音声合成サービスのモデル名が正しくありません。")
        case .serviceCredentialsUnavailable:
            String(localized: "音声合成サービスの認証情報が設定されていません。")
        case let .serviceResponse(statusCode):
            String(localized: "音声合成サービスがエラーを返しました（HTTP \(statusCode)）。")
        case .invalidServiceResponse:
            String(localized: "音声合成サービスから正しい応答を取得できませんでした。")
        case .audioPlaybackFailed:
            String(localized: "合成された音声を再生できませんでした。")
        case let .externalProcessFailed(status, message):
            String(localized: "音声合成プロセスが失敗しました（終了コード \(status)）：\(message)")
        }
    }
}

@MainActor
public final class SpeechSynthesisRouter: SpeechSynthesizing {
    private let systemSynthesizer = MacOSSpeechSynthesizer()
    private let voicevoxSynthesizer: VoicevoxSpeechSynthesizer
    private let coeiroinkSynthesizer: CoeiroinkSpeechSynthesizer
    private let voicepeakSynthesizer: VoicepeakSpeechSynthesizer
    private let voisonaTalkSynthesizer: VoiSonaTalkSpeechSynthesizer
    private let openAISynthesizer: OpenAISpeechSynthesizer
    private let elevenLabsSynthesizer: ElevenLabsSpeechSynthesizer
    private let aivisCloudSynthesizer: AivisCloudSpeechSynthesizer
    private let azureSpeechSynthesizer: AzureSpeechSynthesizer
    private let googleCloudSynthesizer: GoogleCloudSpeechSynthesizer

    public init(
        voicevoxClient: VoicevoxEngineClient = VoicevoxEngineClient(),
        coeiroinkClient: CoeiroinkEngineClient = CoeiroinkEngineClient(),
        voicepeakClient: VoicepeakEngineClient = VoicepeakEngineClient(),
        voisonaTalkClient: VoiSonaTalkEngineClient = VoiSonaTalkEngineClient(),
        openAIClient: OpenAISpeechEngineClient = OpenAISpeechEngineClient(),
        elevenLabsClient: ElevenLabsEngineClient = ElevenLabsEngineClient(),
        aivisCloudClient: AivisCloudEngineClient = AivisCloudEngineClient(),
        azureSpeechClient: AzureSpeechEngineClient = AzureSpeechEngineClient(),
        googleCloudClient: GoogleCloudSpeechEngineClient = GoogleCloudSpeechEngineClient()
    ) {
        voicevoxSynthesizer = VoicevoxSpeechSynthesizer(client: voicevoxClient)
        coeiroinkSynthesizer = CoeiroinkSpeechSynthesizer(client: coeiroinkClient)
        voicepeakSynthesizer = VoicepeakSpeechSynthesizer(client: voicepeakClient)
        voisonaTalkSynthesizer = VoiSonaTalkSpeechSynthesizer(client: voisonaTalkClient)
        openAISynthesizer = OpenAISpeechSynthesizer(client: openAIClient)
        elevenLabsSynthesizer = ElevenLabsSpeechSynthesizer(client: elevenLabsClient)
        aivisCloudSynthesizer = AivisCloudSpeechSynthesizer(client: aivisCloudClient)
        azureSpeechSynthesizer = AzureSpeechSynthesizer(client: azureSpeechClient)
        googleCloudSynthesizer = GoogleCloudSpeechSynthesizer(client: googleCloudClient)
    }

    public func speak(_ request: SpeechSynthesisRequest) async throws {
        stop()
        switch request.configuration.provider {
        case .macOS:
            try await systemSynthesizer.speak(request)
        case .voicevoxCompatible:
            try await voicevoxSynthesizer.speak(request)
        case .coeiroink:
            try await coeiroinkSynthesizer.speak(request)
        case .voicepeak:
            try await voicepeakSynthesizer.speak(request)
        case .voisonaTalk:
            try await voisonaTalkSynthesizer.speak(request)
        case .openAI, .openAICompatibleLocal:
            try await openAISynthesizer.speak(request)
        case .elevenLabs:
            try await elevenLabsSynthesizer.speak(request)
        case .aivisCloud:
            try await aivisCloudSynthesizer.speak(request)
        case .azureSpeech:
            try await azureSpeechSynthesizer.speak(request)
        case .googleCloudTTS:
            try await googleCloudSynthesizer.speak(request)
        }
    }

    public func stop() {
        systemSynthesizer.stop()
        voicevoxSynthesizer.stop()
        coeiroinkSynthesizer.stop()
        voicepeakSynthesizer.stop()
        voisonaTalkSynthesizer.stop()
        openAISynthesizer.stop()
        elevenLabsSynthesizer.stop()
        aivisCloudSynthesizer.stop()
        azureSpeechSynthesizer.stop()
        googleCloudSynthesizer.stop()
    }
}

@MainActor
public final class MacOSSpeechSynthesizer: NSObject, SpeechSynthesizing, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    public static let availableVoices: [SpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
        .map { SpeechSynthesisVoice(identifier: $0.identifier, name: $0.name, language: $0.language) }
        .sorted {
            if $0.language == $1.language {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            } else {
                $0.language.localizedStandardCompare($1.language) == .orderedAscending
            }
        }

    public func speak(_ request: SpeechSynthesisRequest) async throws {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        try Task.checkCancellation()

        let utterance = AVSpeechUtterance(string: text)
        if let identifier = request.configuration.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier)
        {
            utterance.voice = voice
        }
        utterance.rate = min(max(request.configuration.rate, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = min(max(request.configuration.volume, 0), 1)
        utterance.pitchMultiplier = min(max(request.configuration.pitchMultiplier, 0.5), 2)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    public func stop() {
        guard continuation != nil || synthesizer.isSpeaking || synthesizer.isPaused else { return }
        _ = synthesizer.stopSpeaking(at: .immediate)
        finish(with: .failure(SpeechServiceError.synthesisCancelled))
    }

    public func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        finish(with: .success(()))
    }

    public func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        finish(with: .failure(SpeechServiceError.synthesisCancelled))
    }

    private func finish(with result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

public struct SpeechRecognitionConfiguration: Sendable, Equatable {
    public var localeIdentifier: String
    public var prefersOnDeviceRecognition: Bool
    public var contextualStrings: [String]

    public init(
        localeIdentifier: String = Locale.current.identifier,
        prefersOnDeviceRecognition: Bool = true,
        contextualStrings: [String] = []
    ) {
        self.localeIdentifier = localeIdentifier
        self.prefersOnDeviceRecognition = prefersOnDeviceRecognition
        self.contextualStrings = contextualStrings
    }
}

@MainActor
public final class MacOSSpeechRecognizer {
    public var onFinalResult: ((String) -> Void)?
    public var onAvailabilityChange: ((Bool) -> Void)?
    public var onError: ((Error) -> Void)?

    public private(set) var isRunning = false
    public private(set) var usesOnDeviceRecognition = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var configuration: SpeechRecognitionConfiguration?
    private var finalizationTask: Task<Void, Never>?
    private var generation = 0
    private var inputSuppressed = false

    public init() {}

    public func start(configuration: SpeechRecognitionConfiguration) async throws {
        stop()
        guard await Self.requestMicrophonePermission() else {
            throw SpeechServiceError.microphonePermissionDenied
        }
        guard await Self.requestRecognitionPermission() else {
            throw SpeechServiceError.recognitionPermissionDenied
        }

        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechServiceError.recognitionUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = configuration.contextualStrings
        let useOnDevice = configuration.prefersOnDeviceRecognition && recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = useOnDevice

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechServiceError.audioInputUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechServiceError.audioInputUnavailable
        }

        self.recognizer = recognizer
        self.request = request
        self.configuration = configuration
        audioEngine = engine
        usesOnDeviceRecognition = useOnDevice
        isRunning = true
        if inputSuppressed {
            engine.pause()
        }
        onAvailabilityChange?(true)
        let generation = generation
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        self.finalizationTask?.cancel()
                        self.finalizationTask = nil
                        await self.deliver(text, andRestartAfter: generation)
                    } else {
                        self.scheduleFinalization(of: text, after: generation)
                    }
                    return
                }
                if let error {
                    self.stop()
                    self.onError?(error)
                }
            }
        }
    }

    public func setInputSuppressed(_ suppressed: Bool) {
        inputSuppressed = suppressed
        guard isRunning, let audioEngine else { return }
        if suppressed {
            audioEngine.pause()
        } else if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    public func stop() {
        generation += 1
        finalizationTask?.cancel()
        finalizationTask = nil
        if let input = audioEngine?.inputNode {
            input.removeTap(onBus: 0)
        }
        audioEngine?.stop()
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recognizer = nil
        audioEngine = nil
        configuration = nil
        usesOnDeviceRecognition = false
        if isRunning {
            isRunning = false
            onAvailabilityChange?(false)
        }
    }

    private func scheduleFinalization(of text: String, after generation: Int) {
        guard !text.isEmpty else { return }
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            finalizationTask = nil
            await deliver(text, andRestartAfter: generation)
        }
    }

    private func deliver(_ text: String, andRestartAfter generation: Int) async {
        guard !text.isEmpty, self.generation == generation else { return }
        onFinalResult?(text)
        await restart(after: generation)
    }

    private func restart(after completedGeneration: Int) async {
        guard generation == completedGeneration, let configuration else { return }
        do {
            try await start(configuration: configuration)
        } catch {
            stop()
            onError?(error)
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private static func requestRecognitionPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}

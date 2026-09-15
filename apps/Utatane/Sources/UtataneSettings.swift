import AppKit
import Sparkle
import SwiftUI
import UtataneAI
import UtataneBalloon
import UtataneNetwork
import UtatanePlatformMacOS
import UtataneRealtime

@MainActor
final class UtataneSettingsStore: ObservableObject {
    struct SpeechVoiceSettings: Codable, Equatable {
        var provider = SpeechSynthesisProvider.macOS
        var voiceIdentifier = ""
        var localAPIBaseURL = "http://127.0.0.1:50021"
        var localAPIVoiceIdentifier = "0"
        var coeiroinkBaseURL = "http://127.0.0.1:50032"
        var coeiroinkSpeakerUUID = ""
        var coeiroinkStyleIdentifier = "0"
        var voicepeakExecutablePath = "/Applications/voicepeak.app/Contents/MacOS/voicepeak"
        var voicepeakNarrator = ""
        var voisonaTalkBaseURL = "http://127.0.0.1:32766/api/talk/v1"
        var voisonaTalkVoiceName = ""
        var voisonaTalkVoiceVersion = ""
        var voisonaTalkLanguage = "ja_JP"
        var openAIModel = "gpt-4o-mini-tts"
        var openAIVoice = "marin"
        var openAIInstructions = ""
        var openAICompatibleLocalBaseURL = "http://127.0.0.1:8088/v1"
        var openAICompatibleLocalModel = "irodori-tts"
        var openAICompatibleLocalVoice = "none"
        var openAICompatibleLocalInstructions = ""
        var elevenLabsModel = "eleven_multilingual_v2"
        var elevenLabsVoiceID = ""
        var aivisCloudModelUUID = ""
        var aivisCloudSpeakerUUID = ""
        var aivisCloudStyleID = ""
        var rate = 0.5
        var volume = 1.0
        var pitch = 1.0

        var synthesisConfiguration: SpeechSynthesisConfiguration {
            SpeechSynthesisConfiguration(
                provider: provider,
                voiceIdentifier: selectedVoiceIdentifier,
                voiceGroupIdentifier: selectedVoiceGroupIdentifier,
                voiceLanguageIdentifier: selectedVoiceLanguageIdentifier,
                serviceURL: selectedServiceURL,
                modelIdentifier: selectedModelIdentifier,
                styleIdentifier: selectedStyleIdentifier,
                instructions: selectedInstructions,
                rate: Float(rate),
                volume: Float(volume),
                pitchMultiplier: Float(pitch)
            )
        }

        private var selectedVoiceIdentifier: String? {
            let identifier = switch provider {
            case .macOS: voiceIdentifier
            case .voicevoxCompatible: localAPIVoiceIdentifier
            case .coeiroink: coeiroinkStyleIdentifier
            case .voicepeak: voicepeakNarrator
            case .voisonaTalk: voisonaTalkVoiceName
            case .openAI: openAIVoice
            case .openAICompatibleLocal: openAICompatibleLocalVoice
            case .elevenLabs: elevenLabsVoiceID
            case .aivisCloud: aivisCloudModelUUID
            }
            return identifier.isEmpty ? nil : identifier
        }

        private var selectedVoiceGroupIdentifier: String? {
            let identifier = switch provider {
            case .coeiroink: coeiroinkSpeakerUUID
            case .voisonaTalk: voisonaTalkVoiceVersion
            case .aivisCloud: aivisCloudSpeakerUUID
            default: ""
            }
            return identifier.isEmpty ? nil : identifier
        }

        private var selectedVoiceLanguageIdentifier: String? {
            guard provider == .voisonaTalk, !voisonaTalkLanguage.isEmpty else { return nil }
            return voisonaTalkLanguage
        }

        private var selectedModelIdentifier: String? {
            let model = switch provider {
            case .openAI: openAIModel
            case .openAICompatibleLocal: openAICompatibleLocalModel
            case .elevenLabs: elevenLabsModel
            default: ""
            }
            return model.isEmpty ? nil : model
        }

        private var selectedStyleIdentifier: String? {
            guard provider == .aivisCloud, !aivisCloudStyleID.isEmpty else { return nil }
            return aivisCloudStyleID
        }

        private var selectedInstructions: String? {
            let instructions = switch provider {
            case .openAI: openAIInstructions
            case .openAICompatibleLocal: openAICompatibleLocalInstructions
            default: ""
            }
            return instructions.isEmpty ? nil : instructions
        }

        private var selectedServiceURL: URL? {
            switch provider {
            case .macOS: nil
            case .voicevoxCompatible: URL(string: localAPIBaseURL)
            case .coeiroink: URL(string: coeiroinkBaseURL)
            case .voicepeak: URL(fileURLWithPath: voicepeakExecutablePath)
            case .voisonaTalk: URL(string: voisonaTalkBaseURL)
            case .openAI: URL(string: "https://api.openai.com/v1")
            case .openAICompatibleLocal: URL(string: openAICompatibleLocalBaseURL)
            case .elevenLabs: URL(string: "https://api.elevenlabs.io/v1")
            case .aivisCloud: URL(string: "https://api.aivis-project.com/v1")
            }
        }

        private enum CodingKeys: String, CodingKey {
            case provider
            case voiceIdentifier
            case localAPIBaseURL
            case localAPIVoiceIdentifier
            case coeiroinkBaseURL
            case coeiroinkSpeakerUUID
            case coeiroinkStyleIdentifier
            case voicepeakExecutablePath
            case voicepeakNarrator
            case voisonaTalkBaseURL
            case voisonaTalkVoiceName
            case voisonaTalkVoiceVersion
            case voisonaTalkLanguage
            case openAIModel
            case openAIVoice
            case openAIInstructions
            case openAICompatibleLocalBaseURL
            case openAICompatibleLocalModel
            case openAICompatibleLocalVoice
            case openAICompatibleLocalInstructions
            case elevenLabsModel
            case elevenLabsVoiceID
            case aivisCloudModelUUID
            case aivisCloudSpeakerUUID
            case aivisCloudStyleID
            case rate
            case volume
            case pitch
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            provider = try values.decodeIfPresent(SpeechSynthesisProvider.self, forKey: .provider) ?? .macOS
            voiceIdentifier = try values.decodeIfPresent(String.self, forKey: .voiceIdentifier) ?? ""
            localAPIBaseURL = try values.decodeIfPresent(String.self, forKey: .localAPIBaseURL)
                ?? "http://127.0.0.1:50021"
            localAPIVoiceIdentifier = try values.decodeIfPresent(String.self, forKey: .localAPIVoiceIdentifier)
                ?? "0"
            coeiroinkBaseURL = try values.decodeIfPresent(String.self, forKey: .coeiroinkBaseURL)
                ?? "http://127.0.0.1:50032"
            coeiroinkSpeakerUUID = try values.decodeIfPresent(String.self, forKey: .coeiroinkSpeakerUUID) ?? ""
            coeiroinkStyleIdentifier = try values.decodeIfPresent(String.self, forKey: .coeiroinkStyleIdentifier)
                ?? "0"
            voicepeakExecutablePath = try values.decodeIfPresent(String.self, forKey: .voicepeakExecutablePath)
                ?? "/Applications/voicepeak.app/Contents/MacOS/voicepeak"
            voicepeakNarrator = try values.decodeIfPresent(String.self, forKey: .voicepeakNarrator) ?? ""
            voisonaTalkBaseURL = try values.decodeIfPresent(String.self, forKey: .voisonaTalkBaseURL)
                ?? "http://127.0.0.1:32766/api/talk/v1"
            voisonaTalkVoiceName = try values.decodeIfPresent(String.self, forKey: .voisonaTalkVoiceName) ?? ""
            voisonaTalkVoiceVersion = try values.decodeIfPresent(String.self, forKey: .voisonaTalkVoiceVersion) ?? ""
            voisonaTalkLanguage = try values.decodeIfPresent(String.self, forKey: .voisonaTalkLanguage) ?? "ja_JP"
            openAIModel = try values.decodeIfPresent(String.self, forKey: .openAIModel) ?? "gpt-4o-mini-tts"
            openAIVoice = try values.decodeIfPresent(String.self, forKey: .openAIVoice) ?? "marin"
            openAIInstructions = try values.decodeIfPresent(String.self, forKey: .openAIInstructions) ?? ""
            openAICompatibleLocalBaseURL = try values.decodeIfPresent(
                String.self,
                forKey: .openAICompatibleLocalBaseURL
            ) ?? "http://127.0.0.1:8088/v1"
            openAICompatibleLocalModel = try values.decodeIfPresent(
                String.self,
                forKey: .openAICompatibleLocalModel
            ) ?? "irodori-tts"
            openAICompatibleLocalVoice = try values.decodeIfPresent(
                String.self,
                forKey: .openAICompatibleLocalVoice
            ) ?? "none"
            openAICompatibleLocalInstructions = try values.decodeIfPresent(
                String.self,
                forKey: .openAICompatibleLocalInstructions
            ) ?? ""
            elevenLabsModel = try values.decodeIfPresent(String.self, forKey: .elevenLabsModel)
                ?? "eleven_multilingual_v2"
            elevenLabsVoiceID = try values.decodeIfPresent(String.self, forKey: .elevenLabsVoiceID) ?? ""
            aivisCloudModelUUID = try values.decodeIfPresent(String.self, forKey: .aivisCloudModelUUID) ?? ""
            aivisCloudSpeakerUUID = try values.decodeIfPresent(String.self, forKey: .aivisCloudSpeakerUUID) ?? ""
            aivisCloudStyleID = try values.decodeIfPresent(String.self, forKey: .aivisCloudStyleID) ?? ""
            rate = try values.decodeIfPresent(Double.self, forKey: .rate) ?? 0.5
            volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? 1
            pitch = try values.decodeIfPresent(Double.self, forKey: .pitch) ?? 1
        }
    }

    enum ContentUpdateKind: String {
        case ghost
        case balloon
    }

    enum StartupBehavior: String, CaseIterable, Identifiable {
        case restore
        case choose
        case random

        var id: Self {
            self
        }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: Self {
            self
        }
    }

    enum AppLanguage: String, CaseIterable, Identifiable {
        case system
        case ja
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"
        case ko

        var id: Self {
            self
        }

        var languageCode: String? {
            self == .system ? nil : rawValue
        }
    }

    enum Pane: Hashable {
        case general
        case content
        case ghost
        case talkAndBalloon
        case voice
        case shiori
        case network
        case advanced
    }

    private enum Key {
        static let automaticHeadlineRefresh = "network.automaticHeadlineRefresh"
        static let headlineRefreshIntervalMinutes = "network.headlineRefreshIntervalMinutes"
        // Keep the existing keys so current users retain their update settings.
        static let automaticContentUpdate = "network.automaticGhostUpdate"
        static let contentUpdateIntervalDays = "network.ghostUpdateIntervalDays"
        static let startupBehavior = "general.startupBehavior"
        static let appearance = "general.appearance"
        static let windowLevelBehavior = "general.windowLevelBehavior"
        static let windowMode = "general.windowMode"
        static let lastWindowModeLayout = "general.lastWindowModeLayout"
        static let integratesSpeechHistoryInWindowMode = "general.integratesSpeechHistoryInWindowMode"
        static let appLanguage = "general.appLanguage"
        static let defaultBalloonDirectoryName = "general.defaultBalloonDirectoryName"
        static let recentContentMaximumCount = "general.recentContentMaximumCount"
        static let characterDelayMilliseconds = "talk.characterDelayMilliseconds"
        static let randomTalkIntervalMinutes = "talk.randomTalkIntervalMinutes"
        static let dialogueDismissalSeconds = "balloon.dialogueDismissalSeconds"
        static let speechSynthesisEnabled = "speech.synthesisEnabled"
        static let speechRecognitionEnabled = "speech.recognitionEnabled"
        static let speechRecognitionLocaleIdentifier = "speech.recognitionLocaleIdentifier"
        static let prefersOnDeviceSpeechRecognition = "speech.prefersOnDeviceRecognition"
        static let speechVoiceSettings = "speech.voiceSettings"
        static let shellScalePercent = "display.shellScalePercent"
        static let automaticallyFitsLargeSurfaces = "display.automaticallyFitsLargeSurfaces"
        static let balloonScalePercent = "display.balloonScalePercent"
        static let linksBalloonScale = "display.linksBalloonScale"
        static let balloonTextScalePercent = "display.balloonTextScalePercent"
        static let locksShellToDesktopBottom = "display.locksShellToDesktopBottom"
        static let keepsShellOnScreen = "display.keepsShellOnScreen"
        static let notifiesNowPlaying = "general.notifiesNowPlaying"
        static let showsDebugWindow = "debug.showsWindow"
        static let wineExecutablePath = "windowsShiori.wineExecutablePath"
        static let winePrefixPath = "windowsShiori.winePrefixPath"
        static let aiProvider = "ai.provider"
        static let aiModel = "ai.model"
        static let aiBaseURL = "ai.baseURL"
        static let realtimeProvider = "realtime.provider"
        static let realtimeModel = "realtime.model"
        static let realtimeVoice = "realtime.voice"
        static let realtimeBaseURL = "realtime.baseURL"
    }

    @Published var automaticHeadlineRefresh: Bool {
        didSet { defaults.set(automaticHeadlineRefresh, forKey: Key.automaticHeadlineRefresh) }
    }

    @Published var headlineRefreshIntervalMinutes: Int {
        didSet { defaults.set(headlineRefreshIntervalMinutes, forKey: Key.headlineRefreshIntervalMinutes) }
    }

    @Published var automaticContentUpdate: Bool {
        didSet { defaults.set(automaticContentUpdate, forKey: Key.automaticContentUpdate) }
    }

    @Published var contentUpdateIntervalDays: Int {
        didSet { defaults.set(contentUpdateIntervalDays, forKey: Key.contentUpdateIntervalDays) }
    }

    @Published var startupBehavior: StartupBehavior {
        didSet { defaults.set(startupBehavior.rawValue, forKey: Key.startupBehavior) }
    }

    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var windowLevelBehavior: GhostWindowLevelBehavior {
        didSet { defaults.set(windowLevelBehavior.rawValue, forKey: Key.windowLevelBehavior) }
    }

    @Published var windowMode: GhostWindowMode {
        didSet {
            defaults.set(windowMode.rawValue, forKey: Key.windowMode)
            if windowMode != .off {
                defaults.set(windowMode.rawValue, forKey: Key.lastWindowModeLayout)
            }
        }
    }

    @Published var integratesSpeechHistoryInWindowMode: Bool {
        didSet {
            defaults.set(
                integratesSpeechHistoryInWindowMode,
                forKey: Key.integratesSpeechHistoryInWindowMode
            )
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
            Self.apply(appLanguage, to: defaults)
            languageRequiresRestart = appLanguage != launchedAppLanguage
        }
    }

    @Published private(set) var languageRequiresRestart = false

    @Published var defaultBalloonDirectoryName: String {
        didSet { defaults.set(defaultBalloonDirectoryName, forKey: Key.defaultBalloonDirectoryName) }
    }

    @Published var recentContentMaximumCount: Int {
        didSet { defaults.set(recentContentMaximumCount, forKey: Key.recentContentMaximumCount) }
    }

    @Published var characterDelayMilliseconds: Int {
        didSet { defaults.set(characterDelayMilliseconds, forKey: Key.characterDelayMilliseconds) }
    }

    @Published var randomTalkIntervalMinutes: Int {
        didSet {
            guard !isLoadingGhostSettings else { return }
            if let activeGhostDirectoryName {
                defaults.set(
                    randomTalkIntervalMinutes,
                    forKey: ghostRandomTalkKey(activeGhostDirectoryName)
                )
            } else {
                defaults.set(randomTalkIntervalMinutes, forKey: Key.randomTalkIntervalMinutes)
            }
        }
    }

    @Published var dialogueDismissalSeconds: Int {
        didSet { defaults.set(dialogueDismissalSeconds, forKey: Key.dialogueDismissalSeconds) }
    }

    @Published var speechSynthesisEnabled: Bool {
        didSet { defaults.set(speechSynthesisEnabled, forKey: Key.speechSynthesisEnabled) }
    }

    @Published var speechRecognitionEnabled: Bool {
        didSet { defaults.set(speechRecognitionEnabled, forKey: Key.speechRecognitionEnabled) }
    }

    @Published var speechRecognitionLocaleIdentifier: String {
        didSet { defaults.set(speechRecognitionLocaleIdentifier, forKey: Key.speechRecognitionLocaleIdentifier) }
    }

    @Published var prefersOnDeviceSpeechRecognition: Bool {
        didSet {
            defaults.set(prefersOnDeviceSpeechRecognition, forKey: Key.prefersOnDeviceSpeechRecognition)
        }
    }

    @Published private(set) var speechVoiceSettingsByScope: [Int: SpeechVoiceSettings] {
        didSet {
            guard let data = try? JSONEncoder().encode(speechVoiceSettingsByScope) else { return }
            defaults.set(data, forKey: Key.speechVoiceSettings)
        }
    }

    @Published var shellScalePercent: Int {
        didSet { saveGhostValue(shellScalePercent, kind: Key.shellScalePercent) }
    }

    @Published var automaticallyFitsLargeSurfaces: Bool {
        didSet { saveGhostValue(automaticallyFitsLargeSurfaces, kind: Key.automaticallyFitsLargeSurfaces) }
    }

    @Published var balloonScalePercent: Int {
        didSet { saveGhostValue(balloonScalePercent, kind: Key.balloonScalePercent) }
    }

    @Published var linksBalloonScale: Bool {
        didSet { saveGhostValue(linksBalloonScale, kind: Key.linksBalloonScale) }
    }

    @Published var balloonTextScalePercent: Int {
        didSet { saveGhostValue(balloonTextScalePercent, kind: Key.balloonTextScalePercent) }
    }

    @Published var locksShellToDesktopBottom: Bool {
        didSet { saveGhostValue(locksShellToDesktopBottom, kind: Key.locksShellToDesktopBottom) }
    }

    @Published var keepsShellOnScreen: Bool {
        didSet { saveGhostValue(keepsShellOnScreen, kind: Key.keepsShellOnScreen) }
    }

    @Published var notifiesNowPlaying: Bool {
        didSet { defaults.set(notifiesNowPlaying, forKey: Key.notifiesNowPlaying) }
    }

    @Published var showsDebugWindow: Bool {
        didSet { defaults.set(showsDebugWindow, forKey: Key.showsDebugWindow) }
    }

    @Published var wineExecutablePath: String {
        didSet { defaults.set(wineExecutablePath, forKey: Key.wineExecutablePath) }
    }

    @Published var winePrefixPath: String {
        didSet { defaults.set(winePrefixPath, forKey: Key.winePrefixPath) }
    }

    @Published var aiProvider: AIProviderKind {
        didSet { defaults.set(aiProvider.rawValue, forKey: Key.aiProvider) }
    }

    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Key.aiModel) }
    }

    @Published var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Key.aiBaseURL) }
    }

    @Published var aiAPIKey: String {
        didSet { AIAPIKeyStore.save(aiAPIKey) }
    }

    @Published var realtimeProvider: RealtimeProviderKind {
        didSet { defaults.set(realtimeProvider.rawValue, forKey: Key.realtimeProvider) }
    }

    @Published var realtimeModel: String {
        didSet { defaults.set(realtimeModel, forKey: Key.realtimeModel) }
    }

    @Published var realtimeVoice: String {
        didSet { defaults.set(realtimeVoice, forKey: Key.realtimeVoice) }
    }

    @Published var realtimeBaseURL: String {
        didSet { defaults.set(realtimeBaseURL, forKey: Key.realtimeBaseURL) }
    }

    @Published var realtimeAPIKey: String {
        didSet { AIAPIKeyStore.save(realtimeAPIKey, account: "realtime") }
    }

    @Published var selectedPane: Pane = .general
    @Published private(set) var activeGhostName: String?

    private let defaults: UserDefaults
    private let launchedAppLanguage: AppLanguage
    private var activeGhostDirectoryName: String?
    private var isLoadingGhostSettings = false

    init(defaults: UserDefaults = .standard, arguments: [String] = CommandLine.arguments) {
        self.defaults = defaults
        automaticHeadlineRefresh = defaults.bool(forKey: Key.automaticHeadlineRefresh)
        headlineRefreshIntervalMinutes = Self.positiveValue(
            defaults.integer(forKey: Key.headlineRefreshIntervalMinutes),
            fallback: 60
        )
        automaticContentUpdate = defaults.bool(forKey: Key.automaticContentUpdate)
        contentUpdateIntervalDays = Self.positiveValue(
            defaults.integer(forKey: Key.contentUpdateIntervalDays),
            fallback: 7
        )
        startupBehavior = StartupBehavior(
            rawValue: defaults.string(forKey: Key.startupBehavior) ?? ""
        ) ?? .restore
        appearance = Appearance(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
        windowLevelBehavior = GhostWindowLevelBehavior(
            rawValue: defaults.string(forKey: Key.windowLevelBehavior) ?? ""
        ) ?? .always
        let storedWindowMode = GhostWindowMode(
            rawValue: defaults.string(forKey: Key.windowMode) ?? ""
        ) ?? .off
        let lastWindowModeLayout = GhostWindowMode(
            rawValue: defaults.string(forKey: Key.lastWindowModeLayout) ?? ""
        ) ?? (storedWindowMode == .off ? .shared : storedWindowMode)
        let resolvedWindowMode = GhostWindowMode.launchOverride(
            in: arguments,
            previousLayout: lastWindowModeLayout
        ) ?? storedWindowMode
        windowMode = resolvedWindowMode
        if resolvedWindowMode != storedWindowMode {
            defaults.set(resolvedWindowMode.rawValue, forKey: Key.windowMode)
        }
        if resolvedWindowMode != .off {
            defaults.set(resolvedWindowMode.rawValue, forKey: Key.lastWindowModeLayout)
        }
        integratesSpeechHistoryInWindowMode = defaults.object(
            forKey: Key.integratesSpeechHistoryInWindowMode
        ) as? Bool ?? true
        let loadedAppLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Key.appLanguage) ?? ""
        ) ?? .system
        appLanguage = loadedAppLanguage
        launchedAppLanguage = loadedAppLanguage
        defaultBalloonDirectoryName = defaults.string(forKey: Key.defaultBalloonDirectoryName) ?? ""
        recentContentMaximumCount = Self.positiveValue(
            defaults.integer(forKey: Key.recentContentMaximumCount),
            fallback: 12
        )
        characterDelayMilliseconds = defaults.object(forKey: Key.characterDelayMilliseconds) == nil
            ? 50 : defaults.integer(forKey: Key.characterDelayMilliseconds)
        randomTalkIntervalMinutes = defaults.integer(forKey: Key.randomTalkIntervalMinutes)
        dialogueDismissalSeconds = Self.positiveValue(
            defaults.integer(forKey: Key.dialogueDismissalSeconds),
            fallback: 10
        )
        speechSynthesisEnabled = defaults.bool(forKey: Key.speechSynthesisEnabled)
        speechRecognitionEnabled = defaults.bool(forKey: Key.speechRecognitionEnabled)
        speechRecognitionLocaleIdentifier = defaults.string(
            forKey: Key.speechRecognitionLocaleIdentifier
        ) ?? Self.defaultSpeechRecognitionLocaleIdentifier
        prefersOnDeviceSpeechRecognition = defaults.object(
            forKey: Key.prefersOnDeviceSpeechRecognition
        ) as? Bool ?? true
        if let data = defaults.data(forKey: Key.speechVoiceSettings),
           let settings = try? JSONDecoder().decode([Int: SpeechVoiceSettings].self, from: data)
        {
            speechVoiceSettingsByScope = settings
        } else {
            speechVoiceSettingsByScope = [0: SpeechVoiceSettings(), 1: SpeechVoiceSettings()]
        }
        shellScalePercent = 100
        automaticallyFitsLargeSurfaces = true
        balloonScalePercent = 100
        linksBalloonScale = true
        balloonTextScalePercent = 100
        locksShellToDesktopBottom = true
        keepsShellOnScreen = true
        notifiesNowPlaying = defaults.bool(forKey: Key.notifiesNowPlaying)
        showsDebugWindow = defaults.bool(forKey: Key.showsDebugWindow)
        wineExecutablePath = defaults.string(forKey: Key.wineExecutablePath) ?? ""
        winePrefixPath = defaults.string(forKey: Key.winePrefixPath) ?? ""
        aiProvider = AIProviderKind(rawValue: defaults.string(forKey: Key.aiProvider) ?? "") ?? .openAICompatible
        aiModel = defaults.string(forKey: Key.aiModel) ?? "llama3.2"
        aiBaseURL = defaults.string(forKey: Key.aiBaseURL) ?? ""
        aiAPIKey = AIAPIKeyStore.load()
        realtimeProvider = RealtimeProviderKind(
            rawValue: defaults.string(forKey: Key.realtimeProvider) ?? ""
        ) ?? .openAI
        realtimeModel = defaults.string(forKey: Key.realtimeModel) ?? "gpt-realtime"
        realtimeVoice = defaults.string(forKey: Key.realtimeVoice) ?? "alloy"
        realtimeBaseURL = defaults.string(forKey: Key.realtimeBaseURL) ?? ""
        realtimeAPIKey = AIAPIKeyStore.load(account: "realtime")
        Self.apply(appLanguage, to: defaults)
    }

    func speechVoiceSettings(for scope: Int) -> SpeechVoiceSettings {
        speechVoiceSettingsByScope[scope] ?? SpeechVoiceSettings()
    }

    func setSpeechVoiceSettings(_ settings: SpeechVoiceSettings, for scope: Int) {
        speechVoiceSettingsByScope[scope] = settings
    }

    private static func apply(_ language: AppLanguage, to defaults: UserDefaults) {
        if let languageCode = language.languageCode {
            defaults.set([languageCode], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    private static var defaultSpeechRecognitionLocaleIdentifier: String {
        switch Locale.current.language.languageCode?.identifier {
        case "en": "en-US"
        case "zh": Locale.current.scriptCode == "Hant" ? "zh-TW" : "zh-CN"
        case "ko": "ko-KR"
        default: "ja-JP"
        }
    }

    private static func positiveValue(_ value: Int, fallback: Int) -> Int {
        value > 0 ? value : fallback
    }

    func activateGhost(directoryName: String, displayName: String) {
        activeGhostDirectoryName = directoryName
        activeGhostName = displayName
        isLoadingGhostSettings = true
        let key = ghostRandomTalkKey(directoryName)
        if defaults.object(forKey: key) != nil {
            randomTalkIntervalMinutes = defaults.integer(forKey: key)
        } else {
            randomTalkIntervalMinutes = defaults.integer(forKey: Key.randomTalkIntervalMinutes)
        }
        shellScalePercent = ghostIntegerValue(
            directoryName: directoryName,
            kind: Key.shellScalePercent,
            fallback: 100
        )
        automaticallyFitsLargeSurfaces = ghostBoolValue(
            directoryName: directoryName,
            kind: Key.automaticallyFitsLargeSurfaces,
            fallback: true
        )
        balloonScalePercent = ghostIntegerValue(
            directoryName: directoryName,
            kind: Key.balloonScalePercent,
            fallback: 100
        )
        linksBalloonScale = ghostBoolValue(
            directoryName: directoryName,
            kind: Key.linksBalloonScale,
            fallback: true
        )
        balloonTextScalePercent = ghostIntegerValue(
            directoryName: directoryName,
            kind: Key.balloonTextScalePercent,
            fallback: 100
        )
        locksShellToDesktopBottom = ghostBoolValue(
            directoryName: directoryName,
            kind: Key.locksShellToDesktopBottom,
            fallback: true
        )
        keepsShellOnScreen = ghostBoolValue(
            directoryName: directoryName,
            kind: Key.keepsShellOnScreen,
            fallback: true
        )
        isLoadingGhostSettings = false
    }

    func shouldAutomaticallyUpdateContent(
        kind: ContentUpdateKind,
        directoryName: String,
        now: Date = Date()
    ) -> Bool {
        guard automaticContentUpdate else { return false }
        let lastAttempt = defaults.object(
            forKey: contentUpdateKey("network.lastAttempt", kind: kind, directoryName: directoryName)
        ) as? Date ?? legacyGhostUpdateDate(kind: kind, directoryName: directoryName)
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Double(contentUpdateIntervalDays) * 86400
    }

    func recordContentUpdateAttempt(
        kind: ContentUpdateKind,
        directoryName: String,
        at date: Date = Date()
    ) {
        defaults.set(
            date,
            forKey: contentUpdateKey("network.lastAttempt", kind: kind, directoryName: directoryName)
        )
    }

    func recordContentUpdateSuccess(
        kind: ContentUpdateKind,
        directoryName: String,
        at date: Date = Date()
    ) {
        defaults.set(
            date,
            forKey: contentUpdateKey("network.lastSuccess", kind: kind, directoryName: directoryName)
        )
    }

    private func saveGhostValue(_ value: Any, kind: String) {
        guard !isLoadingGhostSettings, let activeGhostDirectoryName else { return }
        defaults.set(value, forKey: ghostKey(kind, activeGhostDirectoryName))
    }

    private func ghostIntegerValue(directoryName: String, kind: String, fallback: Int) -> Int {
        let value = defaults.integer(forKey: ghostKey(kind, directoryName))
        return value > 0 ? value : fallback
    }

    private func ghostBoolValue(directoryName: String, kind: String, fallback: Bool) -> Bool {
        let key = ghostKey(kind, directoryName)
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private func ghostKey(_ kind: String, _ directoryName: String) -> String {
        "\(kind).\(directoryName)"
    }

    private func contentUpdateKey(
        _ prefix: String,
        kind: ContentUpdateKind,
        directoryName: String
    ) -> String {
        "\(prefix).\(kind.rawValue).\(directoryName)"
    }

    private func legacyGhostUpdateDate(kind: ContentUpdateKind, directoryName: String) -> Date? {
        guard kind == .ghost else { return nil }
        return defaults.object(forKey: ghostKey("network.lastUpdate", directoryName)) as? Date
    }

    private func ghostRandomTalkKey(_ directoryName: String) -> String {
        "talk.randomTalkIntervalMinutes.\(directoryName)"
    }
}

struct UtataneSettingsView: View {
    @ObservedObject var settings: UtataneSettingsStore
    @ObservedObject var contentSources: ContentSourceStore
    @ObservedObject private var relauncher = ApplicationRelauncher.shared
    let headlineDirectories: [URL]
    let balloonDirectories: [URL]
    let appUpdater: SPUUpdater
    @State private var headlines: [InstalledHeadline] = []
    @State private var balloons: [BalloonDefinition] = []
    @State private var loadError: String?
    @State private var restartError: String?
    @State private var contentSourcesRequireRestart = false

    var body: some View {
        TabView(selection: $settings.selectedPane) {
            SettingsPage(
                title: "一般",
                description: "Utatane全体の基本設定。"
            ) {
                Section("起動と操作") {
                    Picker("起動するゴースト", selection: $settings.startupBehavior) {
                        Text("前回のゴースト").tag(UtataneSettingsStore.StartupBehavior.restore)
                        Text("起動時に選択").tag(UtataneSettingsStore.StartupBehavior.choose)
                        Text("ランダム").tag(UtataneSettingsStore.StartupBehavior.random)
                    }
                    Picker("外観", selection: $settings.appearance) {
                        Text("システム設定に合わせる").tag(UtataneSettingsStore.Appearance.system)
                        Text("ライト").tag(UtataneSettingsStore.Appearance.light)
                        Text("ダーク").tag(UtataneSettingsStore.Appearance.dark)
                    }
                    Text("Shell、バルーン、キャラクター位置は、最後に使った状態がゴーストごとに復元される。")
                        .foregroundStyle(.secondary)
                }
                Section("ウィンドウモード（実験的）") {
                    Picker("表示方式", selection: $settings.windowMode) {
                        Text("使用しない").tag(GhostWindowMode.off)
                        Text("全ゴーストをまとめて1枚").tag(GhostWindowMode.shared)
                        Text("ゴーストごとに1枚").tag(GhostWindowMode.perGhost)
                    }
                    Toggle(
                        "発話履歴をウィンドウ内に表示",
                        isOn: $settings.integratesSpeechHistoryInWindowMode
                    )
                    .disabled(settings.windowMode == .off)
                    Text("ゴーストとバルーンを通常の1枚のウィンドウ内に表示する。配信や画面収録でウィンドウ単位に取り込みやすくなる。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("ウィンドウ表示") {
                    Picker("手前に表示", selection: $settings.windowLevelBehavior) {
                        Text("常に").tag(GhostWindowLevelBehavior.always)
                        Text("発話中だけ").tag(GhostWindowLevelBehavior.whileTalking)
                        Text("通常のウィンドウと同じ").tag(GhostWindowLevelBehavior.normal)
                    }
                    Text("サーフェスとバルーンをほかのウィンドウより手前に表示するタイミングを選ぶ。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("音楽再生") {
                    Toggle("再生中の曲情報をゴーストに通知", isOn: $settings.notifiesNowPlaying)
                    Text("Spotify、ミュージック、ブラウザなど、macOSの「再生中」に表示される曲が変わった時に通知する。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("言語") {
                    Picker("表示言語", selection: $settings.appLanguage) {
                        Text("システム設定に合わせる").tag(UtataneSettingsStore.AppLanguage.system)
                        Text("日本語").tag(UtataneSettingsStore.AppLanguage.ja)
                        Text("英語").tag(UtataneSettingsStore.AppLanguage.en)
                        Text("中国語（簡体字）").tag(UtataneSettingsStore.AppLanguage.zhHans)
                        Text("中国語（繁体字）").tag(UtataneSettingsStore.AppLanguage.zhHant)
                        Text("韓国語").tag(UtataneSettingsStore.AppLanguage.ko)
                    }
                    if settings.languageRequiresRestart {
                        Text("言語の変更はUtataneの再起動後に反映される。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("今すぐ再起動") {
                            restartApplication()
                        }
                        .disabled(relauncher.isRestarting)
                    }
                }
                Section("既定のバルーン") {
                    Picker("バルーン", selection: $settings.defaultBalloonDirectoryName) {
                        Text("インストール済みの先頭").tag("")
                        ForEach(balloons, id: \.directory) { balloon in
                            Text(balloon.name).tag(balloon.directory.lastPathComponent)
                        }
                    }
                    Text("ゴースト自身にも、ゴーストごとの履歴にも指定がない場合に使う。削除されていた場合は利用可能なバルーンへ切り替わる。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("最近使ったもの") {
                    Picker("最大件数", selection: $settings.recentContentMaximumCount) {
                        ForEach([5, 10, 12, 20, 30], id: \.self) { count in
                            Text("\(count)件").tag(count)
                        }
                    }
                    Text("ゴーストの右クリックメニューに保存する利用履歴の件数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("一般", systemImage: "gearshape") }
            .tag(UtataneSettingsStore.Pane.general)

            SettingsPage(
                title: "コンテンツフォルダ",
                description: "ゴーストなどを種類ごとに複数のフォルダから読み込む。"
            ) {
                ContentSourcesSettingsView(
                    store: contentSources,
                    requiresRestart: $contentSourcesRequireRestart
                )
                if contentSourcesRequireRestart {
                    Section {
                        Text("変更はUtataneの再起動後に反映される。")
                            .foregroundStyle(.secondary)
                        Button("今すぐ再起動") {
                            restartApplication()
                        }
                        .disabled(relauncher.isRestarting)
                    }
                }
            }
            .tabItem { Label("コンテンツ", systemImage: "folder") }
            .tag(UtataneSettingsStore.Pane.content)

            SettingsPage(
                title: "ゴーストごとの設定",
                description: settings.activeGhostName.map { LocalizedStringKey("「\($0)」にだけ適用する設定。") }
                    ?? LocalizedStringKey("現在表示しているゴーストにだけ適用する設定。")
            ) {
                Section("自動会話") {
                    Picker("会話間隔", selection: $settings.randomTalkIntervalMinutes) {
                        Text("しない").tag(0)
                        Text("1分ごと").tag(1)
                        Text("3分ごと").tag(3)
                        Text("5分ごと").tag(5)
                        Text("10分ごと").tag(10)
                        Text("15分ごと").tag(15)
                        Text("30分ごと").tag(30)
                    }
                    .disabled(settings.activeGhostName == nil)
                    Text("ゴースト自身が会話間隔を管理する場合は「しない」にする。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("表示倍率") {
                    Picker("シェル", selection: $settings.shellScalePercent) {
                        ForEach([25, 50, 75, 100, 125, 150, 200], id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    Toggle("大きいシェルを画面に合わせて縮小", isOn: $settings.automaticallyFitsLargeSurfaces)
                    Toggle("バルーンをシェル倍率に連動", isOn: $settings.linksBalloonScale)
                    Picker("バルーン", selection: $settings.balloonScalePercent) {
                        ForEach([25, 50, 75, 100, 125, 150, 200], id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    .disabled(settings.linksBalloonScale)
                    Text("倍率は現在のゴーストにだけ保存される。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("配置") {
                    Toggle("画面下に固定", isOn: $settings.locksShellToDesktopBottom)
                    Toggle("画面端からはみ出さない", isOn: $settings.keepsShellOnScreen)
                    Text("画面下に固定している間は、ドラッグ時に横方向だけ移動する。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("ゴースト", systemImage: "person.2") }
            .tag(UtataneSettingsStore.Pane.ghost)

            SettingsPage(
                title: "喋り / バルーン",
                description: "すべてのゴーストに共通する会話表示の設定。"
            ) {
                Section("喋り") {
                    Picker("喋る速度", selection: $settings.characterDelayMilliseconds) {
                        Text("瞬間表示").tag(0)
                        Text("速い").tag(25)
                        Text("標準").tag(50)
                        Text("遅い").tag(80)
                        Text("かなり遅い").tag(120)
                    }
                }
                Section("バルーン") {
                    Picker("文字サイズ", selection: $settings.balloonTextScalePercent) {
                        ForEach([75, 90, 100, 110, 125, 150], id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    Picker("会話後に閉じる", selection: $settings.dialogueDismissalSeconds) {
                        Text("5秒").tag(5)
                        Text("10秒").tag(10)
                        Text("20秒").tag(20)
                        Text("30秒").tag(30)
                        Text("1分").tag(60)
                    }
                    Text("使用するShellとバルーン、キャラクター位置はゴーストごとに保存される。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("喋り / バルーン", systemImage: "text.bubble") }
            .tag(UtataneSettingsStore.Pane.talkAndBalloon)

            SettingsPage(
                title: "音声",
                description: "音声合成エンジンとmacOS標準の音声認識を設定する。"
            ) {
                Section("音声合成") {
                    Toggle("ゴーストの発話を読み上げる", isOn: $settings.speechSynthesisEnabled)
                    ForEach([0, 1], id: \.self) { scope in
                        SpeechVoiceSettingsEditor(
                            title: scope == 0 ? "本体（スコープ0）" : "相方（スコープ1）",
                            scope: scope,
                            voices: MacOSSpeechSynthesizer.availableVoices,
                            settings: Binding(
                                get: { settings.speechVoiceSettings(for: scope) },
                                set: { settings.setSpeechVoiceSettings($0, for: scope) }
                            )
                        )
                    }
                    Text("SakuraScriptの\\__v[disable]と\\__v[alternate,...]にも対応する。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("音声認識") {
                    Toggle("マイクから音声を認識する", isOn: $settings.speechRecognitionEnabled)
                    Picker("認識言語", selection: $settings.speechRecognitionLocaleIdentifier) {
                        Text("日本語").tag("ja-JP")
                        Text("English (US)").tag("en-US")
                        Text("English (UK)").tag("en-GB")
                        Text("简体中文").tag("zh-CN")
                        Text("繁體中文").tag("zh-TW")
                        Text("한국어").tag("ko-KR")
                    }
                    Toggle(
                        "利用できる場合はデバイス上で認識",
                        isOn: $settings.prefersOnDeviceSpeechRecognition
                    )
                    Text("初回にマイクと音声認識の許可を求める。確定した認識結果だけをゴーストへ通知する。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("音声", systemImage: "waveform") }
            .tag(UtataneSettingsStore.Pane.voice)

            SettingsPage(
                title: "SHIORI対応状況",
                description: "Utataneが認識するSHIORIの実行方式を確認する。"
            ) {
                ShioriStatusView()
            }
            .tabItem { Label("SHIORI", systemImage: "puzzlepiece.extension") }
            .tag(UtataneSettingsStore.Pane.shiori)

            SettingsPage(
                title: "ネットワーク",
                description: "RSS / Atomとヘッドラインの自動巡回を設定する。"
            ) {
                Section("RSS / ヘッドライン") {
                    Toggle("自動巡回する", isOn: $settings.automaticHeadlineRefresh)
                    Picker("巡回間隔", selection: $settings.headlineRefreshIntervalMinutes) {
                        Text("15分").tag(15)
                        Text("30分").tag(30)
                        Text("1時間").tag(60)
                        Text("3時間").tag(180)
                        Text("6時間").tag(360)
                    }
                    .disabled(!settings.automaticHeadlineRefresh)
                }

                Section("生成AIゴースト") {
                    Picker("プロバイダー", selection: $settings.aiProvider) {
                        Text("OpenAI").tag(AIProviderKind.openAI)
                        Text("Claude (Anthropic)").tag(AIProviderKind.anthropic)
                        Text("Gemini").tag(AIProviderKind.gemini)
                        Text("OpenAI互換 / ローカル").tag(AIProviderKind.openAICompatible)
                    }
                    TextField("モデル", text: $settings.aiModel)
                    TextField("Base URL", text: $settings.aiBaseURL)
                    SecureField("APIキー（Keychainに保存）", text: $settings.aiAPIKey)
                    Text("OpenAI互換ではAPIキーを空にできる。設定変更後はAIゴーストを再読み込みする。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("リアルタイム音声会話") {
                    Picker("プロバイダー", selection: $settings.realtimeProvider) {
                        Text("OpenAI Realtime").tag(RealtimeProviderKind.openAI)
                        Text("OpenAI Realtime互換").tag(RealtimeProviderKind.openAICompatible)
                    }
                    TextField("モデル", text: $settings.realtimeModel)
                    TextField("Voice", text: $settings.realtimeVoice)
                    TextField("Base URL", text: $settings.realtimeBaseURL)
                    SecureField("APIキー（Keychainに保存）", text: $settings.realtimeAPIKey)
                    Text("OpenAIではBase URLを空にできる。互換APIではサービスのURLを設定する。設定値は配布するゴーストへ保存されない。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AppUpdateSettingsView(updater: appUpdater)

                Section("ゴースト / バルーンのネットワーク更新") {
                    Toggle("起動後に自動更新を確認", isOn: $settings.automaticContentUpdate)
                    Picker("更新間隔", selection: $settings.contentUpdateIntervalDays) {
                        Text("毎日").tag(1)
                        Text("3日ごと").tag(3)
                        Text("7日ごと").tag(7)
                        Text("14日ごと").tag(14)
                        Text("30日ごと").tag(30)
                    }
                    .disabled(!settings.automaticContentUpdate)
                    Text("homeurlが設定されたゴーストとバルーンが対象。手動更新は右クリックメニューから実行できる。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("インストール済みヘッドライン") {
                    if let loadError {
                        Text(loadError).foregroundStyle(.red)
                    } else if headlines.isEmpty {
                        ContentUnavailableView(
                            "ヘッドラインはありません",
                            systemImage: "newspaper",
                            description: Text("NARをインストールすると、ここに表示される。")
                        )
                    } else {
                        ForEach(headlines) { headline in
                            HStack {
                                Text(headline.name)
                                Spacer()
                                Text(kindLabel(headline)).foregroundStyle(.secondary)
                                if let readmeURL = headline.readmeURL {
                                    Button("README") {
                                        NSWorkspace.shared.open(readmeURL)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .tabItem { Label("ネットワーク", systemImage: "network") }
            .tag(UtataneSettingsStore.Pane.network)

            SettingsPage(
                title: "詳細",
                description: "通常は変更する必要のない開発・診断用の設定。"
            ) {
                Section("開発用") {
                    Toggle("開発用パレットを表示", isOn: $settings.showsDebugWindow)
                    Text("ログ、当たり判定、バルーンテスト、SakuraScript入力、再生操作を表示する。通常の利用では非表示でよい。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Windows互換モジュール") {
                    TextField("Wine実行ファイル", text: $settings.wineExecutablePath)
                    TextField("WINEPREFIX", text: $settings.winePrefixPath)
                    Text("MateriaのFIRST、外部SHIORI・SAORI・プラグインDLL、config.txtで解析できないHEADLINE DLLに使用する。32-bit Windowsアプリを実行できるWineと、専用のprefixを指定する。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("詳細", systemImage: "wrench.and.screwdriver") }
            .tag(UtataneSettingsStore.Pane.advanced)
        }
        .frame(width: 560, height: 520)
        .task { reload() }
        .alert("再起動できなかった", isPresented: Binding(
            get: { restartError != nil },
            set: {
                if !$0 {
                    restartError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { restartError = nil }
        } message: {
            Text("Utataneを終了して、もう一度開いてね。")
            if let restartError {
                Text(verbatim: restartError)
            }
        }
    }

    private func reload() {
        balloons = (try? BalloonLoader().loadInstalled(from: balloonDirectories)) ?? []
        if !settings.defaultBalloonDirectoryName.isEmpty,
           !balloons.contains(where: {
               $0.directory.lastPathComponent == settings.defaultBalloonDirectoryName
           })
        {
            settings.defaultBalloonDirectoryName = ""
        }
        do {
            headlines = try HeadlineCatalog().load(from: headlineDirectories)
            loadError = nil
        } catch {
            headlines = []
            loadError = error.localizedDescription
        }
    }

    private func restartApplication() {
        do {
            try relauncher.restart()
        } catch {
            restartError = error.localizedDescription
        }
    }

    private func kindLabel(_ headline: InstalledHeadline) -> String {
        switch headline.kind {
        case .rss: "RSS / Atom"
        case .legacyDLL:
            ConfigHeadlineSensor.canLoad(headline) ? "HEADLINE設定" : "HEADLINE DLL（Wine）"
        }
    }
}

private struct SpeechVoiceSettingsEditor: View {
    let title: String
    let scope: Int
    let voices: [SpeechSynthesisVoice]
    @Binding var settings: UtataneSettingsStore.SpeechVoiceSettings
    @State private var voisonaTalkCredential: SpeechCredentialStore.Credential
    @State private var openAICredential: SpeechCredentialStore.Credential
    @State private var openAICompatibleLocalCredential: SpeechCredentialStore.Credential
    @State private var elevenLabsCredential: SpeechCredentialStore.Credential
    @State private var aivisCloudCredential: SpeechCredentialStore.Credential
    @State private var localAPIVoices: [SpeechSynthesisVoice] = []
    @State private var localAPIVoiceCount: Int?
    @State private var localAPIError: String?
    @State private var loadsLocalAPIVoices = false

    init(
        title: String,
        scope: Int,
        voices: [SpeechSynthesisVoice],
        settings: Binding<UtataneSettingsStore.SpeechVoiceSettings>
    ) {
        self.title = title
        self.scope = scope
        self.voices = voices
        _settings = settings
        _voisonaTalkCredential = State(initialValue: SpeechCredentialStore.load(scope: scope))
        _openAICredential = State(initialValue: SpeechCredentialStore.load(provider: .openAI, scope: scope))
        _openAICompatibleLocalCredential = State(
            initialValue: SpeechCredentialStore.load(provider: .openAICompatibleLocal, scope: scope)
        )
        _elevenLabsCredential = State(
            initialValue: SpeechCredentialStore.load(provider: .elevenLabs, scope: scope)
        )
        _aivisCloudCredential = State(
            initialValue: SpeechCredentialStore.load(provider: .aivisCloud, scope: scope)
        )
    }

    var body: some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("音声エンジン")
                    Picker("", selection: $settings.provider) {
                        Text("macOS標準").tag(SpeechSynthesisProvider.macOS)
                        Text("VOICEVOX互換API").tag(SpeechSynthesisProvider.voicevoxCompatible)
                        Text("COEIROINK v2").tag(SpeechSynthesisProvider.coeiroink)
                        Text("VOICEPEAK").tag(SpeechSynthesisProvider.voicepeak)
                        Text("VoiSona Talk").tag(SpeechSynthesisProvider.voisonaTalk)
                        Text("OpenAI").tag(SpeechSynthesisProvider.openAI)
                        Text("OpenAI互換ローカルAPI").tag(SpeechSynthesisProvider.openAICompatibleLocal)
                        Text("ElevenLabs").tag(SpeechSynthesisProvider.elevenLabs)
                        Text("Aivis Cloud API").tag(SpeechSynthesisProvider.aivisCloud)
                    }
                    .labelsHidden()
                }
                if settings.provider == .macOS {
                    GridRow {
                        Text("声")
                        Picker("", selection: $settings.voiceIdentifier) {
                            Text("システム標準").tag("")
                            ForEach(voices) { voice in
                                Text("\(voice.name) — \(voice.language)").tag(voice.identifier)
                            }
                        }
                        .labelsHidden()
                    }
                } else if settings.provider == .openAI || settings.provider == .openAICompatibleLocal {
                    if settings.provider == .openAICompatibleLocal {
                        GridRow {
                            Text("API URL")
                            TextField("", text: $settings.openAICompatibleLocalBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        Text("モデル")
                        TextField("", text: openAIModel, prompt: Text(openAIModelPlaceholder))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(settings.provider == .openAI ? "APIキー" : "Bearerトークン（任意）")
                        SecureField(
                            "",
                            text: openAIAPIKey,
                            prompt: settings.provider == .openAI ? Text("APIキー") : nil
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("声")
                        if settings.provider == .openAI {
                            Picker("", selection: $settings.openAIVoice) {
                                ForEach(Self.openAIVoices, id: \.self) { voice in
                                    Text(voice).tag(voice)
                                }
                            }
                            .labelsHidden()
                        } else {
                            TextField("", text: $settings.openAICompatibleLocalVoice, prompt: Text("none"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        Text("話し方の指示")
                        TextField("", text: openAIInstructions, prompt: Text("落ち着いた自然な声で話す"))
                            .textFieldStyle(.roundedBorder)
                    }
                    if settings.provider == .openAI {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text("発話テキストをOpenAIへ送信する。利用量に応じて料金が発生する場合がある。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if settings.provider == .aivisCloud {
                    GridRow {
                        Text("APIキー")
                        SecureField("", text: $aivisCloudCredential.password, prompt: Text("APIキー"))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("モデルUUID / アクセスキー")
                        TextField("", text: $settings.aivisCloudModelUUID, prompt: Text("model_uuid / ak_…"))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("話者UUID（任意）")
                        TextField("", text: $settings.aivisCloudSpeakerUUID, prompt: Text("speaker_uuid"))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("スタイルID（任意）")
                        TextField("", text: $settings.aivisCloudStyleID, prompt: Text("style_id"))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        Text("発話テキストをAivis Cloud APIへ送信する。利用量に応じて料金が発生する場合がある。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if settings.provider == .elevenLabs {
                    GridRow {
                        Text("モデル")
                        TextField("", text: $settings.elevenLabsModel, prompt: Text("eleven_multilingual_v2"))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("APIキー")
                        SecureField("", text: $elevenLabsCredential.password, prompt: Text("APIキー"))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("話者ID")
                        HStack {
                            TextField("", text: $settings.elevenLabsVoiceID, prompt: Text("voice_id"))
                                .textFieldStyle(.roundedBorder)
                            Button("話者一覧を取得") {
                                Task { await loadLocalAPIVoices() }
                            }
                            .disabled(loadsLocalAPIVoices)
                        }
                    }
                    if !localAPIVoices.isEmpty {
                        GridRow {
                            Text("話者")
                            Picker("", selection: $settings.elevenLabsVoiceID) {
                                ForEach(localAPIVoices) { voice in
                                    Text(voice.name).tag(voice.identifier)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    if loadsLocalAPIVoices {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            ProgressView("話者一覧を取得中…")
                                .controlSize(.small)
                        }
                    } else if let localAPIError {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text(localAPIError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else if let localAPIVoiceCount {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text("話者を\(localAPIVoiceCount)件取得した。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        Text("発話テキストをElevenLabsへ送信する。利用量に応じて料金が発生する場合がある。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    GridRow {
                        Text(settings.provider == .voicepeak ? "実行ファイル" : "API URL")
                        TextField("", text: externalServiceLocation, prompt: Text(externalServicePlaceholder))
                            .textFieldStyle(.roundedBorder)
                    }
                    if settings.provider == .coeiroink {
                        GridRow {
                            Text("話者UUID")
                            TextField("", text: $settings.coeiroinkSpeakerUUID, prompt: Text("speakerUuid"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    if settings.provider == .voisonaTalk {
                        GridRow {
                            Text("APIユーザー名")
                            TextField("", text: $voisonaTalkCredential.username, prompt: Text("name@example.com"))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("APIパスワード")
                            SecureField("", text: $voisonaTalkCredential.password, prompt: Text("APIパスワード"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        Text(externalVoiceIdentifierLabel)
                        HStack {
                            TextField("", text: externalVoiceIdentifier, prompt: Text(externalVoiceIdentifierPlaceholder))
                                .textFieldStyle(.roundedBorder)
                            Button("話者一覧を取得") {
                                Task { await loadLocalAPIVoices() }
                            }
                            .disabled(loadsLocalAPIVoices)
                        }
                    }
                    if settings.provider == .voisonaTalk {
                        GridRow {
                            Text("ボイスバージョン")
                            TextField("", text: $settings.voisonaTalkVoiceVersion, prompt: Text("1.0.0"))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("言語")
                            TextField("", text: $settings.voisonaTalkLanguage, prompt: Text("ja_JP"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    if !localAPIVoices.isEmpty {
                        GridRow {
                            Text("話者")
                            Picker("", selection: externalVoiceSelection) {
                                ForEach(localAPIVoices) { voice in
                                    Text(voice.name).tag(voice.id)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    if loadsLocalAPIVoices {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            ProgressView("話者一覧を取得中…")
                                .controlSize(.small)
                        }
                    } else if let localAPIError {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text(localAPIError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else if let localAPIVoiceCount {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            Text("話者を\(localAPIVoiceCount)件取得した。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("速さ")
                    Slider(value: $settings.rate, in: 0.1 ... 1)
                }
                GridRow {
                    Text("音量")
                    Slider(value: $settings.volume, in: 0 ... 1)
                }
                if settings.provider != .openAI,
                   settings.provider != .openAICompatibleLocal,
                   settings.provider != .elevenLabs
                {
                    GridRow {
                        Text("高さ")
                        Slider(value: $settings.pitch, in: 0.5 ... 2)
                    }
                }
            }
        }
        .onChange(of: settings.provider) {
            resetLocalAPIVoices()
        }
        .onChange(of: settings.localAPIBaseURL) {
            resetLocalAPIVoices()
        }
        .onChange(of: settings.coeiroinkBaseURL) {
            resetLocalAPIVoices()
        }
        .onChange(of: settings.voicepeakExecutablePath) {
            resetLocalAPIVoices()
        }
        .onChange(of: settings.voisonaTalkBaseURL) {
            resetLocalAPIVoices()
        }
        .onChange(of: voisonaTalkCredential) {
            SpeechCredentialStore.save(voisonaTalkCredential, scope: scope)
            resetLocalAPIVoices()
        }
        .onChange(of: openAICredential) {
            SpeechCredentialStore.save(openAICredential, provider: .openAI, scope: scope)
        }
        .onChange(of: openAICompatibleLocalCredential) {
            SpeechCredentialStore.save(
                openAICompatibleLocalCredential,
                provider: .openAICompatibleLocal,
                scope: scope
            )
        }
        .onChange(of: elevenLabsCredential) {
            SpeechCredentialStore.save(elevenLabsCredential, provider: .elevenLabs, scope: scope)
            resetLocalAPIVoices()
        }
        .onChange(of: aivisCloudCredential) {
            SpeechCredentialStore.save(aivisCloudCredential, provider: .aivisCloud, scope: scope)
        }
    }

    private var openAIModel: Binding<String> {
        settings.provider == .openAI ? $settings.openAIModel : $settings.openAICompatibleLocalModel
    }

    private var openAIModelPlaceholder: String {
        settings.provider == .openAI ? "gpt-4o-mini-tts" : "irodori-tts"
    }

    private var openAIAPIKey: Binding<String> {
        settings.provider == .openAI ? $openAICredential.password : $openAICompatibleLocalCredential.password
    }

    private var openAIInstructions: Binding<String> {
        settings.provider == .openAI
            ? $settings.openAIInstructions
            : $settings.openAICompatibleLocalInstructions
    }

    private var externalServiceLocation: Binding<String> {
        Binding(
            get: {
                switch settings.provider {
                case .macOS, .voicevoxCompatible: settings.localAPIBaseURL
                case .coeiroink: settings.coeiroinkBaseURL
                case .voicepeak: settings.voicepeakExecutablePath
                case .voisonaTalk: settings.voisonaTalkBaseURL
                case .openAI: "https://api.openai.com/v1"
                case .openAICompatibleLocal: settings.openAICompatibleLocalBaseURL
                case .elevenLabs: "https://api.elevenlabs.io/v1"
                case .aivisCloud: "https://api.aivis-project.com/v1"
                }
            },
            set: { value in
                switch settings.provider {
                case .macOS, .voicevoxCompatible:
                    settings.localAPIBaseURL = value
                case .coeiroink:
                    settings.coeiroinkBaseURL = value
                case .voicepeak:
                    settings.voicepeakExecutablePath = value
                case .voisonaTalk:
                    settings.voisonaTalkBaseURL = value
                case .openAI:
                    break
                case .openAICompatibleLocal:
                    settings.openAICompatibleLocalBaseURL = value
                case .elevenLabs:
                    break
                case .aivisCloud:
                    break
                }
            }
        )
    }

    private var externalVoiceIdentifier: Binding<String> {
        Binding(
            get: {
                switch settings.provider {
                case .macOS, .voicevoxCompatible: settings.localAPIVoiceIdentifier
                case .coeiroink: settings.coeiroinkStyleIdentifier
                case .voicepeak: settings.voicepeakNarrator
                case .voisonaTalk: settings.voisonaTalkVoiceName
                case .openAI: settings.openAIVoice
                case .openAICompatibleLocal: settings.openAICompatibleLocalVoice
                case .elevenLabs: settings.elevenLabsVoiceID
                case .aivisCloud: settings.aivisCloudModelUUID
                }
            },
            set: { value in
                switch settings.provider {
                case .macOS, .voicevoxCompatible:
                    settings.localAPIVoiceIdentifier = value
                case .coeiroink:
                    settings.coeiroinkStyleIdentifier = value
                case .voicepeak:
                    settings.voicepeakNarrator = value
                case .voisonaTalk:
                    settings.voisonaTalkVoiceName = value
                case .openAI:
                    settings.openAIVoice = value
                case .openAICompatibleLocal:
                    settings.openAICompatibleLocalVoice = value
                case .elevenLabs:
                    settings.elevenLabsVoiceID = value
                case .aivisCloud:
                    settings.aivisCloudModelUUID = value
                }
            }
        )
    }

    private var externalVoiceSelection: Binding<String> {
        Binding(
            get: {
                switch settings.provider {
                case .coeiroink:
                    [settings.coeiroinkSpeakerUUID, settings.coeiroinkStyleIdentifier]
                        .joined(separator: ":")
                case .voisonaTalk:
                    [
                        settings.voisonaTalkVoiceVersion,
                        settings.voisonaTalkVoiceName,
                        settings.voisonaTalkLanguage
                    ].joined(separator: ":")
                default:
                    externalVoiceIdentifier.wrappedValue
                }
            },
            set: { id in
                guard let voice = localAPIVoices.first(where: { $0.id == id }) else { return }
                switch settings.provider {
                case .coeiroink:
                    settings.coeiroinkSpeakerUUID = voice.groupIdentifier ?? ""
                    settings.coeiroinkStyleIdentifier = voice.identifier
                case .macOS, .voicevoxCompatible:
                    settings.localAPIVoiceIdentifier = voice.identifier
                case .voicepeak:
                    settings.voicepeakNarrator = voice.identifier
                case .voisonaTalk:
                    settings.voisonaTalkVoiceName = voice.identifier
                    settings.voisonaTalkVoiceVersion = voice.groupIdentifier ?? ""
                    settings.voisonaTalkLanguage = voice.languageIdentifier ?? ""
                case .openAI:
                    settings.openAIVoice = voice.identifier
                case .openAICompatibleLocal:
                    settings.openAICompatibleLocalVoice = voice.identifier
                case .elevenLabs:
                    settings.elevenLabsVoiceID = voice.identifier
                case .aivisCloud:
                    settings.aivisCloudModelUUID = voice.identifier
                }
            }
        )
    }

    private var externalServicePlaceholder: String {
        switch settings.provider {
        case .macOS, .voicevoxCompatible: "http://127.0.0.1:50021"
        case .coeiroink: "http://127.0.0.1:50032"
        case .voicepeak: "/Applications/voicepeak.app/Contents/MacOS/voicepeak"
        case .voisonaTalk: "http://127.0.0.1:32766/api/talk/v1"
        case .openAI: "https://api.openai.com/v1"
        case .openAICompatibleLocal: "http://127.0.0.1:8088/v1"
        case .elevenLabs: "https://api.elevenlabs.io/v1"
        case .aivisCloud: "https://api.aivis-project.com/v1"
        }
    }

    private var externalVoiceIdentifierLabel: LocalizedStringKey {
        switch settings.provider {
        case .macOS, .voicevoxCompatible: "話者ID"
        case .coeiroink: "スタイルID"
        case .voicepeak: "ナレーター"
        case .voisonaTalk: "ボイス名"
        case .openAI: "声"
        case .openAICompatibleLocal: "声"
        case .elevenLabs: "話者ID"
        case .aivisCloud: "モデルUUID / アクセスキー"
        }
    }

    private var externalVoiceIdentifierPlaceholder: String {
        switch settings.provider {
        case .voicepeak: "Japanese Female 1"
        case .voisonaTalk: "voice-name_ja_JP"
        case .openAI: "marin"
        case .openAICompatibleLocal: "none"
        case .elevenLabs: "voice_id"
        case .aivisCloud: "model_uuid / ak_…"
        default: "0"
        }
    }

    private func resetLocalAPIVoices() {
        localAPIVoices = []
        localAPIVoiceCount = nil
        localAPIError = nil
    }

    private func loadLocalAPIVoices() async {
        loadsLocalAPIVoices = true
        localAPIError = nil
        localAPIVoiceCount = nil
        defer { loadsLocalAPIVoices = false }
        do {
            let voices = switch settings.provider {
            case .macOS: [SpeechSynthesisVoice]()
            case .voicevoxCompatible:
                try await VoicevoxEngineClient().voices(serviceURL: externalServiceURL())
            case .coeiroink:
                try await CoeiroinkEngineClient().voices(serviceURL: externalServiceURL())
            case .voicepeak:
                try await VoicepeakEngineClient().voices(
                    executableURL: URL(fileURLWithPath: settings.voicepeakExecutablePath)
                )
            case .voisonaTalk:
                try await VoiSonaTalkEngineClient().voices(
                    serviceURL: externalServiceURL(),
                    credential: voisonaTalkCredential
                )
            case .openAI:
                [SpeechSynthesisVoice]()
            case .openAICompatibleLocal:
                [SpeechSynthesisVoice]()
            case .elevenLabs:
                try await ElevenLabsEngineClient().voices(scope: scope)
            case .aivisCloud:
                [SpeechSynthesisVoice]()
            }
            localAPIVoices = voices
            localAPIVoiceCount = voices.count
        } catch {
            localAPIVoices = []
            localAPIError = error.localizedDescription
        }
    }

    private func externalServiceURL() throws -> URL {
        guard let url = URL(string: externalServiceLocation.wrappedValue) else {
            throw SpeechServiceError.invalidServiceURL
        }
        return url
    }

    private static let openAIVoices = [
        "alloy", "ash", "ballad", "coral", "echo", "fable", "onyx",
        "nova", "sage", "shimmer", "verse", "marin", "cedar"
    ]
}

private struct ContentSourcesSettingsView: View {
    @ObservedObject var store: ContentSourceStore
    @Binding var requiresRestart: Bool

    var body: some View {
        ForEach(ContentSourceKind.allCases) { kind in
            Section(kind.title) {
                let sources = store.orderedSources(for: kind)
                let enabledSources = sources.filter(\.isEnabled)
                if let installationSource = store.installationSource(for: kind) {
                    Picker("インストール先", selection: installationSourceBinding(
                        for: kind,
                        fallback: installationSource.id
                    )) {
                        ForEach(enabledSources) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                }
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 10) {
                            Toggle("", isOn: enabledBinding(for: source))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text(source.directory.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([source.directory])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Finderで表示")
                            Button {
                                store.move(
                                    kind: kind,
                                    fromOffsets: IndexSet(integer: index),
                                    toOffset: index - 1
                                )
                                requiresRestart = true
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("優先順位を上げる")
                            Button {
                                store.move(
                                    kind: kind,
                                    fromOffsets: IndexSet(integer: index),
                                    toOffset: index + 2
                                )
                                requiresRestart = true
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == sources.count - 1)
                            .help("優先順位を下げる")
                            Button(role: .destructive) {
                                store.remove(id: source.id)
                                requiresRestart = true
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(source.isBuiltIn)
                            .help(source.isBuiltIn ? "標準フォルダは削除できない" : "一覧から削除")
                        }
                        if kind == .ghost {
                            HStack(spacing: 18) {
                                Toggle("ランダム切り替えの対象", isOn: automaticSwitchingBinding(for: source))
                                Toggle("自動更新の対象", isOn: automaticUpdatesBinding(for: source))
                            }
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .padding(.leading, 26)
                            .disabled(!source.isEnabled)
                        }
                    }
                }
                Button("フォルダを追加…") {
                    addDirectory(for: kind)
                }
            }
        }
        Section {
            Text("上にあるフォルダほど優先される。同じフォルダ名のコンテンツが複数ある場合は、優先順位が高いほうだけを読み込む。フォルダを一覧から外しても、中のファイルは削除されない。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func enabledBinding(for source: ContentSource) -> Binding<Bool> {
        Binding(
            get: { store.sources.first(where: { $0.id == source.id })?.isEnabled ?? false },
            set: { isEnabled in
                var updated = source
                updated.isEnabled = isEnabled
                store.update(updated)
                requiresRestart = true
            }
        )
    }

    private func installationSourceBinding(for kind: ContentSourceKind, fallback: String) -> Binding<String> {
        Binding(
            get: { store.installationSource(for: kind)?.id ?? fallback },
            set: { store.setInstallationSource(id: $0, for: kind) }
        )
    }

    private func automaticSwitchingBinding(for source: ContentSource) -> Binding<Bool> {
        Binding(
            get: {
                store.sources.first(where: { $0.id == source.id })?.allowsAutomaticSwitching ?? true
            },
            set: { isAllowed in
                var updated = source
                updated.allowsAutomaticSwitching = isAllowed
                store.update(updated)
            }
        )
    }

    private func automaticUpdatesBinding(for source: ContentSource) -> Binding<Bool> {
        Binding(
            get: { store.sources.first(where: { $0.id == source.id })?.allowsAutomaticUpdates ?? true },
            set: { isAllowed in
                var updated = source
                updated.allowsAutomaticUpdates = isAllowed
                store.update(updated)
            }
        )
    }

    private func addDirectory(for kind: ContentSourceKind) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "追加")
        panel.message = String(localized: "読み込むコンテンツフォルダを選択")
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        _ = store.add(kind: kind, name: directory.lastPathComponent, directory: directory)
        requiresRestart = true
    }
}

private extension ContentSourceKind {
    var title: LocalizedStringKey {
        switch self {
        case .ghost: "ゴースト"
        case .balloon: "バルーン"
        case .headline: "ヘッドライン"
        case .plugin: "プラグイン"
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Divider()

            Form {
                content
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

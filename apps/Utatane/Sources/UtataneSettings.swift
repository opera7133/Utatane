import AppKit
import Sparkle
import SwiftUI
import UtataneAI
import UtataneBalloon
import UtataneNetwork

@MainActor
final class UtataneSettingsStore: ObservableObject {
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
        case ghost
        case talkAndBalloon
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
        static let appLanguage = "general.appLanguage"
        static let defaultBalloonDirectoryName = "general.defaultBalloonDirectoryName"
        static let characterDelayMilliseconds = "talk.characterDelayMilliseconds"
        static let randomTalkIntervalMinutes = "talk.randomTalkIntervalMinutes"
        static let dialogueDismissalSeconds = "balloon.dialogueDismissalSeconds"
        static let shellScalePercent = "display.shellScalePercent"
        static let balloonScalePercent = "display.balloonScalePercent"
        static let linksBalloonScale = "display.linksBalloonScale"
        static let balloonTextScalePercent = "display.balloonTextScalePercent"
        static let locksShellToDesktopBottom = "display.locksShellToDesktopBottom"
        static let keepsShellOnScreen = "display.keepsShellOnScreen"
        static let showsDebugWindow = "debug.showsWindow"
        static let wineExecutablePath = "windowsShiori.wineExecutablePath"
        static let winePrefixPath = "windowsShiori.winePrefixPath"
        static let aiProvider = "ai.provider"
        static let aiModel = "ai.model"
        static let aiBaseURL = "ai.baseURL"
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

    @Published var shellScalePercent: Int {
        didSet { saveGhostValue(shellScalePercent, kind: Key.shellScalePercent) }
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

    @Published var selectedPane: Pane = .general
    @Published private(set) var activeGhostName: String?

    private let defaults: UserDefaults
    private let launchedAppLanguage: AppLanguage
    private var activeGhostDirectoryName: String?
    private var isLoadingGhostSettings = false

    init(defaults: UserDefaults = .standard) {
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
        let loadedAppLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Key.appLanguage) ?? ""
        ) ?? .system
        appLanguage = loadedAppLanguage
        launchedAppLanguage = loadedAppLanguage
        defaultBalloonDirectoryName = defaults.string(forKey: Key.defaultBalloonDirectoryName) ?? ""
        characterDelayMilliseconds = defaults.object(forKey: Key.characterDelayMilliseconds) == nil
            ? 50 : defaults.integer(forKey: Key.characterDelayMilliseconds)
        randomTalkIntervalMinutes = defaults.integer(forKey: Key.randomTalkIntervalMinutes)
        dialogueDismissalSeconds = Self.positiveValue(
            defaults.integer(forKey: Key.dialogueDismissalSeconds),
            fallback: 10
        )
        shellScalePercent = 100
        balloonScalePercent = 100
        linksBalloonScale = true
        balloonTextScalePercent = 100
        locksShellToDesktopBottom = true
        keepsShellOnScreen = true
        showsDebugWindow = defaults.bool(forKey: Key.showsDebugWindow)
        wineExecutablePath = defaults.string(forKey: Key.wineExecutablePath) ?? ""
        winePrefixPath = defaults.string(forKey: Key.winePrefixPath) ?? ""
        aiProvider = AIProviderKind(rawValue: defaults.string(forKey: Key.aiProvider) ?? "") ?? .openAICompatible
        aiModel = defaults.string(forKey: Key.aiModel) ?? "llama3.2"
        aiBaseURL = defaults.string(forKey: Key.aiBaseURL) ?? ""
        aiAPIKey = AIAPIKeyStore.load()
        Self.apply(appLanguage, to: defaults)
    }

    private static func apply(_ language: AppLanguage, to defaults: UserDefaults) {
        if let languageCode = language.languageCode {
            defaults.set([languageCode], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
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
    let headlinesDirectory: URL
    let balloonsDirectory: URL
    let appUpdater: SPUUpdater
    @State private var headlines: [InstalledHeadline] = []
    @State private var balloons: [BalloonDefinition] = []
    @State private var loadError: String?

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
            }
            .tabItem { Label("一般", systemImage: "gearshape") }
            .tag(UtataneSettingsStore.Pane.general)

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
                        ForEach([50, 75, 100, 125, 150, 200], id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    Toggle("バルーンをシェル倍率に連動", isOn: $settings.linksBalloonScale)
                    Picker("バルーン", selection: $settings.balloonScalePercent) {
                        ForEach([50, 75, 100, 125, 150, 200], id: \.self) { value in
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
                    Toggle("デバッグ画面を表示", isOn: $settings.showsDebugWindow)
                    Text("エラーや警告などのログ、クリック判定、再生操作を表示する。通常の利用では非表示でよい。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Windows互換モジュール") {
                    TextField("Wine実行ファイル", text: $settings.wineExecutablePath)
                    TextField("WINEPREFIX", text: $settings.winePrefixPath)
                    Text("MateriaのFIRSTと、config.txtで解析できないHEADLINE DLLに使用する。32-bit Windowsアプリを実行できるWineと、専用のprefixを指定する。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("詳細", systemImage: "wrench.and.screwdriver") }
            .tag(UtataneSettingsStore.Pane.advanced)
        }
        .frame(width: 560, height: 520)
        .task { reload() }
    }

    private func reload() {
        balloons = (try? BalloonLoader().loadInstalled(from: balloonsDirectory)) ?? []
        if !settings.defaultBalloonDirectoryName.isEmpty,
           !balloons.contains(where: {
               $0.directory.lastPathComponent == settings.defaultBalloonDirectoryName
           })
        {
            settings.defaultBalloonDirectoryName = ""
        }
        do {
            headlines = try HeadlineCatalog().load(from: headlinesDirectory)
            loadError = nil
        } catch {
            headlines = []
            loadError = error.localizedDescription
        }
    }

    private func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            guard error == nil else { return }
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
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

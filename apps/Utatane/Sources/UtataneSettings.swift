import SwiftUI
import UtataneNetwork

@MainActor
final class UtataneSettingsStore: ObservableObject {
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
        static let characterDelayMilliseconds = "talk.characterDelayMilliseconds"
        static let randomTalkIntervalMinutes = "talk.randomTalkIntervalMinutes"
        static let dialogueDismissalSeconds = "balloon.dialogueDismissalSeconds"
        static let showsDebugWindow = "debug.showsWindow"
        static let wineExecutablePath = "windowsShiori.wineExecutablePath"
        static let winePrefixPath = "windowsShiori.winePrefixPath"
    }

    @Published var automaticHeadlineRefresh: Bool {
        didSet { defaults.set(automaticHeadlineRefresh, forKey: Key.automaticHeadlineRefresh) }
    }
    @Published var headlineRefreshIntervalMinutes: Int {
        didSet { defaults.set(headlineRefreshIntervalMinutes, forKey: Key.headlineRefreshIntervalMinutes) }
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
    @Published var showsDebugWindow: Bool {
        didSet { defaults.set(showsDebugWindow, forKey: Key.showsDebugWindow) }
    }
    @Published var wineExecutablePath: String {
        didSet { defaults.set(wineExecutablePath, forKey: Key.wineExecutablePath) }
    }
    @Published var winePrefixPath: String {
        didSet { defaults.set(winePrefixPath, forKey: Key.winePrefixPath) }
    }
    @Published var selectedPane: Pane = .general
    @Published private(set) var activeGhostName: String?

    private let defaults: UserDefaults
    private var activeGhostDirectoryName: String?
    private var isLoadingGhostSettings = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticHeadlineRefresh = defaults.bool(forKey: Key.automaticHeadlineRefresh)
        headlineRefreshIntervalMinutes = Self.positiveValue(
            defaults.integer(forKey: Key.headlineRefreshIntervalMinutes),
            fallback: 60
        )
        characterDelayMilliseconds = defaults.object(forKey: Key.characterDelayMilliseconds) == nil
            ? 50 : defaults.integer(forKey: Key.characterDelayMilliseconds)
        randomTalkIntervalMinutes = defaults.integer(forKey: Key.randomTalkIntervalMinutes)
        dialogueDismissalSeconds = Self.positiveValue(
            defaults.integer(forKey: Key.dialogueDismissalSeconds),
            fallback: 10
        )
        showsDebugWindow = defaults.bool(forKey: Key.showsDebugWindow)
        wineExecutablePath = defaults.string(forKey: Key.wineExecutablePath) ?? ""
        winePrefixPath = defaults.string(forKey: Key.winePrefixPath) ?? ""
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
        isLoadingGhostSettings = false
    }

    private func ghostRandomTalkKey(_ directoryName: String) -> String {
        "talk.randomTalkIntervalMinutes.\(directoryName)"
    }
}

struct UtataneSettingsView: View {
    @ObservedObject var settings: UtataneSettingsStore
    let headlinesDirectory: URL
    @State private var headlines: [InstalledHeadline] = []
    @State private var loadError: String?

    var body: some View {
        TabView(selection: $settings.selectedPane) {
            SettingsPage(
                title: "一般",
                description: "Utatane全体の基本設定。"
            ) {
                Section("起動と操作") {
                    Text("Shell、バルーン、キャラクター位置は、最後に使った状態がゴーストごとに復元される。")
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("一般", systemImage: "gearshape") }
            .tag(UtataneSettingsStore.Pane.general)

            SettingsPage(
                title: "ゴーストごとの設定",
                description: settings.activeGhostName.map { "「\($0)」にだけ適用する設定。" }
                    ?? "現在表示しているゴーストにだけ適用する設定。"
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
                    Text("ゴースト一覧、クリック判定、再生操作を表示する。通常の利用では非表示でよい。")
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
        .frame(width: 540, height: 440)
        .task { reload() }
    }

    private func reload() {
        do {
            headlines = try HeadlineCatalog().load(from: headlinesDirectory)
            loadError = nil
        } catch {
            headlines = []
            loadError = error.localizedDescription
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
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

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

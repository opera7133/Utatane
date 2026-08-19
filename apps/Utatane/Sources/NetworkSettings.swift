import SwiftUI
import UtataneNetwork

@MainActor
final class NetworkSettingsStore: ObservableObject {
    private enum Key {
        static let automaticHeadlineRefresh = "network.automaticHeadlineRefresh"
        static let headlineRefreshIntervalMinutes = "network.headlineRefreshIntervalMinutes"
    }

    @Published var automaticHeadlineRefresh: Bool {
        didSet { defaults.set(automaticHeadlineRefresh, forKey: Key.automaticHeadlineRefresh) }
    }

    @Published var headlineRefreshIntervalMinutes: Int {
        didSet { defaults.set(headlineRefreshIntervalMinutes, forKey: Key.headlineRefreshIntervalMinutes) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticHeadlineRefresh = defaults.bool(forKey: Key.automaticHeadlineRefresh)
        let savedInterval = defaults.integer(forKey: Key.headlineRefreshIntervalMinutes)
        headlineRefreshIntervalMinutes = savedInterval > 0 ? savedInterval : 60
    }
}

struct UtataneSettingsView: View {
    @ObservedObject var settings: NetworkSettingsStore
    let headlinesDirectory: URL
    @State private var headlines: [InstalledHeadline] = []
    @State private var loadError: String?

    var body: some View {
        Form {
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

                if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else if headlines.isEmpty {
                    Text("インストール済み項目はない")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(headlines) { headline in
                        HStack {
                            Text(headline.name)
                            Spacer()
                            Text(kindLabel(headline.kind))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
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

    private func kindLabel(_ kind: InstalledHeadline.Kind) -> String {
        switch kind {
        case .rss: "RSS / Atom"
        case .legacyDLL: "HEADLINE DLL（未対応）"
        }
    }
}

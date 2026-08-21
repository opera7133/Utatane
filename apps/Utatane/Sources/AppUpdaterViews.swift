import Combine
import Sparkle
import SwiftUI

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("アップデートを確認…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

struct AppUpdateSettingsView: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        Section("Utataneのアップデート") {
            Toggle("自動的にアップデートを確認", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, enabled in
                    updater.automaticallyChecksForUpdates = enabled
                }
            Toggle("アップデートを自動的にダウンロード", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, enabled in
                    updater.automaticallyDownloadsUpdates = enabled
                }
            Button("今すぐ確認", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

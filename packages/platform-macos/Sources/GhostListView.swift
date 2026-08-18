import SwiftUI

public struct GhostListView: View {
    private let model: GhostListModel
    @Binding private var selection: URL?

    public init(model: GhostListModel, selection: Binding<URL?>) {
        self.model = model
        _selection = selection
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "読み込めなかった",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if model.ghosts.isEmpty {
                    ContentUnavailableView(
                        "ゴーストがいない",
                        systemImage: "moon.zzz",
                        description: Text("Ghost フォルダに追加するとここに表示される。")
                    )
                } else {
                    List(model.ghosts, selection: $selection) { ghost in
                        Text(ghost.name)
                            .tag(ghost.id)
                    }
                }
            }
            .navigationTitle("Utatane")
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

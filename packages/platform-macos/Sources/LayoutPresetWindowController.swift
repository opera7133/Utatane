import AppKit
import SwiftUI

@MainActor
public final class LayoutPresetWindowController: NSWindowController {
    public init(
        store: LayoutPresetStore, canCapture: Bool,
        capture: @escaping (String, UUID?) -> Void, restore: @escaping (LayoutPreset) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = String(localized: "配置プリセット")
        window.contentView = NSHostingView(rootView: LayoutPresetView(
            store: store, canCapture: canCapture, capture: capture, restore: restore
        ))
        window.minSize = NSSize(width: 580, height: 380)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct LayoutPresetView: View {
    @ObservedObject var store: LayoutPresetStore
    let canCapture: Bool
    let capture: (String, UUID?) -> Void
    let restore: (LayoutPreset) -> Void
    @State private var selectedID: UUID?
    @State private var name = ""

    private var selected: LayoutPreset? {
        store.presets.first { $0.id == selectedID }
    }

    private var hasName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("起動するゴースト、シェル、バルーン、倍率と表示位置を保存します。")
                .foregroundStyle(.secondary)
            List(selection: $selectedID) {
                ForEach(store.presets) { preset in
                    VStack(alignment: .leading) {
                        Text(verbatim: preset.name)
                        Text(verbatim: preset.ghosts.map { URL(filePath: $0.ghostPath).lastPathComponent }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(preset.id)
                }
            }
            .overlay {
                if store.presets.isEmpty {
                    Text("保存したプリセットはありません。")
                }
            }
            .onChange(of: selectedID) { _, _ in name = selected?.name ?? "" }
            TextField("名前", text: $name)
            HStack {
                Button("現在の配置を保存") { capture(name, nil) }
                    .disabled(!canCapture || !hasName)
                Button("現在の配置で上書き") {
                    guard let selected else { return }
                    capture(name, selected.id)
                }
                .disabled(!canCapture || !hasName || selected == nil)
                Spacer()
                Button("名前を変更") {
                    guard let selectedID else { return }
                    store.rename(selectedID, to: name)
                }
                .disabled(!hasName || selected == nil)
            }
            HStack {
                Button("削除") {
                    guard let selectedID else { return }
                    store.remove(selectedID)
                    self.selectedID = nil
                }
                .disabled(selected == nil)
                Spacer()
                Button("配置を復元") {
                    guard let selected else { return }
                    restore(selected)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
            Text("復元すると、現在のゴースト一式を保存した構成に切り替えます。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

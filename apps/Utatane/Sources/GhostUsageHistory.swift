import AppKit
import SwiftUI
import UtataneCore

@MainActor enum GhostUsageHistory {
    static let store = GhostUsageStore(fileURL: ContentRoot.contentDirectory.appending(path: "State/ghost-usage.json"))
    static func identity(_ ghost: InstalledGhost) -> GhostUsageIdentity {
        .init(id: ghost.rootDirectory.path, name: ghost.name, sakuraName: ghost.characterName(for: 0) ?? ghost.name, keroName: ghost.characterName(for: 1) ?? "")
    }

    static func references(_ ghosts: [InstalledGhost]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: store.rows(installed: ghosts.map(identity)).enumerated().map { ($0.offset, $0.element.shioriValue) })
    }
}

@MainActor final class GhostUsageWindowController: NSWindowController {
    init() {
        super.init(window: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        nil
    }

    func show(ghosts: [InstalledGhost]) {
        let rows = GhostUsageHistory.store.rows(installed: ghosts.map(GhostUsageHistory.identity))
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.identity.id) { row in
                    VStack(alignment: .leading) {
                        Text(row.identity.name)
                        ProgressView(value: row.percent, total: 100)
                        Text("\(row.boots)回 · \(Int(row.seconds / 60))分 · \(row.percent, specifier: "%.1f")%")
                            .font(.caption)
                        Text("7日: \(row.weeklyBoots)回 / \(Int(row.weeklySeconds / 60))分　30日: \(row.monthlyBoots)回 / \(Int(row.monthlySeconds / 60))分")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }
        if window == nil {
            window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window?.title = "使ってるぞグラフ"
            window?.setContentSize(NSSize(width: 520, height: 420))
            window?.styleMask = [.titled, .closable, .resizable]
            window?.isReleasedWhenClosed = false
        } else {
            window?.contentViewController = NSHostingController(rootView: content)
        }
        showWindow(nil)
    }
}

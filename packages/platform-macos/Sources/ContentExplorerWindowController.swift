import AppKit
import Observation
import SwiftUI

public enum ContentExplorerKind: String, CaseIterable, Identifiable, Sendable {
    case ghost
    case shell
    case balloon
    case headline
    case plugin

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .ghost: "ゴースト"
        case .shell: "シェル"
        case .balloon: "バルーン"
        case .headline: "ヘッドライン"
        case .plugin: "プラグイン"
        }
    }

    var systemImage: String {
        switch self {
        case .ghost: "person.crop.rectangle.stack"
        case .shell: "person.crop.artframe"
        case .balloon: "bubble.left.and.bubble.right"
        case .headline: "newspaper"
        case .plugin: "puzzlepiece.extension"
        }
    }
}

public struct ContentExplorerEntry: Identifiable, Sendable, Equatable {
    public let kind: ContentExplorerKind
    public let name: String
    public let detail: String?
    public let directory: URL
    public let parentDirectory: URL?
    public let readmeURL: URL?
    public let homeURL: URL?
    public let removalContainer: URL?
    public let isActive: Bool
    public let canActivate: Bool

    public var id: String {
        "\(kind.rawValue):\(directory.standardizedFileURL.path)"
    }

    public init(
        kind: ContentExplorerKind,
        name: String,
        detail: String? = nil,
        directory: URL,
        parentDirectory: URL? = nil,
        readmeURL: URL? = nil,
        homeURL: URL? = nil,
        removalContainer: URL? = nil,
        isActive: Bool = false,
        canActivate: Bool = true
    ) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.directory = directory
        self.parentDirectory = parentDirectory
        self.readmeURL = readmeURL
        self.homeURL = homeURL
        self.removalContainer = removalContainer
        self.isActive = isActive
        self.canActivate = canActivate
    }

    var activationTitle: String {
        switch kind {
        case .ghost: "起動"
        case .shell, .balloon: "切り替え"
        case .headline, .plugin: "実行"
        }
    }
}

@MainActor
@Observable
final class ContentExplorerModel {
    var entries: [ContentExplorerEntry] = []
    var selectedKind: ContentExplorerKind = .ghost
    var searchText = ""
    var selection: String?
    var onActivate: (@MainActor @Sendable (ContentExplorerEntry) -> Void)?
    var onRemove: (@MainActor @Sendable (ContentExplorerEntry) -> Void)?

    var filteredEntries: [ContentExplorerEntry] {
        entries.filter { entry in
            guard entry.kind == selectedKind else { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return entry.name.lowercased().contains(query)
                || (entry.detail?.lowercased().contains(query) ?? false)
                || entry.directory.lastPathComponent.lowercased().contains(query)
        }
    }

    var selectedEntry: ContentExplorerEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    func update(
        entries: [ContentExplorerEntry],
        preferredKind: ContentExplorerKind? = nil
    ) {
        self.entries = entries
        if let preferredKind {
            selectedKind = preferredKind
        }
        if !entries.contains(where: { $0.kind == selectedKind }),
           let availableKind = ContentExplorerKind.allCases.first(where: { kind in
               entries.contains { $0.kind == kind }
           })
        {
            selectedKind = availableKind
        }
        if selectedEntry == nil || selectedEntry?.kind != selectedKind {
            selection = filteredEntries.first?.id
        }
    }
}

@MainActor
public final class ContentExplorerWindowController: NSObject, NSWindowDelegate {
    static let initialContentSize = NSSize(width: 1120, height: 720)
    static let minimumContentSize = NSSize(width: 760, height: 500)

    private let model = ContentExplorerModel()
    private var window: NSWindow?

    public var isVisible: Bool {
        window?.isVisible == true
    }

    var contentSize: NSSize? {
        window?.contentView?.bounds.size
    }

    override public init() {
        super.init()
    }

    public func show(
        entries: [ContentExplorerEntry],
        preferredKind: ContentExplorerKind? = nil,
        onActivate: @escaping @MainActor @Sendable (ContentExplorerEntry) -> Void,
        onRemove: @escaping @MainActor @Sendable (ContentExplorerEntry) -> Void
    ) {
        model.onActivate = onActivate
        model.onRemove = onRemove
        model.update(entries: entries, preferredKind: preferredKind)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "エクスプローラ"
        let hostingController = NSHostingController(rootView: ContentExplorerView(model: model))
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = Self.minimumContentSize
        panel.setContentSize(Self.initialContentSize)
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = panel
    }

    public func update(entries: [ContentExplorerEntry]) {
        guard window != nil else { return }
        model.update(entries: entries)
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_: Notification) {
        window = nil
    }
}

private struct ContentExplorerView: View {
    let model: ContentExplorerModel

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("種類", selection: $model.selectedKind) {
                    ForEach(ContentExplorerKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.selectedKind) { _, _ in
                    model.selection = model.filteredEntries.first?.id
                }

                TextField("検索", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 230)
                    .onChange(of: model.searchText) { _, _ in
                        if !model.filteredEntries.contains(where: { $0.id == model.selection }) {
                            model.selection = model.filteredEntries.first?.id
                        }
                    }
            }
            .padding(12)

            Divider()

            HSplitView {
                Group {
                    if model.filteredEntries.isEmpty {
                        ContentUnavailableView.search(text: model.searchText)
                    } else {
                        List(model.filteredEntries, selection: $model.selection) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: entry.kind.systemImage)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                    if let detail = entry.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if entry.isActive {
                                    Text("使用中")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(entry.id)
                        }
                    }
                }
                .frame(minWidth: 310)

                detailView(model.selectedEntry)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func detailView(_ entry: ContentExplorerEntry?) -> some View {
        if let entry {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.kind.systemImage)
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.title2.weight(.semibold))
                        Text(entry.kind.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if let detail = entry.detail, !detail.isEmpty {
                    LabeledContent("詳細", value: detail)
                }
                LabeledContent("フォルダ", value: entry.directory.path)

                Spacer()

                HStack {
                    if entry.removalContainer != nil {
                        Button("削除…", role: .destructive) {
                            model.onRemove?(entry)
                        }
                    }
                    Button("Finderで表示") {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.directory])
                    }
                    if let readmeURL = entry.readmeURL {
                        Button("README") {
                            NSWorkspace.shared.open(readmeURL)
                        }
                    }
                    if let homeURL = entry.homeURL {
                        Button("配布元") {
                            NSWorkspace.shared.open(homeURL)
                        }
                    }
                    Spacer()
                    Button(entry.activationTitle) {
                        model.onActivate?(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.canActivate || entry.isActive)
                }
            }
            .padding(20)
        } else {
            ContentUnavailableView(
                "項目を選んで",
                systemImage: "sidebar.left",
                description: Text("一覧からコンテンツを選ぶと詳細を表示する。")
            )
        }
    }
}

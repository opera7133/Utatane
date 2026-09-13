import AppKit
import Observation
import SwiftUI
import UtataneContentValidator

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
    public let websiteURL: URL?
    public let updateURL: URL?
    public let removalContainer: URL?
    public let isActive: Bool
    public let canActivate: Bool
    public let canUpdate: Bool
    public let resolvesUpdateURLDynamically: Bool

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
        websiteURL: URL? = nil,
        updateURL: URL? = nil,
        removalContainer: URL? = nil,
        isActive: Bool = false,
        canActivate: Bool = true,
        canUpdate: Bool = true,
        resolvesUpdateURLDynamically: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.directory = directory
        self.parentDirectory = parentDirectory
        self.readmeURL = readmeURL
        self.websiteURL = websiteURL
        self.updateURL = updateURL
        self.removalContainer = removalContainer
        self.isActive = isActive
        self.canActivate = canActivate
        self.canUpdate = canUpdate
        self.resolvesUpdateURLDynamically = resolvesUpdateURLDynamically
    }

    var activationTitle: String {
        switch kind {
        case .ghost: "起動"
        case .shell, .balloon: "切り替え"
        case .headline, .plugin: "実行"
        }
    }

    public var hasUpdateAction: Bool {
        updateURL != nil || resolvesUpdateURLDynamically
    }
}

@MainActor
@Observable
final class ContentExplorerModel {
    var entries: [ContentExplorerEntry] = []
    var selectedKind: ContentExplorerKind = .ghost
    var searchText = ""
    var selection: Set<String> = []
    var updateStatus: String?
    var isUpdating = false
    var validatingEntryIDs: Set<String> = []
    var validationReports: [String: ContentValidationReport] = [:]
    var onActivate: (@MainActor @Sendable (ContentExplorerEntry) -> Void)?
    var onCheckUpdate: (@MainActor @Sendable (ContentExplorerEntry) -> Void)?
    var onUpdate: (@MainActor @Sendable (ContentExplorerEntry) -> Void)?
    var onCheckUpdates: (@MainActor @Sendable ([ContentExplorerEntry]) -> Void)?
    var onUpdateEntries: (@MainActor @Sendable ([ContentExplorerEntry]) -> Void)?
    var onRepairEntries: (@MainActor @Sendable ([ContentExplorerEntry]) -> Void)?
    var onCancelUpdate: (@MainActor @Sendable () -> Void)?
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
        guard selection.count == 1, let selectedID = selection.first else { return nil }
        return entries.first { $0.id == selectedID }
    }

    var selectedEntries: [ContentExplorerEntry] {
        filteredEntries.filter { selection.contains($0.id) }
    }

    var visibleUpdateEntries: [ContentExplorerEntry] {
        filteredEntries.filter(\.hasUpdateAction)
    }

    var selectedUpdateEntries: [ContentExplorerEntry] {
        selectedEntries.filter(\.hasUpdateAction)
    }

    func validate(_ entry: ContentExplorerEntry) {
        guard entry.kind == .ghost, !validatingEntryIDs.contains(entry.id) else { return }
        validatingEntryIDs.insert(entry.id)
        Task { @MainActor in
            let report = await Task.detached {
                ContentValidator().validate(ghostRoot: entry.directory)
            }.value
            validationReports[entry.id] = report
            validatingEntryIDs.remove(entry.id)
        }
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
        selection.formIntersection(Set(entries.map(\.id)))
        if selectedEntries.isEmpty {
            selection = Set(filteredEntries.first.map { [$0.id] } ?? [])
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
        onCheckUpdate: @escaping @MainActor @Sendable (ContentExplorerEntry) -> Void,
        onUpdate: @escaping @MainActor @Sendable (ContentExplorerEntry) -> Void,
        onCheckUpdates: (@MainActor @Sendable ([ContentExplorerEntry]) -> Void)? = nil,
        onUpdateEntries: (@MainActor @Sendable ([ContentExplorerEntry]) -> Void)? = nil,
        onRepairEntries: (@MainActor @Sendable ([ContentExplorerEntry]) -> Void)? = nil,
        onCancelUpdate: (@MainActor @Sendable () -> Void)? = nil,
        onRemove: @escaping @MainActor @Sendable (ContentExplorerEntry) -> Void
    ) {
        model.onActivate = onActivate
        model.onCheckUpdate = onCheckUpdate
        model.onUpdate = onUpdate
        model.onCheckUpdates = onCheckUpdates
        model.onUpdateEntries = onUpdateEntries
        model.onRepairEntries = onRepairEntries
        model.onCancelUpdate = onCancelUpdate
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

    public func setUpdateState(isUpdating: Bool, status: String? = nil) {
        model.isUpdating = isUpdating
        model.updateStatus = status
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
                    model.selection = Set(model.filteredEntries.first.map { [$0.id] } ?? [])
                }

                TextField("検索", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 230)
                    .onChange(of: model.searchText) { _, _ in
                        if model.selectedEntries.isEmpty {
                            model.selection = Set(model.filteredEntries.first.map { [$0.id] } ?? [])
                        }
                    }
            }
            .padding(12)

            Divider()

            if !model.visibleUpdateEntries.isEmpty {
                HStack(spacing: 10) {
                    Text("⌘クリックで複数選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isUpdating {
                        if let updateStatus = model.updateStatus {
                            Text(updateStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Button("中止") {
                            model.onCancelUpdate?()
                        }
                    } else {
                        Menu("一括操作") {
                            if !model.selectedUpdateEntries.isEmpty {
                                Button("選択項目の更新を確認") {
                                    model.onCheckUpdates?(model.selectedUpdateEntries)
                                }
                                Button("選択項目を更新") {
                                    model.onUpdateEntries?(model.selectedUpdateEntries)
                                }
                                Button("選択項目を修復") {
                                    model.onRepairEntries?(model.selectedUpdateEntries)
                                }
                                Divider()
                            }
                            Button("表示中の全項目の更新を確認") {
                                model.onCheckUpdates?(model.visibleUpdateEntries)
                            }
                            Button("表示中の全項目を更新") {
                                model.onUpdateEntries?(model.visibleUpdateEntries)
                            }
                            Button("表示中の全項目を修復") {
                                model.onRepairEntries?(model.visibleUpdateEntries)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

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

                detailView(model.selectedEntries)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func detailView(_ entries: [ContentExplorerEntry]) -> some View {
        if entries.count == 1, let entry = entries.first {
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

                if entry.kind == .ghost {
                    validationView(entry)
                }

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
                    if let websiteURL = entry.websiteURL {
                        Button("配布元") {
                            NSWorkspace.shared.open(websiteURL)
                        }
                    }
                    if entry.kind == .ghost {
                        Button(
                            model.validationReports[entry.id] == nil
                                ? String(localized: "互換性を検査")
                                : String(localized: "再検査")
                        ) {
                            model.validate(entry)
                        }
                        .disabled(model.validatingEntryIDs.contains(entry.id))
                    }
                    Spacer()
                    if entry.hasUpdateAction {
                        Menu("更新") {
                            Button("更新を確認") {
                                model.onCheckUpdate?(entry)
                            }
                            Button("更新を実行") {
                                model.onUpdate?(entry)
                            }
                            .disabled(!entry.canUpdate)
                        }
                    }
                    Button(entry.activationTitle) {
                        model.onActivate?(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.canActivate || entry.isActive)
                }
            }
            .padding(20)
        } else if entries.count > 1 {
            ContentUnavailableView(
                "\(entries.count)項目を選択中",
                systemImage: "checklist",
                description: Text("上の一括操作から確認、更新、修復ができる。")
            )
        } else {
            ContentUnavailableView(
                "項目を選んで",
                systemImage: "sidebar.left",
                description: Text("一覧からコンテンツを選ぶと詳細を表示する。")
            )
        }
    }

    @ViewBuilder
    private func validationView(_ entry: ContentExplorerEntry) -> some View {
        if model.validatingEntryIDs.contains(entry.id) {
            HStack {
                ProgressView().controlSize(.small)
                Text("互換性を検査中…").foregroundStyle(.secondary)
            }
        } else if let report = model.validationReports[entry.id] {
            GroupBox("互換性診断") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("エラー \(report.errorCount)件、警告 \(report.warningCount)件")
                        .font(.headline)
                    if report.diagnostics.isEmpty {
                        Label("既知の問題は見つからなかった", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: diagnostic.severity == .error
                                            ? "xmark.octagon.fill"
                                            : "exclamationmark.triangle.fill")
                                            .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(diagnostic.message)
                                            Text(diagnostic.line.map { "\(diagnostic.path):\($0)" } ?? diagnostic.path)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

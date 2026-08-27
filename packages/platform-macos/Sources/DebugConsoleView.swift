import AppKit
import SwiftUI
import UtataneCore

public struct DeveloperSurfaceTestItem: Identifiable, Sendable, Equatable {
    public struct Animation: Identifiable, Sendable, Equatable {
        public let id: Int
        public let name: String?

        public init(id: Int, name: String?) {
            self.id = id
            self.name = name
        }
    }

    public struct Collision: Identifiable, Sendable, Equatable {
        public let id: Int
        public let name: String

        public init(id: Int, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let id: Int
    public let name: String?
    public let animations: [Animation]
    public let collisions: [Collision]

    public init(id: Int, name: String?, animations: [Animation], collisions: [Collision]) {
        self.id = id
        self.name = name
        self.animations = animations
        self.collisions = collisions
    }
}

public struct DebugConsoleView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case logs = "ログ"
        case tools = "開発ツール"

        var id: String {
            rawValue
        }
    }

    public enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "すべて"
        case errorOnly = "エラーのみ"
        case warningAndError = "警告以上"
        case infoAndAbove = "情報以上"
        case debug = "デバッグ"

        public var id: String {
            rawValue
        }

        public func matches(_ level: LogLevel) -> Bool {
            switch self {
            case .all: true
            case .errorOnly: level == .error
            case .warningAndError: level >= .warning
            case .infoAndAbove: level >= .info
            case .debug: level == .debug
            }
        }
    }

    private let model: GhostListModel
    @Binding private var selectedGhostID: URL?
    private let lastClickedRegion: String?
    private let isSessionAvailable: Bool
    private let isReloadDisabled: Bool
    private let onPlayRandomTalk: () -> Void
    private let onAdvanceScript: () -> Void
    private let onCancelScript: () -> Void
    private let onReloadGhost: () -> Void
    private let onInstallNar: () -> Void
    private let onPlaySlowAnimation: () -> Void
    private let onExecuteScript: (String) -> Void
    private let onSetCollisionMode: (Bool, Bool) -> Void
    private let onShowBalloonTest: () -> Void
    private let surfaces: [DeveloperSurfaceTestItem]
    private let onSelectSurface: (Int, Int) -> Void
    private let onPlayAnimation: (Int, Int) -> Void
    private let serikoInspectorSnapshots: @MainActor () -> [SERIKOInspectorSnapshot]

    @ObservedObject private var logStore: AppLogStore
    @State private var levelFilter: LevelFilter = .all
    @State private var selectedCategory: String = "すべて"
    @State private var searchText = ""
    @State private var selectedEntryID: UUID?
    @State private var isCopiedNotification = false
    @State private var pane: Pane = .logs
    @State private var scriptInput = #"\0テスト\e"#
    @State private var showsCollisions = false
    @State private var showsCollisionNames = true
    @State private var testScope = 0
    @State private var selectedSurfaceID: Int?

    public init(
        model: GhostListModel,
        selectedGhostID: Binding<URL?>,
        lastClickedRegion: String?,
        isSessionAvailable: Bool,
        isReloadDisabled: Bool,
        onPlayRandomTalk: @escaping () -> Void,
        onAdvanceScript: @escaping () -> Void,
        onCancelScript: @escaping () -> Void,
        onReloadGhost: @escaping () -> Void,
        onInstallNar: @escaping () -> Void,
        onPlaySlowAnimation: @escaping () -> Void,
        onExecuteScript: @escaping (String) -> Void,
        onSetCollisionMode: @escaping (Bool, Bool) -> Void,
        onShowBalloonTest: @escaping () -> Void,
        surfaces: [DeveloperSurfaceTestItem],
        onSelectSurface: @escaping (Int, Int) -> Void,
        onPlayAnimation: @escaping (Int, Int) -> Void,
        serikoInspectorSnapshots: @escaping @MainActor () -> [SERIKOInspectorSnapshot],
        logStore: AppLogStore = .shared
    ) {
        self.model = model
        _selectedGhostID = selectedGhostID
        self.lastClickedRegion = lastClickedRegion
        self.isSessionAvailable = isSessionAvailable
        self.isReloadDisabled = isReloadDisabled
        self.onPlayRandomTalk = onPlayRandomTalk
        self.onAdvanceScript = onAdvanceScript
        self.onCancelScript = onCancelScript
        self.onReloadGhost = onReloadGhost
        self.onInstallNar = onInstallNar
        self.onPlaySlowAnimation = onPlaySlowAnimation
        self.onExecuteScript = onExecuteScript
        self.onSetCollisionMode = onSetCollisionMode
        self.onShowBalloonTest = onShowBalloonTest
        self.surfaces = surfaces
        self.onSelectSurface = onSelectSurface
        self.onPlayAnimation = onPlayAnimation
        self.serikoInspectorSnapshots = serikoInspectorSnapshots
        self.logStore = logStore
    }

    private var availableCategories: [String] {
        let set = Set(logStore.entries.map(\.category))
        return ["すべて"] + Array(set).sorted()
    }

    private var filteredEntries: [LogEntry] {
        logStore.entries.filter { entry in
            guard levelFilter.matches(entry.level) else { return false }
            if selectedCategory != "すべて", entry.category != selectedCategory {
                return false
            }
            if !searchText.isEmpty {
                let lower = searchText.lowercased()
                let matchMessage = entry.message.lowercased().contains(lower)
                let matchDetails = entry.details?.lowercased().contains(lower) ?? false
                let matchCategory = entry.category.lowercased().contains(lower)
                let matchGhost = entry.ghostName?.lowercased().contains(lower) ?? false
                guard matchMessage || matchDetails || matchCategory || matchGhost else { return false }
            }
            return true
        }
    }

    private var selectedEntry: LogEntry? {
        if let selectedEntryID {
            return logStore.entries.first(where: { $0.id == selectedEntryID })
        }
        return nil
    }

    private var errorCount: Int {
        logStore.entries.filter { $0.level == .error }.count
    }

    private var warningCount: Int {
        logStore.entries.filter { $0.level == .warning }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerControls
            Divider()
            Picker("表示", selection: $pane) {
                ForEach(Pane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if pane == .logs {
                filterBar
                Divider()
                logContentArea
            } else {
                developerTools
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var developerTools: some View {
        Form {
            Section("表示テスト") {
                Toggle("当たり判定を表示", isOn: $showsCollisions)
                    .onChange(of: showsCollisions) { _, value in
                        onSetCollisionMode(value, showsCollisionNames)
                    }
                Toggle("当たり判定名を表示", isOn: $showsCollisionNames)
                    .disabled(!showsCollisions)
                    .onChange(of: showsCollisionNames) { _, value in
                        onSetCollisionMode(showsCollisions, value)
                    }
                Button("バルーンテストを表示", action: onShowBalloonTest)
                Text("両スコープへ行数・桁数、リンク、番号、SSTPマーカー、スクロール矢印を確認するための内容を表示する。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("SakuraScript入力") {
                TextEditor(text: $scriptInput)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                HStack {
                    Spacer()
                    Button("実行") {
                        onExecuteScript(scriptInput)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scriptInput.isEmpty || !isSessionAvailable)
                }
                Text("SHIORI辞書の記法ではなく、実行するSakuraScriptを直接入力する。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("サーフィステスト") {
                Picker("スコープ", selection: $testScope) {
                    ForEach(0 ... 9, id: \.self) { scope in
                        Text("\\p[\(scope)]").tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: testScope) { _, scope in
                    guard let selectedSurfaceID else { return }
                    onSelectSurface(scope, selectedSurfaceID)
                }

                if surfaces.isEmpty {
                    Text("読み込まれているサーフィスはありません。")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        List(surfaces, selection: $selectedSurfaceID) { surface in
                            Text(surface.name.map { "surface\(surface.id) — \($0)" } ?? "surface\(surface.id)")
                                .tag(surface.id)
                        }
                        .frame(minWidth: 230, minHeight: 210)
                        .onChange(of: selectedSurfaceID) { _, id in
                            guard let id else { return }
                            onSelectSurface(testScope, id)
                        }

                        if let selectedSurface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Animation").font(.headline)
                                if selectedSurface.animations.isEmpty {
                                    Text("なし").foregroundStyle(.secondary)
                                } else {
                                    ForEach(selectedSurface.animations) { animation in
                                        Button(animation.name.map { "\(animation.id): \($0)" } ?? String(animation.id)) {
                                            onPlayAnimation(testScope, animation.id)
                                        }
                                        .buttonStyle(.link)
                                    }
                                }
                                Divider()
                                Text("Collision").font(.headline)
                                if selectedSurface.collisions.isEmpty {
                                    Text("なし").foregroundStyle(.secondary)
                                } else {
                                    ForEach(selectedSurface.collisions) { collision in
                                        Text("\(collision.id): \(collision.name)")
                                    }
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Section("SERIKO Inspector") {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let snapshots = serikoInspectorSnapshots()
                    if snapshots.isEmpty {
                        Text("表示中のサーフィスはありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshots) { snapshot in
                            serikoSnapshotView(snapshot)
                        }
                    }
                }
                Text("実行状態を0.5秒ごとに更新する読み取り専用Inspector。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("既存の開発操作") {
                Text("ゴーストの再読み込み、低速アニメーション、再生の進行・停止、ログ確認は上部の操作とログ画面から利用できる。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedSurface: DeveloperSurfaceTestItem? {
        guard let selectedSurfaceID else { return nil }
        return surfaces.first { $0.id == selectedSurfaceID }
    }

    private func serikoSnapshotView(_ snapshot: SERIKOInspectorSnapshot) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("\\p[\(snapshot.scope)] surface\(snapshot.surfaceID)")
                    .font(.headline.monospaced())
                Text(snapshot.isAnimating ? "実行中" : "待機中")
                    .foregroundStyle(snapshot.isAnimating ? .primary : .secondary)
            }
            GridRow {
                Text("Animation")
                Text(snapshot.currentAnimationID.map(String.init) ?? "—")
            }
            GridRow {
                Text("Persistent")
                Text(idList(snapshot.persistentAnimationIDs))
            }
            GridRow {
                Text("Paused")
                Text(idList(snapshot.pausedAnimationIDs))
            }
            GridRow {
                Text("Offset")
                Text(nonemptyOrDash(snapshot.animationOffsets.keys.sorted().map { id in
                    snapshot.animationOffsets[id].map { "\(id):(\($0.x),\($0.y))" } ?? "\(id):(0,0)"
                }.joined(separator: ", ")))
            }
            GridRow {
                Text("Lock")
                Text(verbatim: "repaint=\(snapshot.isRepaintLocked), movement=\(snapshot.isMovementLocked)")
            }
            GridRow {
                Text("Transform")
                Text(String(format: "alpha=%.2f, scale=(%.2f, %.2f)", snapshot.alpha, snapshot.scaleX, snapshot.scaleY))
            }
        }
        .font(.body.monospaced())
        .padding(.vertical, 4)
    }

    private func idList(_ ids: [Int]) -> String {
        nonemptyOrDash(ids.map(String.init).joined(separator: ", "))
    }

    private func nonemptyOrDash(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    // MARK: - Header Controls

    private var headerControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("👻 ゴースト:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedGhostID) {
                        Text("未選択").tag(nil as URL?)
                        ForEach(model.ghosts) { ghost in
                            Text(ghost.name).tag(ghost.id as URL?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("クリック判定:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(lastClickedRegion ?? "未検出")
                        .font(.subheadline.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack(spacing: 8) {
                Button(action: onPlayRandomTalk) {
                    Label("ランダムトーク", systemImage: "bubble.left.and.bubble.right")
                }
                .disabled(!isSessionAvailable)

                Button(action: onAdvanceScript) {
                    Label("進む", systemImage: "forward.fill")
                }

                Button(action: onCancelScript) {
                    Label("停止", systemImage: "stop.fill")
                }

                Button(action: onReloadGhost) {
                    Label("リロード", systemImage: "arrow.clockwise")
                }
                .disabled(isReloadDisabled)

                Button(action: onPlaySlowAnimation) {
                    Label("ゆっくり再生", systemImage: "tortoise")
                }

                Spacer()

                Button(action: onInstallNar) {
                    Label("NARインストール", systemImage: "square.and.arrow.down")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("レベル", selection: $levelFilter) {
                ForEach(LevelFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Picker("カテゴリ", selection: $selectedCategory) {
                ForEach(availableCategories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .frame(maxWidth: 130)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            Spacer()

            if errorCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("\(errorCount)")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.12), in: Capsule())
            }

            if warningCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(warningCount)")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.12), in: Capsule())
            }

            Button(action: copyAllFilteredLogs) {
                Label("コピー", systemImage: "doc.on.doc")
            }
            .help("表示中のログをクリップボードにコピー")

            Button(action: logStore.clear) {
                Label("消去", systemImage: "trash")
            }
            .help("ログを消去")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Log Content Area

    @ViewBuilder
    private var logContentArea: some View {
        if filteredEntries.isEmpty {
            ContentUnavailableView(
                "ログはありません",
                systemImage: "list.bullet.rectangle",
                description: Text(searchText.isEmpty && levelFilter == .all ? "エラーや警告、システムイベントがここに記録されます。" : "条件に一致するログが見つかりませんでした。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VSplitView {
                logTable
                    .frame(minHeight: 180)

                logDetailPane
                    .frame(minHeight: 120, maxHeight: 300)
            }
        }
    }

    // MARK: - Log Table

    private var logTable: some View {
        Table(filteredEntries, selection: $selectedEntryID) {
            TableColumn("レベル") { entry in
                HStack(spacing: 4) {
                    levelIcon(entry.level)
                    Text(entry.level.title)
                        .font(.caption.bold())
                        .foregroundStyle(levelColor(entry.level))
                }
            }
            .width(min: 75, ideal: 85, max: 95)

            TableColumn("時刻") { entry in
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 85, ideal: 95, max: 110)

            TableColumn("カテゴリ") { entry in
                Text(entry.category)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
            .width(min: 80, ideal: 90, max: 120)

            TableColumn("ゴースト") { entry in
                Text(entry.ghostName ?? "-")
                    .font(.caption)
                    .foregroundStyle(entry.ghostName != nil ? .primary : .secondary)
            }
            .width(min: 70, ideal: 90, max: 130)

            TableColumn("メッセージ") { entry in
                Text(entry.message)
                    .font(.body)
                    .lineLimit(1)
            }
            .width(min: 200, ideal: 400)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var logDetailPane: some View {
        if let entry = selectedEntry {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    levelIcon(entry.level)
                    Text("[\(entry.level.title)]")
                        .font(.headline)
                        .foregroundStyle(levelColor(entry.level))

                    Text("[\(entry.category)]")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let ghost = entry.ghostName {
                        Text("[\(ghost)]")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Text(Self.detailDateFormatter.string(from: entry.timestamp))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Button(action: { copyEntry(entry) }) {
                        Label("詳細をコピー", systemImage: "doc.on.doc")
                    }
                }

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.message)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let details = entry.details, !details.isEmpty {
                            Divider()
                            Text("詳細情報:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(details)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(8)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            VStack {
                Spacer()
                Text("ログ行を選択すると詳細が表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func levelIcon(_ level: LogLevel) -> some View {
        switch level {
        case .debug:
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: .secondary
        case .info: .blue
        case .warning: .yellow
        case .error: .red
        }
    }

    private func copyAllFilteredLogs() {
        let text = AppLogStore.formatText(for: filteredEntries)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyEntry(_ entry: LogEntry) {
        let text = AppLogStore.formatText(for: [entry])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}

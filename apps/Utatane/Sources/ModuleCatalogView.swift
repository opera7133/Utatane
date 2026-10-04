import Foundation
import SwiftUI
import UtataneCore
import UtataneModuleCatalog
import UtataneNetwork

struct ModuleCatalogCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("モジュール") {
            Button("モジュールカタログ…") { openWindow(id: "module-catalog") }
        }
    }
}

struct ModuleSetupOpening: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            guard ModuleCatalogConfiguration.requiresInitialSetup else { return }
            openWindow(id: "module-setup")
        }
    }
}

struct ModuleSetupCompletionListener: View {
    let onComplete: () -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .moduleCatalogSetupCompleted)) { _ in
                onComplete()
            }
    }
}

enum ModuleCatalogConfiguration {
    static let customIndexURLKey = "moduleCatalog.customIndexURL"
    static let customPublicKeyKey = "moduleCatalog.customPublicKey"

    static var requiresInitialSetup: Bool {
        !ModuleCatalogInventory().hasRequiredInitialModules
    }

    static var client: SignedModuleCatalogClient? {
        let defaults = UserDefaults.standard
        let customURL = defaults.string(forKey: customIndexURLKey)
        let customKey = defaults.string(forKey: customPublicKeyKey)
        let urlText = customURL ?? (Bundle.main.object(forInfoDictionaryKey: "ModuleCatalogIndexURL") as? String)
        let keyText = customKey ?? (Bundle.main.object(forInfoDictionaryKey: "ModuleCatalogPublicKey") as? String)
        guard let urlText, let keyText,
              let url = URL(string: urlText), validIndexURL(url),
              let key = Data(base64Encoded: keyText), key.count == 32
        else { return nil }
        let allowsStaging = customURL == nil && customKey == nil
            && (Bundle.main.object(forInfoDictionaryKey: "ModuleCatalogAllowStaging") as? Bool ?? false)
        return SignedModuleCatalogClient(indexURL: url, publicKey: key, allowsStaging: allowsStaging)
    }

    static func validIndexURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.lastPathComponent == "index.json"
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

struct ModuleCatalogView: View {
    enum Mode: Equatable {
        case catalog
        case settings
        case initialSelection
    }

    let mode: Mode
    var installedGhosts: [InstalledGhost] = []
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var catalog: SignedModuleCatalog?
    @State private var search = ""
    @State private var kind = "all"
    @State private var stateFilter = "all"
    @State private var selectedIDs: Set<String> = ["yaya-6", "satori"]
    @State private var installingIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var detailModule: SignedModuleCatalog.Module?
    @AppStorage(ModuleCatalogConfiguration.customIndexURLKey) private var customIndexURL = ""
    @AppStorage(ModuleCatalogConfiguration.customPublicKeyKey) private var customPublicKey = ""

    private var modules: [SignedModuleCatalog.Module] {
        (catalog?.modules ?? []).filter { module in
            let kindMatches = mode == .settings
                ? module.kinds.contains("shiori")
                : mode == .initialSelection || kind == "all" || module.kinds.contains(kind)
            let state = ModuleCatalogInventory().state(for: module)
            let stateMatches = mode != .catalog || stateFilter == "all"
                || (stateFilter == "installed" && state == .current)
                || (stateFilter == "available" && state == .notInstalled)
                || (stateFilter == "updates" && state == .updateAvailable)
            return kindMatches && stateMatches && (search.isEmpty || module.displayName.localizedStandardContains(search)
                || module.id.localizedStandardContains(search)
                || module.windowsFilenames.contains(where: { $0.localizedStandardContains(search) }))
        }.sorted { lhs, rhs in
            let inventory = ModuleCatalogInventory()
            func rank(_ state: ModuleCatalogState) -> Int {
                switch state {
                case .updateAvailable: 0
                case .notInstalled: 1
                case .current: 2
                case .unsupportedPlatform: 3
                case .unavailable: 4
                }
            }
            let left = rank(inventory.state(for: lhs))
            let right = rank(inventory.state(for: rhs))
            return left == right ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                : left < right
        }
    }

    private var canInstallInitialSelection: Bool {
        guard installingIDs.isEmpty else { return false }
        let inventory = ModuleCatalogInventory()
        guard let catalog else {
            return inventory.hasRequiredInitialModules
        }
        return selectedIDs.allSatisfy { id in
            guard let module = catalog.modules.first(where: { $0.id == id }) else {
                return inventory.isInstalled(moduleID: id, kind: "shiori")
            }
            return inventory.state(for: module) == .current
                || inventory.state(for: module) == .notInstalled
                || inventory.state(for: module) == .updateAvailable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode != .settings {
                Text(mode == .initialSelection ? "はじめに使うモジュール" : "モジュールカタログ")
                    .font(.title2.bold())
                Text(mode == .initialSelection
                    ? "既存ゴーストは変更せず、使っているSHIORI・SAORIを選んである。不要なものは外せる。導入済みの最新版は再ダウンロードしない。YAYAと里々は必須。"
                    : "macOS向けのSHIORI・SAORIをダウンロードする。ゴーストに同梱されたライブラリが優先される。")
                    .foregroundStyle(.secondary)
            }

            if mode == .catalog {
                HStack {
                    TextField("名前で検索", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Picker("種類", selection: $kind) {
                        Text("すべて").tag("all")
                        Text("SHIORI").tag("shiori")
                        Text("SAORI").tag("saori")
                    }
                    .frame(width: 180)
                    Picker("状態", selection: $stateFilter) {
                        Text("すべて").tag("all")
                        Text("未導入").tag("available")
                        Text("更新あり").tag("updates")
                        Text("導入済み").tag("installed")
                    }
                    .frame(width: 180)
                }
            }

            if ModuleCatalogConfiguration.client == nil {
                ContentUnavailableView("カタログを利用できない", systemImage: "network.slash",
                                       description: Text("配布先と署名鍵が設定されていない。"))
            } else if isLoading, catalog == nil {
                ProgressView("カタログを読み込み中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(modules) { module in
                    moduleRow(module)
                }
                .frame(minHeight: mode == .settings ? 260 : 0)
                .overlay {
                    if !isLoading, catalog != nil, modules.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }

            if mode == .catalog, let catalog {
                let inventory = ModuleCatalogInventory()
                let updates = catalog.modules.filter { inventory.state(for: $0) == .updateAvailable }.count
                Text("\(modules.count)件を表示 · \(updates)件の更新あり")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mode == .initialSelection, catalog == nil {
                if let url = URL(string: "https://github.com/opera7133/utatane-modules") {
                    Link("手動導入の手順", destination: url)
                }
                Text("手動導入後はUtataneを再起動して。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("再読み込み") { Task { await reload() } }
                    .disabled(isLoading || ModuleCatalogConfiguration.client == nil)
                Spacer()
                if mode == .initialSelection {
                    Button(catalog == nil ? "導入済みのモジュールで続ける" : "選択したモジュールを導入") {
                        Task { await installInitialSelection() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canInstallInitialSelection)
                }
            }
        }
        .padding(mode == .settings ? 0 : 22)
        .frame(minWidth: mode == .settings ? 0 : 650,
               minHeight: mode == .settings ? 300 : (mode == .initialSelection ? 480 : 540))
        .task(id: customIndexURL + customPublicKey) { await reload() }
        .onChange(of: installedGhosts.map(\.id)) { _, _ in selectInstalledGhostModules() }
        .onChange(of: installedGhosts, initial: true) { _, _ in
            selectInstalledGhostModules()
        }
        .sheet(item: $detailModule) { module in
            ModuleCatalogDetailView(module: module, indexURL: ModuleCatalogConfiguration.client?.indexURL) {
                detailModule = nil
                Task { await install(module.id) }
            }
        }
    }

    private func moduleRow(_ module: SignedModuleCatalog.Module) -> some View {
        HStack(spacing: 14) {
            if mode == .initialSelection {
                Toggle(isOn: Binding(
                    get: { selectedIDs.contains(module.id) },
                    set: { enabled in
                        if enabled {
                            selectedIDs.insert(module.id)
                        } else {
                            selectedIDs.remove(module.id)
                        }
                    }
                )) { EmptyView() }
                    .labelsHidden()
                    .disabled(module.id == "yaya-6" || module.id == "satori")
            }
            VStack(alignment: .leading, spacing: 3) {
                Button(module.displayName) { detailModule = module }
                    .buttonStyle(.plain)
                    .font(.headline)
                Text(([module.kinds.map { $0.uppercased() }.joined(separator: " / "),
                       module.windowsFilenames.first].compactMap(\.self)).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let artifact = ModuleCatalogInventory().artifact(for: module)?.value {
                    Text("\(artifact.version) · macOS \(artifact.minimumOS)以降")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(stateTitle(ModuleCatalogInventory().state(for: module)))
                .font(.caption.weight(.medium))
                .foregroundStyle(ModuleCatalogInventory().state(for: module) == .updateAvailable
                    ? Color.orange : Color.secondary)
            Button { detailModule = module } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("詳細を表示")
            if mode != .initialSelection {
                let state = ModuleCatalogInventory().state(for: module)
                if state == .notInstalled || state == .updateAvailable {
                    Button(installingIDs.contains(module.id) ? "導入中…" : installedLabel(state)) {
                        Task { await install(module.id) }
                    }
                    .disabled(installingIDs.contains(module.id))
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func installedLabel(_ state: ModuleCatalogState) -> String {
        switch state {
        case .notInstalled: String(localized: "ダウンロード")
        case .current: String(localized: "導入済み")
        case .updateAvailable: String(localized: "更新")
        case .unsupportedPlatform: String(localized: "このMacでは利用不可")
        case .unavailable: String(localized: "手動導入")
        }
    }

    private func stateTitle(_ state: ModuleCatalogState) -> String {
        switch state {
        case .notInstalled: String(localized: "未導入")
        case .current: String(localized: "導入済み")
        case .updateAvailable: String(localized: "更新あり")
        case .unsupportedPlatform: String(localized: "このMacでは利用不可")
        case .unavailable: String(localized: "手動導入")
        }
    }

    private func reload() async {
        guard let client = ModuleCatalogConfiguration.client else { return }
        isLoading = true
        catalog = nil
        successMessage = nil
        defer { isLoading = false }
        do {
            catalog = try await client.fetch()
            selectInstalledGhostModules()
            errorMessage = nil
        } catch {
            errorMessage = ModuleCatalogFailureMessage.describe(error)
        }
    }

    private func selectInstalledGhostModules() {
        guard mode == .initialSelection, let catalog else { return }
        let candidates = Set(catalog.modules.filter { $0.availability == "candidate" }.map(\.id))
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane", directoryHint: .isDirectory)
        let used = installedGhosts.flatMap {
            GhostModuleRequirements().missing(for: $0, in: catalog, applicationSupportURL: support)
        }.map(\.id)
        selectedIDs.formUnion(used.filter(candidates.contains))
        let shioriIDs = installedGhosts.compactMap { ghost -> String? in
            let master = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
            guard let identifier = ShioriCatalog.identify(
                masterDirectory: master,
                declaredModuleFilename: ghost.shioriFilename,
                macOSModuleFilename: ghost.shioriMacOSFilename
            )?.id.rawValue else { return nil }
            return identifier == "misaka" ? "misaka-native" : identifier
        }
        selectedIDs.formUnion(shioriIDs.filter(candidates.contains))
    }

    private func install(_ id: String) async {
        guard let client = ModuleCatalogConfiguration.client else { return }
        installingIDs.insert(id)
        defer { installingIDs.remove(id) }
        do {
            _ = try await ModuleCatalogManager(client: client).install(moduleID: id)
            errorMessage = nil
            successMessage = String(localized: "導入した。共通版を使用中のゴーストは再読み込みすると反映される。ゴースト同梱版は優先される。")
        } catch {
            errorMessage = "\(id): \(ModuleCatalogFailureMessage.describe(error))"
        }
    }

    private func installInitialSelection() async {
        guard canInstallInitialSelection else { return }
        if catalog == nil {
            finishInitialSelection()
            return
        }
        guard let client = ModuleCatalogConfiguration.client else { return }
        let ids = ["yaya-6", "satori"] + selectedIDs.subtracting(["yaya-6", "satori"]).sorted()
        for id in ids {
            if catalog?.modules.contains(where: { $0.id == id }) != true,
               ModuleCatalogInventory().isInstalled(moduleID: id, kind: "shiori")
            {
                continue
            }
            if let module = catalog?.modules.first(where: { $0.id == id }),
               ModuleCatalogInventory().state(for: module) == .current
            {
                continue
            }
            installingIDs.insert(id)
            do {
                _ = try await ModuleCatalogManager(client: client).install(moduleID: id)
                installingIDs.remove(id)
            } catch {
                installingIDs.remove(id)
                errorMessage = "\(id): \(ModuleCatalogFailureMessage.describe(error))"
                return
            }
        }
        finishInitialSelection()
    }

    private func finishInitialSelection() {
        NotificationCenter.default.post(name: .moduleCatalogSetupCompleted, object: nil)
        dismissWindow(id: "module-setup")
    }
}

extension Notification.Name {
    static let moduleCatalogSetupCompleted = Notification.Name("Utatane.ModuleCatalogSetupCompleted")
}

enum ModuleCatalogFailureMessage {
    static func describe(_ error: Error) -> String {
        if let catalogError = error as? ModuleCatalogError {
            switch catalogError {
            case .invalidSignature:
                return String(localized: "カタログの署名が一致しない。配布元と公開鍵を確認してから再試行して。")
            case .artifactMismatch:
                return String(localized: "ダウンロードしたモジュールがカタログの検証値と一致しない。再試行して。")
            case .missingArtifact:
                return String(localized: "このモジュールの配布ファイルが見つからない。手動導入の手順を確認して。")
            default:
                return String(localized: "カタログを読み込めなかった。接続先を確認して再試行して。")
            }
        }
        if let installError = error as? ModuleCatalogInstallError {
            switch installError {
            case .unsupportedPlatform:
                return String(localized: "このMacに対応するモジュールがない。手動導入の手順を確認して。")
            case .unavailable, .unsupportedKind:
                return String(localized: "自動導入できるモジュールがない。手動導入の手順を確認して。")
            }
        }
        if error is ModulePackageInstallError {
            return String(localized: "モジュールの検証または導入に失敗した。導入済みの状態を確認して再試行して。")
        }
        return String(localized: "カタログまたはモジュールの取得に失敗した。ネットワークを確認して再試行して。")
    }
}

struct ModuleCatalogSourceSettingsView: View {
    @State private var indexURL = UserDefaults.standard.string(forKey: ModuleCatalogConfiguration.customIndexURLKey) ?? ""
    @State private var publicKey = UserDefaults.standard.string(forKey: ModuleCatalogConfiguration.customPublicKeyKey) ?? ""
    @State private var message: String?

    var body: some View {
        Section("カタログの接続先（上級者向け）") {
            TextField("index.json のURL", text: $indexURL)
                .textContentType(.URL)
            TextField("Ed25519公開鍵（Base64）", text: $publicKey)
            Text("別の配布元を使う場合は、HTTPSのURLと、その配布元が公開した署名鍵を両方指定する。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("接続先を保存") { save() }
                Button("標準に戻す") { reset() }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let trimmedURL = indexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), ModuleCatalogConfiguration.validIndexURL(url),
              let key = Data(base64Encoded: trimmedKey), key.count == 32
        else {
            message = String(localized: "HTTPSのindex.json URLと32バイトの公開鍵を確認して。")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(url.absoluteString, forKey: ModuleCatalogConfiguration.customIndexURLKey)
        defaults.set(trimmedKey, forKey: ModuleCatalogConfiguration.customPublicKeyKey)
        indexURL = url.absoluteString
        publicKey = trimmedKey
        message = String(localized: "接続先を保存した。")
    }

    private func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ModuleCatalogConfiguration.customIndexURLKey)
        defaults.removeObject(forKey: ModuleCatalogConfiguration.customPublicKeyKey)
        indexURL = ""
        publicKey = ""
        message = String(localized: "標準のカタログに戻した。")
    }
}

private struct ModuleCatalogDetailView: View {
    let module: SignedModuleCatalog.Module
    let indexURL: URL?
    let onInstall: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0
    @State private var licenseText: String?
    @State private var instructionsText: String?
    @State private var documentError: String?

    private var artifact: SignedModuleCatalog.Module.Artifact? {
        ModuleCatalogInventory().artifact(for: module)?.value
    }

    private var documentSourceURL: URL? {
        if selection == 1 {
            return module.licenseURL.flatMap(URL.init(string:))
        }
        if selection == 2, let path = module.instructions {
            return indexURL?.deletingLastPathComponent().appending(path: path)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(module.displayName).font(.title2.bold())
                    Text(module.kinds.map { $0.uppercased() }.joined(separator: " / "))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                let state = ModuleCatalogInventory().state(for: module)
                if [.notInstalled, .updateAvailable].contains(state) {
                    Button(state == .updateAvailable ? String(localized: "更新") : String(localized: "ダウンロード")) {
                        onInstall()
                    }
                    .buttonStyle(.borderedProminent)
                } else if state == .unsupportedPlatform {
                    Text("このMacでは利用不可").foregroundStyle(.secondary)
                }
            }
            Picker("情報", selection: $selection) {
                Text("概要").tag(0)
                Text("ライセンス").tag(1)
                Text("導入手順").tag(2)
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selection {
                    case 1:
                        documentBody(licenseText, fallback: module.license ?? "ライセンス情報なし", markdown: false)
                    case 2:
                        documentBody(instructionsText, fallback: "導入手順を読み込めませんでした。", markdown: true)
                    default:
                        if let first = artifact {
                            Text("\(first.version) r\(first.revision) · macOS \(first.minimumOS)以降 · \(ByteCountFormatter.string(fromByteCount: Int64(first.size), countStyle: .file))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("導入手順のみ").foregroundStyle(.secondary)
                        }
                        if let author = module.upstream?.author {
                            Text("作者: \(author)")
                        }
                        if let license = module.license {
                            Text("ライセンス: \(license)")
                        }
                        ForEach(module.limitations ?? [], id: \.self) { limitation in
                            Text(limitation)
                        }
                        if let original = (module.originalURL ?? module.upstream?.url).flatMap(URL.init(string:)) {
                            Link("原作・配布元", destination: original)
                        }
                        if let source = (module.upstream?.url).flatMap(URL.init(string:)) {
                            Link("ソースコード", destination: source)
                        }
                    }
                    if let documentError, selection != 0 {
                        Text(documentError).foregroundStyle(.secondary)
                    }
                    if let source = documentSourceURL, selection != 0 {
                        Link("元のファイルを開く", destination: source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(minHeight: 300)
        }
        .padding(22)
        .frame(width: 620, height: 470)
        .task(id: selection) { await loadSelectedDocument() }
    }

    @ViewBuilder
    private func documentBody(_ value: String?, fallback: String, markdown: Bool) -> some View {
        if let value {
            if markdown {
                ModuleCatalogMarkdownView(source: value, baseURL: documentSourceURL?.deletingLastPathComponent())
            } else {
                Text(value).font(.system(.body, design: .monospaced))
            }
        } else if documentError != nil {
            Text(fallback)
        } else {
            ProgressView("読み込み中…")
        }
    }

    private func loadSelectedDocument() async {
        documentError = nil
        let url: URL?
        switch selection {
        case 1:
            guard licenseText == nil else { return }
            url = module.licenseURL.flatMap(URL.init(string:)).flatMap(Self.rawGitHubURL)
        case 2:
            guard instructionsText == nil else { return }
            url = module.instructions.flatMap { path in
                indexURL?.deletingLastPathComponent().appending(path: path)
            }
        default:
            return
        }
        guard let url, url.scheme == "https" else {
            documentError = "本文のURLがありません。"
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 1_000_000,
                  let content = String(data: data, encoding: .utf8)
            else { throw ModuleCatalogError.invalidResponse }
            if selection == 1 {
                licenseText = content
            }
            if selection == 2 {
                instructionsText = content
            }
        } catch {
            documentError = "本文を読み込めませんでした。"
        }
    }

    private static func rawGitHubURL(_ url: URL) -> URL? {
        guard url.scheme == "https" else { return nil }
        guard url.host == "github.com" else { return url }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 5, components[2] == "blob",
              components.allSatisfy({ $0.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil })
        else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(components[0])/\(components[1])/\(components.dropFirst(3).joined(separator: "/"))")
    }
}

private struct ModuleCatalogMarkdownView: View {
    let source: String
    let baseURL: URL?

    var body: some View {
        let blocks = ModuleCatalogMarkdownBlock.parse(source)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ModuleCatalogMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, title):
            VStack(alignment: .leading, spacing: 6) {
                inlineText(title)
                    .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                if level <= 2 {
                    Divider()
                }
            }
            .padding(.top, level == 1 ? 4 : 8)
        case let .paragraph(text):
            inlineText(text)
                .lineSpacing(4)
        case let .list(items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(item.marker)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        inlineText(item.text)
                            .lineSpacing(3)
                    }
                }
            }
            .padding(.leading, 6)
        case let .code(language, code):
            VStack(alignment: .leading, spacing: 6) {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint)
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
        case .rule:
            Divider()
        }
    }

    private func inlineText(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: source, options: options, baseURL: baseURL))
            ?? AttributedString(source))
    }
}

private enum ModuleCatalogMarkdownBlock {
    struct ListItem {
        let marker: String
        let text: String
    }

    case heading(Int, String)
    case paragraph(String)
    case list([ListItem])
    case code(String, String)
    case quote(String)
    case rule

    static func parse(_ source: String) -> [Self] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Self] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language, code.joined(separator: "\n")))
                index += 1
                continue
            }
            let level = line.prefix(while: { $0 == "#" }).count
            if (1 ... 6).contains(level), line.dropFirst(level).hasPrefix(" ") {
                blocks.append(.heading(level, String(line.dropFirst(level + 1))))
                index += 1
                continue
            }
            if line.count >= 3, Set(line).count == 1, line.first == "-" || line.first == "*" {
                blocks.append(.rule)
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quote.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: " ")))
                continue
            }
            if listItem(line) != nil {
                var items: [ListItem] = []
                while index < lines.count,
                      let item = listItem(lines[index].trimmingCharacters(in: .whitespaces))
                {
                    items.append(item)
                    index += 1
                }
                blocks.append(.list(items))
                continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty, !next.hasPrefix("#"), !next.hasPrefix("```"), !next.hasPrefix("~~~"),
                      !next.hasPrefix(">"), listItem(next) == nil
                else { break }
                paragraph.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
        }
        return blocks
    }

    private static func listItem(_ line: String) -> ListItem? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return ListItem(marker: "•", text: String(line.dropFirst(marker.count)))
        }
        guard let separator = line.firstIndex(where: { $0 == "." || $0 == ")" }),
              line[..<separator].allSatisfy(\.isNumber),
              !line[..<separator].isEmpty,
              line[line.index(after: separator)...].hasPrefix(" ")
        else { return nil }
        return ListItem(marker: String(line[...separator]),
                        text: String(line[line.index(separator, offsetBy: 2)...]))
    }
}

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
            guard ModuleCatalogConfiguration.client != nil,
                  !UserDefaults.standard.bool(forKey: ModuleCatalogConfiguration.setupCompletedKey)
            else { return }
            openWindow(id: "module-setup")
        }
    }
}

enum ModuleCatalogConfiguration {
    static let setupCompletedKey = "moduleCatalog.initialSelectionCompleted"
    static let customIndexURLKey = "moduleCatalog.customIndexURL"
    static let customPublicKeyKey = "moduleCatalog.customPublicKey"

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
    @State private var selectedIDs: Set<String> = ["yaya", "satori"]
    @State private var installingIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var detailModule: SignedModuleCatalog.Module?
    @AppStorage(ModuleCatalogConfiguration.customIndexURLKey) private var customIndexURL = ""
    @AppStorage(ModuleCatalogConfiguration.customPublicKeyKey) private var customPublicKey = ""

    private var modules: [SignedModuleCatalog.Module] {
        (catalog?.modules ?? []).filter { module in
            let kindMatches = mode != .catalog
                ? module.kinds.contains("shiori")
                : kind == "all" || module.kinds.contains(kind)
            return kindMatches && (search.isEmpty || module.displayName.localizedStandardContains(search)
                || module.id.localizedStandardContains(search))
        }
    }

    private var canInstallInitialSelection: Bool {
        guard let catalog else { return false }
        return ["yaya", "satori"].allSatisfy { id in
            catalog.modules.contains { $0.id == id && $0.availability == "candidate" }
        } && installingIDs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode != .settings {
                Text(mode == .initialSelection ? "はじめに使うSHIORI" : "モジュールカタログ")
                    .font(.title2.bold())
                Text(mode == .initialSelection
                    ? "既存ゴーストは変更せず、使っているSHIORIを選んである。不要なものは外せる。導入済みの最新版は再ダウンロードしない。YAYAと里々は必須。"
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("再読み込み") { Task { await reload() } }
                    .disabled(isLoading || ModuleCatalogConfiguration.client == nil)
                Spacer()
                if mode == .initialSelection {
                    Button("選択したSHIORIを導入") { Task { await installInitialSelection() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canInstallInitialSelection)
                }
            }
        }
        .padding(mode == .settings ? 0 : 22)
        .frame(minWidth: mode == .settings ? 0 : 650,
               minHeight: mode == .settings ? 300 : (mode == .initialSelection ? 480 : 540))
        .task(id: customIndexURL + customPublicKey) { await reload() }
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
                    .disabled(module.id == "yaya" || module.id == "satori" || module.availability != "candidate")
            }
            VStack(alignment: .leading, spacing: 3) {
                Button(module.displayName) { detailModule = module }
                    .buttonStyle(.plain)
                    .font(.headline)
                Text(module.kinds.map { $0.uppercased() }.joined(separator: " / "))
                    .font(.caption).foregroundStyle(.secondary)
                if let license = module.license {
                    Text(license).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { detailModule = module } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("詳細を表示")
            if mode != .initialSelection {
                if module.availability == "candidate" {
                    Button(installingIDs.contains(module.id) ? "導入中…" : installedLabel(module)) {
                        Task { await install(module.id) }
                    }
                    .disabled(installingIDs.contains(module.id))
                } else {
                    Text("手動導入").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func installedLabel(_ module: SignedModuleCatalog.Module) -> String {
        let directory = module.kinds.contains("shiori") ? "NativeShiori" : "NativeSaori"
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/\(directory)/\(module.id)/module.json")
        guard let data = try? Data(contentsOf: root),
              let installed = try? JSONDecoder().decode(InstalledModuleVersion.self, from: data)
        else { return "ダウンロード" }
        if module.artifacts.contains(where: { $0.version == installed.version && $0.revision == installed.revision }) {
            return "導入済み"
        }
        return "更新"
    }

    private func reload() async {
        guard let client = ModuleCatalogConfiguration.client else { return }
        isLoading = true
        catalog = nil
        defer { isLoading = false }
        do {
            catalog = try await client.fetch()
            selectInstalledGhostModules()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectInstalledGhostModules() {
        guard mode == .initialSelection, let catalog else { return }
        let candidates = Set(catalog.modules.filter { $0.availability == "candidate" }.map(\.id))
        let used = installedGhosts.compactMap { ghost -> String? in
            let master = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
            guard let identifier = ShioriCatalog.identify(
                masterDirectory: master,
                declaredModuleFilename: ghost.shioriFilename,
                macOSModuleFilename: ghost.shioriMacOSFilename
            )?.id.rawValue else { return nil }
            return identifier == "misaka" ? "misaka-native" : identifier
        }
        selectedIDs.formUnion(used.filter(candidates.contains))
    }

    private func install(_ id: String) async {
        guard let client = ModuleCatalogConfiguration.client else { return }
        installingIDs.insert(id)
        defer { installingIDs.remove(id) }
        do {
            _ = try await ModuleCatalogManager(client: client).install(moduleID: id)
            errorMessage = nil
        } catch {
            errorMessage = "\(id): \(error.localizedDescription)"
        }
    }

    private func installInitialSelection() async {
        guard canInstallInitialSelection, let client = ModuleCatalogConfiguration.client else { return }
        let ids = ["yaya", "satori"] + selectedIDs.subtracting(["yaya", "satori"]).sorted()
        for id in ids {
            if let module = catalog?.modules.first(where: { $0.id == id }), installedLabel(module) == "導入済み" {
                continue
            }
            installingIDs.insert(id)
            do {
                _ = try await ModuleCatalogManager(client: client).install(moduleID: id)
                installingIDs.remove(id)
            } catch {
                installingIDs.remove(id)
                errorMessage = "\(id): \(error.localizedDescription)"
                return
            }
        }
        UserDefaults.standard.set(true, forKey: ModuleCatalogConfiguration.setupCompletedKey)
        dismissWindow(id: "module-setup")
    }
}

private struct InstalledModuleVersion: Decodable {
    let version: String
    let revision: Int
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
        module.artifacts.first(where: { Set($0.architectures) == ["arm64", "x86_64"] }) ?? module.artifacts.first
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
                if module.availability == "candidate" {
                    Button("ダウンロード") { onInstall() }
                        .buttonStyle(.borderedProminent)
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
            if markdown, let rendered = try? AttributedString(markdown: value) {
                Text(rendered)
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

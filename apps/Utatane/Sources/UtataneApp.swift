import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UtataneBalloon
import UtataneContent
import UtataneCore
import UtataneGhostKit
import UtataneNetwork
import UtatanePlatformMacOS
import UtataneRuntime
import UtataneSatoriNative
import UtataneSakuraScript
import UtataneShell
import UtataneYayaNative

@main
struct UtataneApp: App {
    @NSApplicationDelegateAdaptor(UtataneApplicationDelegate.self)
    private var applicationDelegate

    private let model: GhostListModel
    private let shellLoader: ShellLoader
    private let surfaceWindowController: SurfaceWindowController
    private let balloonWindowController: BalloonWindowController
    private let balloonLoader: BalloonLoader
    private let scriptPlayer: SakuraScriptPlayer
    private let selectionStore: ContentSelectionStore
    private let sstpServer: SSTPServer
    @StateObject private var networkSettings: UtataneSettingsStore

    init() {
        let positionStore = WindowPositionStore()
        let surfaceWindowController = SurfaceWindowController(positionStore: positionStore)
        let balloonWindowController = BalloonWindowController(positionStore: positionStore)
        let repository = FileSystemGhostRepository(
            rootDirectory: ContentRoot.ghostsDirectory
        )
        model = GhostListModel(loadGhosts: LoadInstalledGhosts(repository: repository))
        shellLoader = ShellLoader()
        self.surfaceWindowController = surfaceWindowController
        self.balloonWindowController = balloonWindowController
        balloonLoader = BalloonLoader()
        selectionStore = ContentSelectionStore()
        sstpServer = SSTPServer()
        _networkSettings = StateObject(wrappedValue: UtataneSettingsStore())
        scriptPlayer = SakuraScriptPlayer(
            surfaceWindowController: surfaceWindowController,
            balloonWindowController: balloonWindowController
        )
    }

    var body: some Scene {
        WindowGroup {
            UtataneRootView(
                model: model,
                shellLoader: shellLoader,
                surfaceWindowController: surfaceWindowController,
                balloonWindowController: balloonWindowController,
                balloonLoader: balloonLoader,
                scriptPlayer: scriptPlayer,
                selectionStore: selectionStore,
                sstpServer: sstpServer,
                networkSettings: networkSettings,
                applicationDelegate: applicationDelegate
            )
        }
        Settings {
            UtataneSettingsView(
                settings: networkSettings,
                headlinesDirectory: ContentRoot.headlinesDirectory
            )
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Utataneについて") {
                    showAboutPanel()
                }
            }
        }
    }

    private func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "macOS向け伺か互換ベースウェア",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Utatane",
            .applicationVersion: "バージョン \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")",
            .version: "ビルド \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")",
            .credits: credits
        ]
        if let applicationIcon = NSApplication.shared.applicationIconImage {
            options[.applicationIcon] = applicationIcon
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct UtataneRootView: View {
    let model: GhostListModel
    let shellLoader: ShellLoader
    let surfaceWindowController: SurfaceWindowController
    let balloonWindowController: BalloonWindowController
    let balloonLoader: BalloonLoader
    let scriptPlayer: SakuraScriptPlayer
    let selectionStore: ContentSelectionStore
    let sstpServer: SSTPServer
    @ObservedObject var networkSettings: UtataneSettingsStore
    let applicationDelegate: UtataneApplicationDelegate

    @Environment(\.openSettings) private var openSettings

    @State private var previewError: String?
    @State private var lastClickedRegion: String?
    @State private var balloon: BalloonDefinition?
    @State private var session: GhostSession?
    @State private var selectedGhostID: URL?
    @State private var currentGhost: InstalledGhost?
    @State private var selectedShell: InstalledShell?
    @State private var installedBalloons: [BalloonDefinition] = []
    @State private var isImportingNar = false
    @State private var isEnteringRSSURL = false
    @State private var rssURLText = ""
    @State private var installedHeadlines: [InstalledHeadline] = []
    @State private var debugWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            GhostListView(model: model, selection: $selectedGhostID)
            Divider()
            HStack {
                Text("クリック判定")
                Spacer()
                Text(lastClickedRegion ?? "未検出")
                    .foregroundStyle(.secondary)
                Button("ゆっくり再生") {
                    surfaceWindowController.playAnimation(
                        id: 0,
                        minimumFrameDurationMilliseconds: 3000
                    )
                }
                Button("ランダムトーク") {
                    sendEvent(.randomTalk)
                }
                .disabled(session == nil)
                Button("進む") {
                    scriptPlayer.advance()
                }
                Button("停止") {
                    scriptPlayer.cancel()
                }
                Button("NARをインストール") {
                    isImportingNar = true
                }
            }
            .padding(12)
        }
        .task {
            applicationDelegate.onTerminationRequest = {
                requestApplicationTermination()
            }
            await model.load()
            reloadHeadlines()
            let restoredGhost = model.ghosts.first {
                $0.rootDirectory.lastPathComponent == selectionStore.ghostDirectoryName
            }
            selectedGhostID = selectedGhostID ?? restoredGhost?.id ?? model.ghosts.first?.id
            configurePlayback()
            do {
                try sstpServer.start { request in
                    await handleSSTP(request)
                }
            } catch {
                previewError = error.localizedDescription
            }
        }
        .task(id: "\(networkSettings.characterDelayMilliseconds)-\(networkSettings.dialogueDismissalSeconds)") {
            configurePlayback()
        }
        .task(id: networkSettings.randomTalkIntervalMinutes) {
            let interval = networkSettings.randomTalkIntervalMinutes
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval * 60))
                guard !Task.isCancelled else { return }
                sendEvent(.randomTalk)
            }
        }
        .task(id: selectedGhostID) {
            guard let selectedGhostID,
                  let ghost = model.ghosts.first(where: { $0.id == selectedGhostID })
            else { return }
            await transition(to: ghost)
        }
        .task(id: "\(networkSettings.automaticHeadlineRefresh)-\(networkSettings.headlineRefreshIntervalMinutes)") {
            guard networkSettings.automaticHeadlineRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(networkSettings.headlineRefreshIntervalMinutes * 60))
                guard !Task.isCancelled else { return }
                for headline in installedHeadlines {
                    if case let .rss(feedURL) = headline.kind {
                        await fetchRSS(url: feedURL)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingNar,
            allowedContentTypes: [UTType(filenameExtension: "nar") ?? .data]
        ) { result in
            switch result {
            case let .success(url):
                installNar(from: url)
            case let .failure(error):
                if !error.isUserCancelledFileImport {
                    previewError = error.localizedDescription
                }
            }
        }
        .alert(
            "プレビューを表示できなかった",
            isPresented: Binding(
                get: { previewError != nil },
                set: {
                    if !$0 {
                        previewError = nil
                    }
                }
            )
        ) {
            Button("OK") { previewError = nil }
        } message: {
            Text(previewError ?? "")
        }
        .alert("RSS/Atomを取得", isPresented: $isEnteringRSSURL) {
            TextField("https://example.com/feed.xml", text: $rssURLText)
            Button("取得") { fetchRSS() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("RSSまたはAtomフィードのURL")
        }
        .onDisappear {
            scriptPlayer.cancel()
            sstpServer.stop()
        }
        .background {
            DebugWindowReader { window in
                debugWindow = window
                updateDebugWindowVisibility()
            }
        }
        .onChange(of: networkSettings.showsDebugWindow) {
            updateDebugWindowVisibility()
        }
    }

    private func sendEvent(_ event: GhostEvent) {
        guard let session, let balloon else { return }
        Task {
            do {
                if let script = try await session.handle(event: event) {
                    scriptPlayer.play(script, balloon: balloon)
                }
            } catch {
                previewError = error.localizedDescription
            }
        }
    }

    private func transition(to ghost: InstalledGhost, forceReload: Bool = false) async {
        guard forceReload || currentGhost?.id != ghost.id else { return }
        await closeCurrentGhost(reason: .ghostChanging(name: ghost.name))
        guard !Task.isCancelled else { return }
        await activate(ghost)
    }

    private func closeCurrentGhost(reason: GhostStopReason) async {
        guard let activeSession = session else { return }
        session = nil
        configureContextMenu()

        do {
            guard let closeScript = try await activeSession.stop(reason: reason), let balloon else { return }
            await scriptPlayer.playAndWait(closeScript, balloon: balloon)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(1))
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func activate(_ ghost: InstalledGhost) async {
        scriptPlayer.cancel()
        surfaceWindowController.hideAll()
        surfaceWindowController.setPresentationHidden(true)
        session = nil
        balloon = nil
        currentGhost = ghost
        networkSettings.activateGhost(
            directoryName: ghost.rootDirectory.lastPathComponent,
            displayName: ghost.name
        )
        surfaceWindowController.setPositionContentID(ghost.id)
        balloonWindowController.setPositionContentID(ghost.id)
        selectionStore.ghostDirectoryName = ghost.rootDirectory.lastPathComponent

        do {
            let restoredShellName = selectionStore.shellDirectoryName(for: ghost.id)
            let shellChoice = ghost.shells.first {
                $0.directory.lastPathComponent == restoredShellName
            } ?? ghost.shells.first {
                $0.directory == ghost.defaultShellDirectory
            } ?? ghost.shells.first
            guard let shellChoice else {
                throw AppError.missingResource("shell")
            }
            selectedShell = shellChoice
            try show(shell: shellChoice)
            surfaceWindowController.onMouseClick = { scope, region in
                lastClickedRegion = "scope \(scope): \(region ?? "範囲外")"
            }
            surfaceWindowController.onMouseEvent = { event in
                if case .click = event.kind {
                    lastClickedRegion = "scope \(event.scope): \(event.region ?? "範囲外")"
                }
                sendEvent(.mouse(event))
            }
            surfaceWindowController.onNarDrop = { _, urls in
                installNars(from: urls)
            }

            installedBalloons = try balloonLoader.loadInstalled(
                from: ContentRoot.balloonsDirectory
            )
            let restoredBalloonName = selectionStore.balloonDirectoryName(for: ghost.id)
            let loadedBalloon = installedBalloons.first {
                $0.directory.lastPathComponent == restoredBalloonName
            } ?? installedBalloons.first
            balloon = loadedBalloon
            configureContextMenu()
            scriptPlayer.onError = { error in
                previewError = error.localizedDescription
            }
            scriptPlayer.onDialogueContent = {
                surfaceWindowController.setPresentationHidden(false)
            }
            scriptPlayer.onPlaybackFinished = {
                surfaceWindowController.setPresentationHidden(false)
            }
            scriptPlayer.onDialogueDismissed = {
                sendEvent(.shiori(id: "OnSurfaceRestore", references: [:]))
            }
            scriptPlayer.onChoice = { id, arguments in
                if let url = URL(string: id), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                } else if id.caseInsensitiveCompare("CANCEL_NOTALK") == .orderedSame {
                    scriptPlayer.cancel()
                } else {
                    sendEvent(.choice(id: id, arguments: arguments))
                }
            }
            scriptPlayer.onEmbeddedEvent = { id, arguments in
                guard let embeddedSession = session else { return nil }
                return try? await embeddedSession.handle(event: .shiori(
                    id: id,
                    references: Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                        ($0.offset, $0.element)
                    })
                ))
            }

            let ghostSession = try GhostSession(
                personalityEngine: personalityEngine(for: ghost),
                variableStore: GhostVariableStore(fileURL: ContentRoot.variableStoreURL(for: ghost))
            )
            session = ghostSession
            configureContextMenu()
            if let script = try await ghostSession.start(), let loadedBalloon {
                scriptPlayer.play(script, balloon: loadedBalloon)
            }
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func personalityEngine(for ghost: InstalledGhost) throws -> any PersonalityEngine {
        let masterDirectory = ghost.rootDirectory.appending(
            path: "ghost/master",
            directoryHint: .isDirectory
        )
        if NativeYayaPersonalityEngine.supports(masterDirectoryURL: masterDirectory),
           let engine = try? NativeYayaPersonalityEngine(masterDirectoryURL: masterDirectory)
        {
            return engine
        }
        if NativeSatoriPersonalityEngine.supports(masterDirectoryURL: masterDirectory),
           let engine = try? NativeSatoriPersonalityEngine(masterDirectoryURL: masterDirectory)
        {
            return engine
        }

        guard let dialogueURL = ContentRoot.dialogueURL(for: ghost) else {
            throw AppError.missingResource("default-dialogue.json")
        }
        let catalog = try DialogueCatalogLoader().load(from: dialogueURL)
        return DialoguePersonalityEngine(catalog: catalog)
    }

    private func show(shell installedShell: InstalledShell) throws {
        scriptPlayer.cancel()
        let shell = try shellLoader.load(from: installedShell.directory)
        let characters = currentGhost?.characters ?? []
        try surfaceWindowController.show(
            shell: shell,
            defaultSurfaceIDs: Dictionary(
                uniqueKeysWithValues: characters.map { ($0.scope, $0.defaultSurfaceID) }
            )
        )
        scriptPlayer.configure(
            defaultBalloonSurfaceIDs: Dictionary(
                uniqueKeysWithValues: characters.map { ($0.scope, $0.defaultBalloonSurfaceID) }
            )
        )
        selectedShell = installedShell
        if let currentGhost {
            selectionStore.setShellDirectoryName(
                installedShell.directory.lastPathComponent,
                for: currentGhost.id
            )
        }
        configureContextMenu()
    }

    private func select(shell: InstalledShell) {
        do {
            try show(shell: shell)
            sendEvent(.shiori(
                id: "OnShellChanged",
                references: [
                    0: shell.name,
                    1: shell.directory.lastPathComponent
                ]
            ))
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func select(balloon selectedBalloon: BalloonDefinition) {
        scriptPlayer.cancel()
        balloon = selectedBalloon
        if let currentGhost {
            selectionStore.setBalloonDirectoryName(
                selectedBalloon.directory.lastPathComponent,
                for: currentGhost.id
            )
        }
        configureContextMenu()
    }

    private func configureContextMenu() {
        surfaceWindowController.contextMenuItems = {
            [
                .submenu(
                    title: "ゴースト",
                    items: model.ghosts.map { ghost in
                        .action(
                            title: ghost.name,
                            isSelected: ghost.id == selectedGhostID,
                            handler: { selectedGhostID = ghost.id }
                        )
                    }
                ),
                .submenu(
                    title: "Shell",
                    items: (currentGhost?.shells ?? []).map { shell in
                        .action(
                            title: shell.name,
                            isSelected: shell.id == selectedShell?.id,
                            handler: { select(shell: shell) }
                        )
                    }
                ),
                .submenu(
                    title: "バルーン",
                    items: installedBalloons.map { candidate in
                        .action(
                            title: candidate.name,
                            isSelected: candidate.directory == balloon?.directory,
                            handler: { select(balloon: candidate) }
                        )
                    }
                ),
                .separator,
                .action(
                    title: "ランダムトーク",
                    isEnabled: session != nil,
                    handler: { sendEvent(.randomTalk) }
                ),
                .action(title: "バルーンを閉じる", handler: { scriptPlayer.cancel() }),
                .action(title: "NARをインストール…", handler: { isImportingNar = true }),
                .action(
                    title: "ネットワーク更新",
                    isEnabled: currentGhost != nil && session != nil,
                    handler: { updateCurrentGhost() }
                ),
                .submenu(
                    title: "RSS / ヘッドライン",
                    items: installedHeadlines.map { headline in
                        switch headline.kind {
                        case let .rss(feedURL):
                            .action(title: headline.name, handler: {
                                Task { await fetchRSS(url: feedURL) }
                            })
                        case .legacyDLL:
                            .action(title: "\(headline.name)（DLL未対応）", isEnabled: false, handler: {})
                        }
                    } + [
                        .separator,
                        .action(title: "URLを指定して取得…", handler: { isEnteringRSSURL = true })
                    ]
                ),
                .action(
                    title: "設定",
                    handler: {
                            networkSettings.selectedPane = .general
                            openSettings()
                    }
                ),
                .action(title: "デバッグ画面を表示", handler: {
                    networkSettings.showsDebugWindow = true
                    updateDebugWindowVisibility()
                }),
                .separator,
                .action(title: "Utataneを終了", handler: { NSApplication.shared.terminate(nil) })
            ]
        }
    }

    private func configurePlayback() {
        scriptPlayer.configurePlayback(
            characterDelayMilliseconds: networkSettings.characterDelayMilliseconds,
            postDialogueDismissalMilliseconds: networkSettings.dialogueDismissalSeconds * 1000
        )
    }

    private func updateDebugWindowVisibility() {
        guard let debugWindow else { return }
        if networkSettings.showsDebugWindow {
            debugWindow.makeKeyAndOrderFront(nil)
        } else {
            debugWindow.orderOut(nil)
        }
    }

    private func installNar(from url: URL) {
        installNars(from: [url])
    }

    private func updateCurrentGhost() {
        guard let ghost = currentGhost, let updateSession = session, let updateBalloon = balloon else { return }
        Task {
            do {
                _ = await playInstallationEvent(
                    .shiori(id: "OnUpdateBegin", references: [:]),
                    session: updateSession,
                    balloon: updateBalloon
                )
                let homeURL: URL
                if let configured = GhostNetworkUpdater.homeURL(in: ghost.rootDirectory) {
                    homeURL = configured
                } else if let value = try await updateSession.handle(event: .shiori(id: "On_homeurl", references: [:])),
                          let configured = URL(string: value.rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
                {
                    homeURL = configured
                } else {
                    throw GhostNetworkUpdateError.invalidHomeURL
                }
                let result = try await GhostNetworkUpdater().update(
                    rootDirectory: ghost.rootDirectory,
                    homeURL: homeURL
                )
                _ = await playInstallationEvent(
                    .shiori(id: "OnUpdateComplete", references: [
                        0: result.changedFiles.isEmpty ? "none" : "changed",
                        1: String(result.changedFiles.count)
                    ]),
                    session: updateSession,
                    balloon: updateBalloon
                )
            } catch {
                let handled = await playInstallationEvent(
                    .shiori(id: "OnUpdateFailure", references: [0: "download"]),
                    session: updateSession,
                    balloon: updateBalloon
                )
                if !handled { previewError = error.localizedDescription }
            }
        }
    }

    private func fetchRSS() {
        guard let url = URL(string: rssURLText) else {
            previewError = "RSS/AtomのURLが不正"
            return
        }
        Task { await fetchRSS(url: url) }
    }

    private func fetchRSS(url: URL) async {
        guard let rssSession = session, let rssBalloon = balloon else { return }
        do {
            let siteName = url.host ?? "RSS"
            _ = await playInstallationEvent(
                .shiori(id: "OnRSSBegin", references: [0: siteName, 1: url.absoluteString]),
                session: rssSession,
                balloon: rssBalloon
            )
            let feed = try await RSSFeedClient().fetch(url)
            var references: [Int: String] = [
                0: sanitizeNetworkText(feed.title),
                1: feed.link
            ]
            for (index, item) in feed.items.prefix(50).enumerated() {
                references[index + 2] = [
                    sanitizeNetworkText(item.title), item.link,
                    sanitizeNetworkText(item.published), sanitizeNetworkText(item.author),
                    sanitizeNetworkText(item.summary)
                ].joined(separator: "\u{1}")
            }
            _ = await playInstallationEvent(
                .shiori(id: "OnRSSComplete", references: references),
                session: rssSession,
                balloon: rssBalloon
            )
        } catch {
            let handled = await playInstallationEvent(
                .shiori(id: "OnRSSFailure", references: [0: "can't analyze"]),
                session: rssSession,
                balloon: rssBalloon
            )
            if !handled { previewError = error.localizedDescription }
        }
    }

    private func reloadHeadlines() {
        installedHeadlines = (try? HeadlineCatalog().load(from: ContentRoot.headlinesDirectory)) ?? []
        configureContextMenu()
    }

    private func sanitizeNetworkText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\", with: "")
            .filter { character in
                !character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            }
            .prefix(4096)
            .description
    }

    private func handleSSTP(_ request: SSTPRequest) async -> SSTPResponse {
        guard let activeSession = session, let activeBalloon = balloon else {
            return SSTPResponse(statusCode: 503, reason: "Service Unavailable")
        }
        var script: SakuraScript?
        if let eventID = request.value(for: "Event") {
            var references: [Int: String] = [:]
            for index in 0 ..< 256 {
                guard let value = request.value(for: "Reference\(index)") else { continue }
                references[index] = value
            }
            script = try? await activeSession.handle(event: .shiori(id: eventID, references: references))
        }
        if script == nil, let fallback = request.value(for: "Script") {
            script = SakuraScript(rawValue: fallback)
        }
        guard let script else { return SSTPResponse(statusCode: 204, reason: "No Content") }
        scriptPlayer.play(script, balloon: activeBalloon)
        return SSTPResponse(script: script.rawValue)
    }

    private func installNars(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        let roots = NarInstallationRoots(
            ghostsDirectory: ContentRoot.ghostsDirectory,
            balloonsDirectory: ContentRoot.balloonsDirectory,
            headlinesDirectory: ContentRoot.headlinesDirectory
        )
        let selectedGhostDirectory = currentGhost?.rootDirectory
        let installSession = session
        let installBalloon = balloon
        Task {
            let securityScopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                for url in securityScopedURLs {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                _ = await playInstallationEvent(
                    .shiori(id: "OnInstallBegin", references: [:]),
                    session: installSession,
                    balloon: installBalloon
                )
                var installedItems: [NarInstalledItem] = []
                for url in urls {
                    let result = try await Task.detached {
                        try NarInstaller().install(
                            archiveURL: url,
                            roots: roots,
                            selectedGhostDirectory: selectedGhostDirectory
                        )
                    }.value
                    installedItems.append(contentsOf: result.items)
                }
                await model.load()
                if let refreshedGhost = model.ghosts.first(where: {
                    $0.id.standardizedFileURL == selectedGhostID?.standardizedFileURL
                }) {
                    currentGhost = refreshedGhost
                }
                installedBalloons = try balloonLoader.loadInstalled(from: ContentRoot.balloonsDirectory)
                reloadHeadlines()
                configureContextMenu()

                let separator = "\u{1}"
                _ = await playInstallationEvent(
                    .shiori(id: "OnInstallCompleteEx", references: [
                        0: installedItems.map { $0.type.rawValue }.joined(separator: separator),
                        1: installedItems.map(\.name).joined(separator: separator),
                        2: installedItems.map { $0.url.lastPathComponent }.joined(separator: separator)
                    ]),
                    session: installSession,
                    balloon: installBalloon
                )
            } catch {
                let handled = await playInstallationEvent(
                    .shiori(id: "OnInstallFailure", references: [0: installFailureReason(error)]),
                    session: installSession,
                    balloon: installBalloon
                )
                if !handled {
                    previewError = error.localizedDescription
                }
            }
        }
    }

    private func playInstallationEvent(
        _ event: GhostEvent,
        session: GhostSession?,
        balloon: BalloonDefinition?
    ) async -> Bool {
        guard let session, let balloon else { return false }
        do {
            guard let script = try await session.handle(event: event) else { return false }
            scriptPlayer.play(script, balloon: balloon)
            return true
        } catch {
            return false
        }
    }

    private func installFailureReason(_ error: Error) -> String {
        guard let error = error as? NarInstallError else { return "unsupported" }
        switch error {
        case .unreadableArchive, .commandFailed, .symbolicLink, .unsafeEntry,
             .tooManyEntries, .extractedContentTooLarge:
            return "extraction"
        case .missingInstallFile, .ambiguousInstallFile, .unsupportedTextEncoding,
             .invalidDirectoryName, .missingSourceDirectory, .shellRequiresGhost:
            return "invalid type"
        case .unsupportedType, .missingArchive, .archiveTooLarge, .destinationExists:
            return "unsupported"
        }
    }

    private func requestApplicationTermination() {
        Task {
            await closeCurrentGhost(reason: .close)
            scriptPlayer.cancel()
            surfaceWindowController.hideAll()
            applicationDelegate.completeTermination()
        }
    }
}

@MainActor
private final class UtataneApplicationDelegate: NSObject, NSApplicationDelegate {
    var onTerminationRequest: (() -> Void)?

    private var isAwaitingTermination = false
    private var isTerminationApproved = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminationApproved {
            return .terminateNow
        }
        guard let onTerminationRequest else {
            return .terminateNow
        }
        if !isAwaitingTermination {
            isAwaitingTermination = true
            onTerminationRequest()
        }
        return .terminateLater
    }

    func completeTermination() {
        guard isAwaitingTermination else { return }
        isTerminationApproved = true
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }
}

private extension Error {
    var isUserCancelledFileImport: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}

private enum AppError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "アプリ内リソースが見つからない: \(name)"
        }
    }
}

private struct DebugWindowReader: NSViewRepresentable {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    func makeNSView(context _: Context) -> DebugWindowReaderView {
        DebugWindowReaderView(onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: DebugWindowReaderView, context _: Context) {
        nsView.onWindowAvailable = onWindowAvailable
    }
}

private final class DebugWindowReaderView: NSView {
    var onWindowAvailable: @MainActor (NSWindow) -> Void

    init(onWindowAvailable: @escaping @MainActor (NSWindow) -> Void) {
        self.onWindowAvailable = onWindowAvailable
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor [onWindowAvailable] in
            onWindowAvailable(window)
        }
    }
}

private enum ContentRoot {
    static func variableStoreURL(for ghost: InstalledGhost) -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appending(path: "Utatane/State", directoryHint: .isDirectory)
            .appending(path: ghost.rootDirectory.lastPathComponent, directoryHint: .isDirectory)
            .appending(path: "variables.json", directoryHint: .notDirectory)
    }

    static func dialogueURL(for ghost: InstalledGhost) -> URL? {
        if let override = ProcessInfo.processInfo.environment["UTATANE_DIALOGUE_PATH"] {
            return URL(filePath: override, directoryHint: .notDirectory)
        }

        #if DEBUG
            let localDialogue = repositoryRoot
                .appending(path: "Content/Local/Converted", directoryHint: .isDirectory)
                .appending(path: "\(ghost.rootDirectory.lastPathComponent).json", directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: localDialogue.path) {
                return localDialogue
            }
        #endif

        return Bundle.main.url(forResource: "default-dialogue", withExtension: "json")
    }

    static var ghostsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["UTATANE_GHOSTS_ROOT"] {
            return URL(filePath: override, directoryHint: .isDirectory)
        }

        #if DEBUG
            let localGhosts = repositoryRoot.appending(
                path: "Content/Local/Ghosts",
                directoryHint: .isDirectory
            )
            if FileManager.default.fileExists(atPath: localGhosts.path) {
                return localGhosts
            }
        #endif

        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Utatane/Ghosts", directoryHint: .isDirectory)
    }

    static var balloonsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["UTATANE_BALLOONS_ROOT"] {
            return URL(filePath: override, directoryHint: .isDirectory)
        }

        #if DEBUG
            let localBalloons = repositoryRoot.appending(
                path: "Content/Local/Balloons",
                directoryHint: .isDirectory
            )
            if FileManager.default.fileExists(atPath: localBalloons.path) {
                return localBalloons
            }
        #endif

        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Utatane/Balloons", directoryHint: .isDirectory)
    }

    static var headlinesDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["UTATANE_HEADLINES_ROOT"] {
            return URL(filePath: override, directoryHint: .isDirectory)
        }

        #if DEBUG
            let localHeadlines = repositoryRoot.appending(
                path: "Content/Local/Headline",
                directoryHint: .isDirectory
            )
            if FileManager.default.fileExists(atPath: localHeadlines.path) {
                return localHeadlines
            }
        #endif

        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Utatane/Headline", directoryHint: .isDirectory)
    }

    private static var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UtataneBalloon
import UtataneContent
import UtataneCore
import UtataneGhostKit
import UtataneKawariNative
import UtataneNetwork
import UtatanePlatformMacOS
import UtatanePOSIXShiori
import UtataneRuntime
import UtataneSakuraScript
import UtataneSatoriNative
import UtataneShell
import UtataneWindowsShiori
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
    private let statusWindowController: StatusWindowController
    private let alertController: ApplicationAlertController
    @StateObject private var networkSettings: UtataneSettingsStore

    init() {
        try? ContentRoot.prepareDirectories()
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
        statusWindowController = StatusWindowController()
        alertController = ApplicationAlertController()
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
                statusWindowController: statusWindowController,
                alertController: alertController,
                networkSettings: networkSettings,
                applicationDelegate: applicationDelegate
            )
        }
        Settings {
            UtataneSettingsView(
                settings: networkSettings,
                headlinesDirectory: ContentRoot.headlinesDirectory,
                balloonsDirectory: ContentRoot.balloonsDirectory
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
    let statusWindowController: StatusWindowController
    let alertController: ApplicationAlertController
    private let weatherProvider = CurrentWeatherProvider()
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
    @State private var showsOnboarding = false
    @State private var isImportingSSPDirectory = false
    @State private var calledGhosts: [URL: CalledGhostRuntime] = [:]
    @State private var showsStartupGhostPicker = false
    @State private var startupGhostID: URL?
    @State private var isTransitioningGhost = false
    @State private var weatherTask: Task<Void, Never>?

    var body: some View {
        Group {
            if showsOnboarding {
                WelcomeView(
                    installNar: { isImportingNar = true },
                    importSSP: { isImportingSSPDirectory = true },
                    showContentFolder: showContentFolder
                )
            } else {
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
                        Button("リロード") {
                            reloadCurrentGhost()
                        }
                        .disabled(currentGhost == nil || isTransitioningGhost)
                        Button("NARをインストール") {
                            isImportingNar = true
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task {
            applicationDelegate.onTerminationRequest = {
                requestApplicationTermination()
            }
            applicationDelegate.setOpenNarHandler { urls in
                installNars(from: urls)
            }
            await model.load()
            showsOnboarding = model.ghosts.isEmpty
            reloadHeadlines()
            switch networkSettings.startupBehavior {
            case .restore:
                let restoredGhost = model.ghosts.first {
                    $0.rootDirectory.lastPathComponent == selectionStore.ghostDirectoryName
                }
                selectedGhostID = selectedGhostID ?? restoredGhost?.id ?? model.ghosts.first?.id
            case .choose:
                startupGhostID = model.ghosts.first?.id
                showsStartupGhostPicker = !model.ghosts.isEmpty
            case .random:
                selectedGhostID = model.ghosts.randomElement()?.id
            }
            configurePlayback()
            applyAppearance()
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
        .task(id: "\(networkSettings.shellScalePercent)-\(networkSettings.balloonScalePercent)-\(networkSettings.linksBalloonScale)-\(networkSettings.balloonTextScalePercent)-\(networkSettings.locksShellToDesktopBottom)-\(networkSettings.keepsShellOnScreen)") {
            configureDisplay()
        }
        .task(id: networkSettings.appearance) {
            applyAppearance()
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                sendSecondChange()
            }
        }
        .task(id: selectedGhostID) {
            guard let selectedGhostID,
                  let ghost = model.ghosts.first(where: { $0.id == selectedGhostID })
            else { return }
            await transition(to: ghost)
        }
        .task(id: "\(selectedGhostID?.path ?? "")-\(networkSettings.automaticGhostUpdate)-\(networkSettings.ghostUpdateIntervalDays)") {
            guard networkSettings.automaticGhostUpdate else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  let ghost = currentGhost,
                  networkSettings.shouldAutomaticallyUpdateGhost(
                      directoryName: ghost.rootDirectory.lastPathComponent
                  )
            else { return }
            updateCurrentGhost(isAutomatic: true)
        }
        .task(id: "\(networkSettings.automaticHeadlineRefresh)-\(networkSettings.headlineRefreshIntervalMinutes)") {
            guard networkSettings.automaticHeadlineRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(networkSettings.headlineRefreshIntervalMinutes * 60))
                guard !Task.isCancelled else { return }
                for headline in installedHeadlines {
                    switch headline.kind {
                    case let .rss(feedURL):
                        await fetchRSS(url: feedURL)
                    case .legacyDLL:
                        await fetchLegacyHeadline(headline)
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
        .sheet(isPresented: $showsStartupGhostPicker) {
            StartupGhostPicker(
                ghosts: model.ghosts,
                selection: $startupGhostID,
                start: {
                    selectedGhostID = startupGhostID
                    showsStartupGhostPicker = false
                }
            )
        }
        .fileImporter(
            isPresented: $isImportingSSPDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case let .success(url):
                importSSPContents(from: url)
            case let .failure(error):
                if !error.isUserCancelledFileImport {
                    previewError = error.localizedDescription
                }
            }
        }
        .onChange(of: previewError) { _, message in
            guard let message else { return }
            previewError = nil
            alertController.showError(message)
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
        .onChange(of: showsOnboarding) {
            updateDebugWindowVisibility()
        }
    }

    private func sendEvent(_ event: GhostEvent) {
        guard !isTransitioningGhost, let session, let balloon else { return }
        Task {
            do {
                guard let response = try await session.response(for: event) else { return }
                if let script = response.script {
                    scriptPlayer.play(script, balloon: balloon)
                }
                forwardCommunication(from: currentGhost, response: response)
            } catch {
                previewError = error.localizedDescription
            }
        }
    }

    private func sendSecondChange() {
        guard !isTransitioningGhost else { return }
        let references = secondChangeReferences(for: surfaceWindowController)
        if let session {
            let canTalk = !scriptPlayer.isDialogueActive
            var primaryReferences = references
            primaryReferences[3] = canTalk ? "1" : "0"
            Task {
                do {
                    guard let response = try await session.response(for: .shiori(
                        id: "OnSecondChange",
                        references: primaryReferences
                    )) else { return }
                    guard canTalk else { return }
                    if let script = response.script, let balloon {
                        scriptPlayer.play(script, balloon: balloon)
                    }
                    forwardCommunication(from: currentGhost, response: response)
                } catch {
                    previewError = error.localizedDescription
                }
            }
        }
        for runtime in calledGhosts.values {
            runtime.sendSecondChange(references: secondChangeReferences(for: runtime.surfaceController))
        }
    }

    private func secondChangeReferences(for controller: SurfaceWindowController) -> [Int: String] {
        let frames = controller.visibleScopes.compactMap { controller.windowFrame(for: $0) }
        let isClipped = frames.contains { frame in
            !NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
        }
        let otherControllers = [surfaceWindowController] + calledGhosts.values.map(\.surfaceController)
        let otherFrames = otherControllers.filter { $0 !== controller }.flatMap { other in
            other.visibleScopes.compactMap { other.windowFrame(for: $0) }
        }
        let isOverlapping = frames.contains { frame in
            otherFrames.contains { $0.intersects(frame) }
        }
        return [
            0: String(Int(ProcessInfo.processInfo.systemUptime / 3600)),
            1: isClipped ? "1" : "0",
            2: isOverlapping ? "1" : "0",
            4: String(Int(CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .null
            )))
        ]
    }

    private func transition(to ghost: InstalledGhost, forceReload: Bool = false) async {
        guard forceReload || currentGhost?.id != ghost.id else { return }
        let previousGhost = currentGhost
        let statusToken = statusWindowController.show("「\(ghost.name)」を起動中…")
        defer { statusWindowController.hide(token: statusToken) }
        isTransitioningGhost = true
        defer { isTransitioningGhost = false }
        if let called = calledGhosts.removeValue(forKey: ghost.id) {
            await called.stop()
        }
        await closeCurrentGhost(reason: .ghostChanging(name: ghost.name))
        guard !Task.isCancelled else { return }
        switch await activate(ghost) {
        case .success:
            return
        case let .failure(error):
            let fallbackCandidates = ([previousGhost].compactMap(\.self) + model.ghosts)
                .reduce(into: [InstalledGhost]()) { result, candidate in
                    guard candidate.id != ghost.id,
                          !result.contains(where: { $0.id == candidate.id })
                    else { return }
                    result.append(candidate)
                }
            for fallback in fallbackCandidates {
                let fallbackToken = statusWindowController.show(
                    "「\(ghost.name)」を起動できなかったため「\(fallback.name)」を起動中…"
                )
                let fallbackResult = await activate(fallback)
                statusWindowController.hide(token: fallbackToken)
                if case .success = fallbackResult {
                    selectedGhostID = fallback.id
                    previewError = "「\(ghost.name)」を起動できなかったため「\(fallback.name)」へ切り替えた。\n\(error.localizedDescription)"
                    return
                }
            }
            currentGhost = nil
            selectedGhostID = nil
            previewError = "「\(ghost.name)」を起動できず、代わりに起動できるゴーストも見つからなかった。\n\(error.localizedDescription)"
        }
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
            if !isTransitioningGhost {
                previewError = error.localizedDescription
            }
        }
    }

    private func activate(_ ghost: InstalledGhost) async -> Result<Void, any Error> {
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
        configureDisplay()
        surfaceWindowController.setPositionContentID(ghost.id)
        balloonWindowController.setPositionContentID(ghost.id)
        selectionStore.ghostDirectoryName = ghost.rootDirectory.lastPathComponent

        defer { surfaceWindowController.setPresentationHidden(false) }
        do {
            guard let shellChoice = selectionStore.resolveShell(for: ghost) else {
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
            let loadedBalloon = selectionStore.resolveBalloon(
                for: ghost,
                from: installedBalloons,
                defaultDirectoryName: networkSettings.defaultBalloonDirectoryName
            )
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
                if ["configuration", "configurationdialog"].contains(id.lowercased()) {
                    networkSettings.selectedPane = .advanced
                    openSettings()
                } else if let url = URL(string: id), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
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
            scriptPlayer.onInputBox = { id, _, initialValue in
                guard let value = promptForText(initialValue: initialValue),
                      let activeSession = session
                else { return nil }
                return try? await activeSession.handle(event: .shiori(
                    id: id,
                    references: [0: value]
                ))
            }
            scriptPlayer.onHTTPGet = { url, eventID in
                await handleHTTPGet(url: url, eventID: eventID)
            }
            scriptPlayer.onWeatherGet = { eventID in
                weatherTask?.cancel()
                weatherTask = Task {
                    await fetchWeatherAndPlay(eventID: eventID)
                }
                return nil
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
            return .success(())
        } catch {
            session = nil
            balloon = nil
            return .failure(error)
        }
    }

    private func personalityEngine(for ghost: InstalledGhost) throws -> any PersonalityEngine {
        let masterDirectory = ghost.rootDirectory.appending(
            path: "ghost/master",
            directoryHint: .isDirectory
        )
        if NativeYayaPersonalityEngine.supports(masterDirectoryURL: masterDirectory) {
            return try NativeYayaPersonalityEngine(masterDirectoryURL: masterDirectory)
        }
        if NativeSatoriPersonalityEngine.supports(masterDirectoryURL: masterDirectory) {
            return try NativeSatoriPersonalityEngine(masterDirectoryURL: masterDirectory)
        }
        if NativeKawariPersonalityEngine.supports(masterDirectoryURL: masterDirectory) {
            return try NativeKawariPersonalityEngine(masterDirectoryURL: masterDirectory)
        }
        if POSIXShioriPersonalityEngine.supports(masterDirectoryURL: masterDirectory) {
            return try POSIXShioriPersonalityEngine(masterDirectoryURL: masterDirectory)
        }
        if MateriaFirstPersonalityEngine.supports(shioriFilename: ghost.shioriFilename),
           let configuration = ContentRoot.materiaFirstConfiguration(for: ghost)
        {
            return MateriaFirstPersonalityEngine(configuration: configuration)
        } else if MateriaFirstPersonalityEngine.supports(shioriFilename: ghost.shioriFilename) {
            throw AppError.windowsShioriUnavailable
        }

        guard let dialogueURL = ContentRoot.dialogueURL(for: ghost) else {
            throw AppError.unsupportedShiori(ghost.shioriFilename)
        }
        let catalog = try DialogueCatalogLoader().load(from: dialogueURL)
        return DialoguePersonalityEngine(catalog: catalog)
    }

    private func promptForText(initialValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "文字を入力"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(string: initialValue)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func handleHTTPGet(url source: String, eventID: String) async -> SakuraScript? {
        guard let activeSession = session else { return nil }
        guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return try? await activeSession.handle(event: .shiori(id: eventID, references: [:]))
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "utatane-http-get-\(UUID().uuidString)", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(statusCode) else { throw URLError(.badServerResponse) }
            try data.write(to: temporaryURL, options: .atomic)
            return try await activeSession.handle(event: .shiori(id: eventID, references: [
                0: source,
                1: String(statusCode),
                2: response.mimeType ?? "",
                3: temporaryURL.path
            ]))
        } catch {
            return try? await activeSession.handle(event: .shiori(id: eventID, references: [:]))
        }
    }

    private func fetchWeatherAndPlay(eventID: String) async {
        guard let balloon else { return }
        let script = await handleWeatherGet(eventID: eventID)
        scriptPlayer.play(script, balloon: balloon)
    }

    private func handleWeatherGet(eventID: String) async -> SakuraScript {
        do {
            let weather = try await weatherProvider.fetch()
            return await weatherResultScript(eventID: eventID, references: [
                0: "ok",
                1: String(weather.code),
                2: String(format: "%.1f", weather.temperatureCelsius),
                3: weather.isDay ? "1" : "0"
            ], fallback: "天気は取得できたけど、ゴースト側の結果トークが空だった。")
        } catch CurrentWeatherError.locationPermissionDenied {
            return await weatherResultScript(eventID: eventID, references: [0: "denied"], fallback: "位置情報が許可されてないみたい。")
        } catch CurrentWeatherError.locationServicesUnavailable {
            return await weatherResultScript(eventID: eventID, references: [0: "unavailable"], fallback: "位置情報サービスを利用できなかった。")
        } catch CurrentWeatherError.locationTimedOut {
            return await weatherResultScript(eventID: eventID, references: [0: "timeout"], fallback: "位置情報の取得が10秒でタイムアウトした。")
        } catch {
            return await weatherResultScript(eventID: eventID, references: [0: "network"], fallback: "天気情報の通信に失敗した。")
        }
    }

    private func weatherResultScript(
        eventID: String,
        references: [Int: String],
        fallback: String
    ) async -> SakuraScript {
        if let activeSession = session,
           let response = try? await activeSession.handle(event: .shiori(id: eventID, references: references)),
           !response.rawValue.isEmpty
        {
            return response
        }
        return SakuraScript(rawValue: "\\0\\s[6]\(fallback)\\e")
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
        let statusToken = statusWindowController.show("「\(shell.name)」に切り替え中…")
        defer { statusWindowController.hide(token: statusToken) }
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
                    title: "ゴースト切り替え",
                    items: model.ghosts.map { ghost in
                        .action(
                            title: ghost.name,
                            isSelected: ghost.id == selectedGhostID,
                            handler: { selectedGhostID = ghost.id }
                        )
                    }
                ),
                callGhostMenu(),
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
                            .action(
                                title: headline.name,
                                isEnabled: headline.siteURL != nil
                                    && (ConfigHeadlineSensor.canLoad(headline)
                                        || ContentRoot.windowsHeadlineConfiguration() != nil),
                                handler: { Task { await fetchLegacyHeadline(headline) } }
                            )
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
                .action(
                    title: "現在のゴーストを再読み込み",
                    isEnabled: currentGhost != nil && !isTransitioningGhost,
                    handler: { reloadCurrentGhost() }
                ),
                .separator,
                .action(title: "Utataneを終了", handler: { NSApplication.shared.terminate(nil) })
            ]
        }
        for runtime in calledGhosts.values {
            runtime.contextMenuItems = { calledGhostContextMenu(for: runtime) }
        }
    }

    private func callGhostMenu() -> SurfaceContextMenuItem {
        .submenu(
            title: "ゴーストを呼ぶ",
            items: model.ghosts.filter { ghost in
                ghost.id != currentGhost?.id && calledGhosts[ghost.id] == nil
            }.map { ghost in
                .action(title: ghost.name, handler: { call(ghost) })
            }
        )
    }

    private func calledGhostContextMenu(for runtime: CalledGhostRuntime) -> [SurfaceContextMenuItem] {
        [
            .submenu(
                title: "ゴースト切り替え",
                items: model.ghosts.map { ghost in
                    .action(
                        title: ghost.name,
                        isSelected: ghost.id == selectedGhostID,
                        handler: { selectedGhostID = ghost.id }
                    )
                }
            ),
            callGhostMenu(),
            .submenu(
                title: "Shell",
                items: runtime.ghost.shells.map { shell in
                    .action(
                        title: shell.name,
                        isSelected: shell.id == runtime.shell.id,
                        handler: {
                            runtime.select(shell: shell)
                            configureContextMenu()
                        }
                    )
                }
            ),
            .submenu(
                title: "バルーン",
                items: installedBalloons.map { balloon in
                    .action(
                        title: balloon.name,
                        isSelected: balloon.directory == runtime.balloon.directory,
                        handler: {
                            runtime.select(balloon: balloon)
                            configureContextMenu()
                        }
                    )
                }
            ),
            .separator,
            .action(title: "ランダムトーク", handler: { runtime.send(.randomTalk) }),
            .action(title: "このゴーストを閉じる", handler: { dismissCalledGhost(runtime.ghost) }),
            .action(title: "設定", handler: {
                networkSettings.selectedPane = .general
                openSettings()
            }),
            .separator,
            .action(title: "Utataneを終了", handler: { NSApplication.shared.terminate(nil) })
        ]
    }

    private func call(_ ghost: InstalledGhost) {
        guard let caller = currentGhost, calledGhosts[ghost.id] == nil else { return }
        Task {
            do {
                sendEvent(.shiori(id: "OnGhostCalling", references: [
                    0: ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
                    1: "manual",
                    2: ghost.name,
                    3: ghost.rootDirectory.path
                ]))
                let runtime = try CalledGhostRuntime(
                    ghost: ghost,
                    balloons: installedBalloons,
                    shellLoader: shellLoader,
                    selectionStore: selectionStore,
                    defaultBalloonDirectoryName: networkSettings.defaultBalloonDirectoryName,
                    personalityEngine: personalityEngine(for: ghost),
                    characterDelayMilliseconds: networkSettings.characterDelayMilliseconds,
                    dialogueDismissalMilliseconds: networkSettings.dialogueDismissalSeconds * 1000
                )
                runtime.onError = { previewError = $0.localizedDescription }
                runtime.onNarDrop = { installNars(from: $0) }
                runtime.onCommunication = { target, sentence in
                    deliverCommunication(from: ghost, target: target, sentence: sentence)
                }
                calledGhosts[ghost.id] = runtime
                configureContextMenu()
                let startupScript = try await runtime.start(caller: caller) ?? ""
                sendEvent(.shiori(id: "OnGhostCallComplete", references: [
                    0: ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
                    1: startupScript,
                    2: ghost.name,
                    3: ghost.rootDirectory.path,
                    7: runtime.shell.name
                ]))
            } catch {
                calledGhosts[ghost.id] = nil
                configureContextMenu()
                previewError = error.localizedDescription
            }
        }
    }

    private func dismissCalledGhost(_ ghost: InstalledGhost) {
        guard let runtime = calledGhosts.removeValue(forKey: ghost.id) else { return }
        configureContextMenu()
        Task {
            await runtime.stop()
            sendEvent(.shiori(id: "OnOtherGhostClosed", references: [
                0: ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
                1: ghost.name,
                2: ghost.rootDirectory.path
            ]))
        }
    }

    private func forwardCommunication(from sender: InstalledGhost?, response: PersonalityResponse) {
        guard let sender,
              let target = response.references[0], !target.isEmpty,
              let sentence = response.references[1], !sentence.isEmpty else { return }
        deliverCommunication(from: sender, target: target, sentence: sentence)
    }

    private func deliverCommunication(from sender: InstalledGhost, target: String, sentence: String) {
        if let currentGhost, ghost(currentGhost, matches: target), let session, let balloon {
            Task {
                guard let response = try? await session.response(for: .shiori(
                    id: "OnCommunicate",
                    references: [0: sender.name, 1: sentence]
                )) else { return }
                if let script = response.script {
                    scriptPlayer.play(script, balloon: balloon)
                }
            }
            return
        }
        guard let runtime = calledGhosts.values.first(where: { ghost($0.ghost, matches: target) }) else { return }
        Task { _ = await runtime.communicate(from: sender.name, sentence: sentence) }
    }

    private func ghost(_ ghost: InstalledGhost, matches target: String) -> Bool {
        ghost.name.caseInsensitiveCompare(target) == .orderedSame
            || ghost.characters.contains { $0.name?.caseInsensitiveCompare(target) == .orderedSame }
    }

    private func configurePlayback() {
        scriptPlayer.configurePlayback(
            characterDelayMilliseconds: networkSettings.characterDelayMilliseconds,
            postDialogueDismissalMilliseconds: networkSettings.dialogueDismissalSeconds * 1000
        )
        for runtime in calledGhosts.values {
            runtime.configurePlayback(
                characterDelayMilliseconds: networkSettings.characterDelayMilliseconds,
                dismissalMilliseconds: networkSettings.dialogueDismissalSeconds * 1000
            )
        }
    }

    private func configureDisplay() {
        let shellScale = Double(networkSettings.shellScalePercent) / 100
        let balloonScalePercent = networkSettings.linksBalloonScale
            ? networkSettings.shellScalePercent
            : networkSettings.balloonScalePercent
        surfaceWindowController.setDisplayScale(shellScale)
        surfaceWindowController.setPlacement(
            locksToDesktopBottom: networkSettings.locksShellToDesktopBottom,
            keepsOnScreen: networkSettings.keepsShellOnScreen
        )
        balloonWindowController.setDisplayScale(
            Double(balloonScalePercent) / 100,
            textScale: Double(networkSettings.balloonTextScalePercent) / 100
        )
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = switch networkSettings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func updateDebugWindowVisibility() {
        guard let debugWindow else { return }
        if showsOnboarding || networkSettings.showsDebugWindow {
            debugWindow.makeKeyAndOrderFront(nil)
        } else {
            debugWindow.orderOut(nil)
        }
    }

    private func installNar(from url: URL) {
        installNars(from: [url])
    }

    private func updateCurrentGhost(isAutomatic: Bool = false) {
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
                networkSettings.recordGhostUpdate(
                    directoryName: ghost.rootDirectory.lastPathComponent
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
                if !handled, !isAutomatic {
                    previewError = error.localizedDescription
                }
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
            if !handled {
                previewError = error.localizedDescription
            }
        }
    }

    private func fetchLegacyHeadline(_ headline: InstalledHeadline) async {
        guard let headlineSession = session, let headlineBalloon = balloon else { return }
        guard let sourceURL = headline.siteURL else {
            previewError = "HEADLINEセンサーの取得URLが設定されていない"
            return
        }
        let usesNativeConfig = ConfigHeadlineSensor.canLoad(headline)
        let windowsConfiguration = ContentRoot.windowsHeadlineConfiguration()
        guard usesNativeConfig || windowsConfiguration != nil else {
            previewError = "このHEADLINE DLLを使うにはWine設定が必要"
            return
        }
        _ = await playInstallationEvent(
            .shiori(id: "OnHeadlinesenseBegin", references: [
                0: headline.name,
                1: sourceURL.absoluteString
            ]),
            session: headlineSession,
            balloon: headlineBalloon
        )

        let cacheURL = ContentRoot.headlineCacheURL(for: headline)
        let incomingURL = cacheURL.deletingLastPathComponent().appending(
            path: "incoming-\(UUID().uuidString).html",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: incomingURL) }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try await NetworkFetchClient(maximumBytes: 5 * 1024 * 1024).fetch(sourceURL)
            try data.write(to: incomingURL, options: .atomic)
            let items: [HeadlineSensorItem] = try await Task.detached {
                if usesNativeConfig {
                    return try ConfigHeadlineSensor().analyze(
                        headline: headline,
                        oldData: try? Data(contentsOf: cacheURL),
                        newData: data
                    )
                }
                guard let windowsConfiguration else { return [] }
                return try WindowsHeadlineSensor(configuration: windowsConfiguration).analyze(
                    headline: headline,
                    oldFileURL: FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL : nil,
                    newFileURL: incomingURL
                ).items
            }.value
            try data.write(to: cacheURL, options: .atomic)

            let displayedItems = Array(items.prefix(50))
            guard !displayedItems.isEmpty else {
                _ = await playInstallationEvent(
                    .shiori(id: "OnHeadlinesenseComplete", references: [0: "no update"]),
                    session: headlineSession,
                    balloon: headlineBalloon
                )
                return
            }
            for (index, item) in displayedItems.enumerated() {
                let phase = if displayedItems.count == 1 {
                    "First and Last"
                } else if index == 0 {
                    "First"
                } else if index == displayedItems.count - 1 {
                    "Last"
                } else {
                    "Next"
                }
                _ = await playInstallationEvent(
                    .shiori(id: "OnHeadlinesense.OnFind", references: [
                        0: headline.name,
                        1: item.url ?? headline.openURL?.absoluteString ?? sourceURL.absoluteString,
                        2: phase,
                        3: sanitizeNetworkText(item.title)
                    ]),
                    session: headlineSession,
                    balloon: headlineBalloon
                )
            }
        } catch {
            let reason = error is NetworkFetchError ? "can't download" : "can't analyze"
            let handled = await playInstallationEvent(
                .shiori(id: "OnHeadlinesenseFailure", references: [0: reason]),
                session: headlineSession,
                balloon: headlineBalloon
            )
            if !handled {
                previewError = error.localizedDescription
            }
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
        if let command = request.value(for: "Command") {
            return handleMCPBridgeCommand(
                command,
                ghostID: request.value(for: "Ghost-ID"),
                script: request.value(for: "Script")
            )
        }
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

    private func handleMCPBridgeCommand(
        _ command: String,
        ghostID: String?,
        script: String?
    ) -> SSTPResponse {
        switch command {
        case "GetActiveGhostList":
            return jsonSSTPResponse(activeGhostDescriptions())
        case "GetExpressionTable":
            guard let ghostID,
                  let shell = activeShell(for: ghostID),
                  let definition = try? shellLoader.load(from: shell.directory)
            else { return SSTPResponse(statusCode: 404, reason: "Ghost Not Found") }
            let imageIDs = (try? FileManager.default.contentsOfDirectory(atPath: shell.directory.path))?
                .compactMap(surfaceID(fromImageFilename:)) ?? []
            let aliases = definition.surfaceAliases.flatMap { scope, entries in
                entries.map { name, surfaces in
                    ["scope": scope, "name": name, "surfaces": surfaces] as [String: Any]
                }
            }
            return jsonSSTPResponse([
                "ghost_id": ghostID,
                "shell": shell.name,
                "surfaces": Array(Set(definition.surfaces.keys).union(imageIDs)).sorted(),
                "aliases": aliases
            ])
        case "SakuraScript":
            guard let script else { return SSTPResponse(statusCode: 400, reason: "Script Required") }
            let sakuraScript = SakuraScript(rawValue: script.replacingOccurrences(of: "\\n", with: "\n"))
            if let ghostID, ghostID != currentGhost?.rootDirectory.lastPathComponent {
                guard let runtime = calledGhosts.values.first(where: {
                    $0.ghost.rootDirectory.lastPathComponent == ghostID
                }) else { return SSTPResponse(statusCode: 404, reason: "Ghost Not Found") }
                runtime.player.play(sakuraScript, balloon: runtime.balloon)
            } else if let balloon {
                scriptPlayer.play(sakuraScript, balloon: balloon)
            } else {
                return SSTPResponse(statusCode: 503, reason: "Service Unavailable")
            }
            return SSTPResponse(statusCode: 204, reason: "No Content")
        default:
            return SSTPResponse(statusCode: 400, reason: "Unknown Command")
        }
    }

    private func activeGhostDescriptions() -> [[String: Any]] {
        var ghosts: [(InstalledGhost, InstalledShell?, BalloonDefinition?)] = []
        if let currentGhost {
            ghosts.append((currentGhost, selectedShell, balloon))
        }
        ghosts.append(contentsOf: calledGhosts.values.map { ($0.ghost, $0.shell, $0.balloon) })
        return ghosts.map { ghost, shell, balloon in
            [
                "id": ghost.rootDirectory.lastPathComponent,
                "name": ghost.name,
                "sakura_name": ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
                "kero_name": ghost.characters.first(where: { $0.scope == 1 })?.name ?? "",
                "shell": shell?.name ?? "",
                "balloon": balloon?.name ?? ""
            ]
        }
    }

    private func activeShell(for ghostID: String) -> InstalledShell? {
        if currentGhost?.rootDirectory.lastPathComponent == ghostID {
            return selectedShell
        }
        return calledGhosts.values.first {
            $0.ghost.rootDirectory.lastPathComponent == ghostID
        }?.shell
    }

    private func jsonSSTPResponse(_ object: Any) -> SSTPResponse {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return SSTPResponse(statusCode: 500, reason: "Serialization Error") }
        return SSTPResponse(script: json)
    }

    private func surfaceID(fromImageFilename filename: String) -> Int? {
        let name = filename.lowercased()
        guard name.hasPrefix("surface"), name.hasSuffix(".png") else { return nil }
        return Int(name.dropFirst("surface".count).dropLast(".png".count))
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
            let statusToken = statusWindowController.show(
                urls.count == 1 ? "NARをインストール中…" : "NARを\(urls.count)件インストール中…"
            )
            defer { statusWindowController.hide(token: statusToken) }
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
                if selectedGhostID == nil {
                    selectedGhostID = model.ghosts.first?.id
                }
                showsOnboarding = model.ghosts.isEmpty
                updateDebugWindowVisibility()
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
                        0: installedItems.map(\.type.rawValue).joined(separator: separator),
                        1: installedItems.map(\.name).joined(separator: separator),
                        2: installedItems.map(\.url.lastPathComponent).joined(separator: separator)
                    ]),
                    session: installSession,
                    balloon: installBalloon
                )
                let completionToken = statusWindowController.show(
                    installedItems.count == 1
                        ? "「\(installedItems[0].name)」をインストールした"
                        : "\(installedItems.count)件をインストールした"
                )
                try? await Task.sleep(for: .seconds(2))
                statusWindowController.hide(token: completionToken)
            } catch {
                _ = await playInstallationEvent(
                    .shiori(id: "OnInstallFailure", references: [0: installFailureReason(error)]),
                    session: installSession,
                    balloon: installBalloon
                )
                previewError = error.localizedDescription
            }
        }
    }

    private func reloadCurrentGhost() {
        guard let activeGhost = currentGhost, !isTransitioningGhost else { return }
        Task {
            await model.load()
            guard let refreshedGhost = model.ghosts.first(where: {
                $0.id.standardizedFileURL == activeGhost.id.standardizedFileURL
            }) else {
                previewError = "再読み込み対象のゴーストが見つからない: \(activeGhost.name)"
                return
            }
            selectedGhostID = refreshedGhost.id
            await transition(to: refreshedGhost, forceReload: true)
        }
    }

    private func importSSPContents(from url: URL) {
        Task {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                _ = try await Task.detached {
                    try SSPContentImporter().importContents(
                        from: url,
                        ghostsDirectory: ContentRoot.ghostsDirectory,
                        balloonsDirectory: ContentRoot.balloonsDirectory
                    )
                }.value
                await model.load()
                installedBalloons = try balloonLoader.loadInstalled(from: ContentRoot.balloonsDirectory)
                if selectedGhostID == nil {
                    selectedGhostID = model.ghosts.first?.id
                }
                showsOnboarding = model.ghosts.isEmpty
                updateDebugWindowVisibility()
            } catch {
                previewError = error.localizedDescription
            }
        }
    }

    private func showContentFolder() {
        do {
            try FileManager.default.createDirectory(
                at: ContentRoot.contentDirectory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(ContentRoot.contentDirectory)
        } catch {
            previewError = error.localizedDescription
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
            for runtime in calledGhosts.values {
                await runtime.stop()
            }
            calledGhosts.removeAll()
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
    private var onOpenNar: (([URL]) -> Void)?
    private var pendingNarURLs: [URL] = []

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

    func setOpenNarHandler(_ handler: @escaping ([URL]) -> Void) {
        onOpenNar = handler
        guard !pendingNarURLs.isEmpty else { return }
        let urls = pendingNarURLs
        pendingNarURLs.removeAll()
        handler(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }.filter {
            $0.pathExtension.caseInsensitiveCompare("nar") == .orderedSame
        }
        guard !urls.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        if let onOpenNar {
            onOpenNar(urls)
        } else {
            pendingNarURLs.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }
}

private struct StartupGhostPicker: View {
    let ghosts: [InstalledGhost]
    @Binding var selection: URL?
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("起動するゴーストを選択")
                .font(.title2.weight(.semibold))
            List(ghosts, selection: $selection) { ghost in
                Text(ghost.name).tag(ghost.id)
            }
            HStack {
                Spacer()
                Button("起動", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 420, height: 360)
        .interactiveDismissDisabled()
    }
}

private extension Error {
    var isUserCancelledFileImport: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}

enum AppError: LocalizedError {
    case missingResource(String)
    case unsupportedShiori(String?)
    case windowsShioriUnavailable

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "アプリ内リソースが見つからない: \(name)"
        case let .unsupportedShiori(filename):
            "このゴーストのSHIORIにはまだ対応していない: \(filename ?? "SHIORI不明")"
        case .windowsShioriUnavailable:
            "FIRSTを起動するためのWine設定またはMateria互換ファイルが足りない。設定の「Windows SHIORI」とREADMEの追加手順を確認して"
        }
    }
}

private struct WelcomeView: View {
    let installNar: () -> Void
    let importSSP: () -> Void
    let showContentFolder: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)

            VStack(spacing: 8) {
                Text("Utataneへようこそ")
                    .font(.title.bold())
                Text("表示するゴーストがまだありません。NARをインストールするか、\n展開済みのSSPフォルダからゴーストとバルーンを取り込んでください。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button("NARをインストール…", action: installNar)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("SSPフォルダから取り込む…", action: importSSP)
                    .controlSize(.large)
                Button("コンテンツフォルダをFinderで表示", action: showContentFolder)
                    .buttonStyle(.link)
            }

            Text("SSP本体をZIPから展開したあと、そのフォルダを選択できます。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
        .frame(minWidth: 520, minHeight: 430)
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

enum ContentRoot {
    static var contentDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Utatane", directoryHint: .isDirectory)
    }

    static func prepareDirectories() throws {
        for directory in [
            contentDirectory,
            ghostsDirectory,
            balloonsDirectory,
            headlinesDirectory,
            materiaCompatibilityDirectory,
            materiaHostDirectory
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

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

    static func materiaFirstConfiguration(
        for ghost: InstalledGhost
    ) -> WindowsShioriProcessConfiguration? {
        guard let shioriFilename = ghost.shioriFilename else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default

        let wineExecutableURL: URL
        let winePrefixURL: URL
        let hostExecutableURL: URL
        let materiaExecutableURL: URL

        let defaults = UserDefaults.standard
        guard let winePath = environment["UTATANE_WINE_EXECUTABLE"]
            ?? defaults.string(forKey: "windowsShiori.wineExecutablePath"),
            !winePath.isEmpty,
            let prefixPath = environment["UTATANE_WINE_PREFIX"]
            ?? defaults.string(forKey: "windowsShiori.winePrefixPath"),
            !prefixPath.isEmpty
        else { return nil }
        wineExecutableURL = URL(filePath: winePath, directoryHint: .notDirectory)
        winePrefixURL = URL(filePath: prefixPath, directoryHint: .isDirectory)

        #if DEBUG
            let local = repositoryRoot.appending(path: "Content/Local", directoryHint: .isDirectory)
            hostExecutableURL = environment["UTATANE_MATERIA_HOST"].map {
                URL(filePath: $0, directoryHint: .notDirectory)
            } ?? local.appending(path: "MateriaBridge/materia.exe", directoryHint: .notDirectory)
            materiaExecutableURL = environment["UTATANE_MATERIA_EXE"].map {
                URL(filePath: $0, directoryHint: .notDirectory)
            } ?? local.appending(path: "materia.exe", directoryHint: .notDirectory)
        #else
            if let hostPath = environment["UTATANE_MATERIA_HOST"] {
                hostExecutableURL = URL(filePath: hostPath, directoryHint: .notDirectory)
            } else if let bundledHost = Bundle.main.url(
                forResource: "materia",
                withExtension: "exe",
                subdirectory: "MateriaHost"
            ) ?? Bundle.main.url(forResource: "materia", withExtension: "exe"),
                let installedHost = installMateriaHost(from: bundledHost)
            {
                hostExecutableURL = installedHost
            } else {
                return nil
            }
            materiaExecutableURL = environment["UTATANE_MATERIA_EXE"].map {
                URL(filePath: $0, directoryHint: .notDirectory)
            } ?? materiaCompatibilityDirectory.appending(
                path: "materia.exe",
                directoryHint: .notDirectory
            )
        #endif

        let shioriDLLURL = ghost.rootDirectory
            .appending(path: "ghost/master", directoryHint: .isDirectory)
            .appending(path: shioriFilename, directoryHint: .notDirectory)
        let required = [wineExecutableURL, winePrefixURL, hostExecutableURL, materiaExecutableURL, shioriDLLURL]
        guard required.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else { return nil }
        return WindowsShioriProcessConfiguration(
            wineExecutableURL: wineExecutableURL,
            winePrefixURL: winePrefixURL,
            hostExecutableURL: hostExecutableURL,
            materiaExecutableURL: materiaExecutableURL,
            shioriDLLURL: shioriDLLURL
        )
    }

    static func windowsHeadlineConfiguration() -> WindowsHeadlineHostConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        let fileManager = FileManager.default
        guard let winePath = environment["UTATANE_WINE_EXECUTABLE"]
            ?? defaults.string(forKey: "windowsShiori.wineExecutablePath"),
            !winePath.isEmpty,
            let prefixPath = environment["UTATANE_WINE_PREFIX"]
            ?? defaults.string(forKey: "windowsShiori.winePrefixPath"),
            !prefixPath.isEmpty
        else { return nil }

        let hostURL: URL
        if let override = environment["UTATANE_WINDOWS_DLL_HOST"] {
            hostURL = URL(filePath: override, directoryHint: .notDirectory)
        } else {
            #if DEBUG
                hostURL = repositoryRoot.appending(
                    path: "Content/Local/WindowsDLLBridge/utatane-dll-host.exe",
                    directoryHint: .notDirectory
                )
            #else
                guard let bundledHost = Bundle.main.url(
                    forResource: "utatane-dll-host",
                    withExtension: "exe"
                ) else { return nil }
                hostURL = bundledHost
            #endif
        }
        let wineURL = URL(filePath: winePath, directoryHint: .notDirectory)
        let prefixURL = URL(filePath: prefixPath, directoryHint: .isDirectory)
        guard [wineURL, prefixURL, hostURL].allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }
        return WindowsHeadlineHostConfiguration(
            wineExecutableURL: wineURL,
            winePrefixURL: prefixURL,
            hostExecutableURL: hostURL
        )
    }

    static func headlineCacheURL(for headline: InstalledHeadline) -> URL {
        contentDirectory
            .appending(path: "Cache/Headline", directoryHint: .isDirectory)
            .appending(path: headline.id.lastPathComponent, directoryHint: .isDirectory)
            .appending(path: "latest.html", directoryHint: .notDirectory)
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

        return contentDirectory.appending(path: "Ghosts", directoryHint: .isDirectory)
    }

    static var materiaCompatibilityDirectory: URL {
        contentDirectory.appending(
            path: "Compatibility/Materia",
            directoryHint: .isDirectory
        )
    }

    static var materiaHostDirectory: URL {
        materiaCompatibilityDirectory.appending(path: "Host", directoryHint: .isDirectory)
    }

    private static func installMateriaHost(from bundledURL: URL) -> URL? {
        let destination = materiaHostDirectory.appending(
            path: "materia.exe",
            directoryHint: .notDirectory
        )
        do {
            try FileManager.default.createDirectory(
                at: materiaHostDirectory,
                withIntermediateDirectories: true
            )
            let bundledData = try Data(contentsOf: bundledURL)
            if (try? Data(contentsOf: destination)) != bundledData {
                try bundledData.write(to: destination, options: .atomic)
            }
            return destination
        } catch {
            return nil
        }
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

        return contentDirectory.appending(path: "Balloons", directoryHint: .isDirectory)
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

        return contentDirectory.appending(path: "Headline", directoryHint: .isDirectory)
    }

    static var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

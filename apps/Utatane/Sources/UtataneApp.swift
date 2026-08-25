import AppKit
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import UtataneAI
import UtataneBalloon
import UtataneContent
import UtataneCore
import UtataneFirstNative
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
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var networkSettings: UtataneSettingsStore

    init() {
        Self.configureApplicationIcon()
        try? ContentRoot.prepareDirectories()
        try? ContentRoot.installBundledContent()
        let positionStore = WindowPositionStore()
        let surfaceWindowController = SurfaceWindowController(positionStore: positionStore)
        let balloonWindowController = BalloonWindowController(positionStore: positionStore)
        let repository = OverlayGhostRepository(repositories: ContentRoot.ghostReadDirectories.map {
            FileSystemGhostRepository(rootDirectory: $0)
        })
        model = GhostListModel(loadGhosts: LoadInstalledGhosts(repository: repository))
        shellLoader = ShellLoader()
        self.surfaceWindowController = surfaceWindowController
        self.balloonWindowController = balloonWindowController
        balloonLoader = BalloonLoader()
        selectionStore = ContentSelectionStore()
        sstpServer = SSTPServer()
        statusWindowController = StatusWindowController()
        alertController = ApplicationAlertController()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        _networkSettings = StateObject(wrappedValue: UtataneSettingsStore())
        scriptPlayer = SakuraScriptPlayer(
            surfaceWindowController: surfaceWindowController,
            balloonWindowController: balloonWindowController
        )
    }

    private static func configureApplicationIcon() {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }
        NSApplication.shared.applicationIconImage = icon
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
                balloonsDirectory: ContentRoot.balloonsDirectory,
                appUpdater: updaterController.updater
            )
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Utataneについて") {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }

    private func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: String(localized: "macOS向け伺か互換ベースウェア"),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Utatane",
            .applicationVersion: String(localized: "バージョン \(appVersion)"),
            .version: String(localized: "ビルド \(buildVersion)"),
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
    private let propertySystem = PropertySystem(configuration: .init(
        basewareName: "Utatane",
        basewareVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    ))
    @ObservedObject var networkSettings: UtataneSettingsStore
    let applicationDelegate: UtataneApplicationDelegate

    @Environment(\.openSettings) private var openSettings

    @State private var lastClickedRegion: String?
    @State private var balloon: BalloonDefinition?
    @State private var session: GhostSession?
    @State private var selectedGhostID: URL?
    @State private var currentGhost: InstalledGhost?
    @State private var selectedShell: InstalledShell?
    @State private var installedBalloons: [BalloonDefinition] = []
    @State private var installedHeadlines: [InstalledHeadline] = []
    @State private var isUpdatingContent = false
    @State private var debugWindow: NSWindow?
    @State private var showsOnboarding = false
    @State private var calledGhosts: [URL: CalledGhostRuntime] = [:]
    @State private var contentPickerController = ContentPickerWindowController()
    @State private var textInputWindowController = TextInputWindowController()
    @State private var isTransitioningGhost = false
    @State private var isClosingCurrentGhost = false
    @State private var weatherTask: Task<Void, Never>?
    @State private var webSocketManager = WebSocketSessionManager()
    @State private var lastGhostName: String = ""
    @State private var lastObjectName: String = ""
    @State private var inFlightHTTPTasks: [String: Task<Void, Never>] = [:]
    @State private var teachHistory: [String] = []
    @State private var lastClockMinute: DateComponents?
    @State private var pendingHourTimeSignal = false
    @State private var systemLoadSampler = MacOSSystemLoadSampler()
    @State private var configuredShellScalePercent: Int?
    @State private var configuredBalloonScalePercent: Int?
    @State private var gamepadMonitor = GamepadEventMonitor()
    @State private var systemInputMonitor = SystemInputEventMonitor()
    @State private var systemLoadDetector = SystemLoadTransitionDetector()

    var body: some View {
        Group {
            if showsOnboarding {
                WelcomeView(
                    installNar: selectAndInstallNar,
                    importSSP: selectAndImportSSPDirectory,
                    showContentFolder: showContentFolder
                )
            } else {
                DebugConsoleView(
                    model: model,
                    selectedGhostID: $selectedGhostID,
                    lastClickedRegion: lastClickedRegion,
                    isSessionAvailable: session != nil,
                    isReloadDisabled: currentGhost == nil || isTransitioningGhost,
                    onPlayRandomTalk: { sendEvent(.randomTalk) },
                    onAdvanceScript: { scriptPlayer.advance() },
                    onCancelScript: { scriptPlayer.cancel() },
                    onReloadGhost: { reloadCurrentGhost() },
                    onInstallNar: selectAndInstallNar,
                    onPlaySlowAnimation: {
                        surfaceWindowController.playAnimation(
                            id: 0,
                            minimumFrameDurationMilliseconds: 3000
                        )
                    }
                )
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
                if !model.ghosts.isEmpty {
                    showGhostPicker(requiresSelection: true)
                }
            case .random:
                selectedGhostID = model.ghosts.randomElement()?.id
            }
            configurePlayback()
            applyAppearance()
            gamepadMonitor.onEvent = { id, references in
                broadcastEvent(.shiori(id: id, references: references))
            }
            gamepadMonitor.start()
            systemInputMonitor.onEvent = { id, references in
                broadcastEvent(.shiori(id: id, references: references))
            }
            systemInputMonitor.start()
            do {
                try sstpServer.start { request in
                    await handleSSTP(request)
                }
            } catch {
                showError(error.localizedDescription)
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
                sendClockEvents(at: Date())
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let sample = systemLoadSampler.sample() else { continue }
                dispatchSystemLoadEvents(sample: sample)
            }
        }
        .task(id: selectedGhostID) {
            guard let selectedGhostID,
                  let ghost = model.ghosts.first(where: { $0.id == selectedGhostID })
            else { return }
            await transition(to: ghost)
        }
        .task(id: "\(selectedGhostID?.path ?? "")-\(balloon?.directory.path ?? "")-\(networkSettings.automaticContentUpdate)-\(networkSettings.contentUpdateIntervalDays)") {
            guard networkSettings.automaticContentUpdate else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if let ghost = currentGhost,
               networkSettings.shouldAutomaticallyUpdateContent(
                   kind: .ghost,
                   directoryName: ghost.rootDirectory.lastPathComponent
               )
            {
                await updateCurrentGhost(isAutomatic: true)
            }
            guard !Task.isCancelled else { return }
            if let balloon,
               networkSettings.shouldAutomaticallyUpdateContent(
                   kind: .balloon,
                   directoryName: balloon.directory.lastPathComponent
               )
            {
                await updateCurrentBalloon(isAutomatic: true)
            }
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
        .onChange(of: networkSettings.showsDebugWindow) { _, isShown in
            updateDebugWindowVisibility(bringForward: isShown)
        }
        .onChange(of: showsOnboarding) {
            updateDebugWindowVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let closingWindow = notification.object as? NSWindow,
                  closingWindow === debugWindow,
                  !showsOnboarding
            else { return }
            networkSettings.showsDebugWindow = false
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in
            broadcastEvent(.shiori(id: "OnDisplayChange", references: displayChangeReferences()))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            broadcastEvent(.shiori(id: "OnWindowStateMinimize", references: [0: "system"]))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
            broadcastEvent(.shiori(id: "OnWindowStateRestore", references: [0: "system"]))
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            broadcastEvent(.shiori(id: "OnDarkTheme", references: darkThemeReferences()))
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.willSleepNotification
        )) { _ in
            broadcastEvent(.shiori(id: "OnSysSuspend", references: [:]))
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didWakeNotification
        )) { _ in
            broadcastEvent(.shiori(id: "OnSysResume", references: [0: "normal"]))
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.sessionDidResignActiveNotification
        )) { _ in
            broadcastEvent(.shiori(id: "OnSessionLock", references: [:]))
            broadcastEvent(.shiori(id: "OnSessionDisconnect", references: [:]))
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.sessionDidBecomeActiveNotification
        )) { _ in
            broadcastEvent(.shiori(id: "OnSessionUnlock", references: [:]))
            broadcastEvent(.shiori(id: "OnSessionReconnect", references: [:]))
        }
    }

    private func registerCurrentGhostProperties() async {
        var values = MacOSPropertySnapshot.values()
        values["ghostlist.count"] = String(model.ghosts.count)
        for (index, ghost) in model.ghosts.enumerated() {
            values["ghostlist.index(\(index)).name"] = ghost.name
            values["ghostlist.index(\(index)).sakuraname"] = ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name
            values["ghostlist.index(\(index)).keroname"] = ghost.characters.first(where: { $0.scope == 1 })?.name ?? ""
            values["ghostlist.index(\(index)).path"] = ghost.rootDirectory.path
            values["ghostlist.index(\(index)).index"] = String(index)
        }
        if let currentGhost {
            values["currentghost.name"] = currentGhost.name
            values["currentghost.sakuraname"] = currentGhost.characters.first(where: { $0.scope == 0 })?.name ?? currentGhost.name
            values["currentghost.keroname"] = currentGhost.characters.first(where: { $0.scope == 1 })?.name ?? ""
            values["currentghost.path"] = currentGhost.rootDirectory.path
            values["currentghost.shelllist.count"] = String(currentGhost.shells.count)
            for (index, shell) in currentGhost.shells.enumerated() {
                let prefix = "currentghost.shelllist.index(\(index))"
                values["\(prefix).name"] = shell.name
                values["\(prefix).path"] = shell.directory.path
                values["\(prefix).index"] = String(index)
                values["currentghost.shelllist(\(shell.name)).name"] = shell.name
                values["currentghost.shelllist(\(shell.name)).path"] = shell.directory.path
                values["currentghost.shelllist(\(shell.name)).index"] = String(index)
            }
            if let selectedShell {
                values["currentghost.shelllist.current.name"] = selectedShell.name
                values["currentghost.shelllist.current.path"] = selectedShell.directory.path
                values["currentghost.shelllist.current.index"] = String(
                    currentGhost.shells.firstIndex(of: selectedShell) ?? 0
                )
            }
        }
        await propertySystem.register(values: values)
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
                AppLogStore.shared.error(
                    "SHIORIイベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Event: \(event)\nError: \(error)",
                    ghostName: currentGhost?.name
                )
                showError(error.localizedDescription)
            }
        }
    }

    private func broadcastEvent(_ event: GhostEvent) {
        sendEvent(event)
        for runtime in calledGhosts.values {
            runtime.send(event)
        }
    }

    private func dispatchSystemLoadEvents(sample: SystemLoadPercentages) {
        let transitions = systemLoadDetector.consume(sample)
        if transitions.cpuBecameHigh {
            broadcastEvent(.shiori(id: "OnCPULoadHigh", references: [0: String(sample.cpu)]))
        }
        if transitions.cpuBecameLow {
            broadcastEvent(.shiori(id: "OnCPULoadLow", references: [0: String(sample.cpu)]))
        }
        if transitions.memoryBecameHigh {
            broadcastEvent(.shiori(id: "OnMemoryLoadHigh", references: [0: String(sample.memory)]))
        }
        if transitions.memoryBecameLow {
            broadcastEvent(.shiori(id: "OnMemoryLoadLow", references: [0: String(sample.memory)]))
        }
    }

    private func displayChangeReferences() -> [Int: String] {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return [:] }
        let bitsPerSample = (screen.deviceDescription[.bitsPerSample] as? NSNumber)?.intValue ?? 8
        return [
            0: String(bitsPerSample * 4),
            1: String(Int(screen.frame.width)),
            2: String(Int(screen.frame.height))
        ]
    }

    private func sendFileDropEvents(scope: Int, urls: [URL]) {
        guard !urls.isEmpty, let session, let balloon else { return }
        let joinedReferences = [
            0: urls.map(\.path).joined(separator: "\u{1}"),
            1: String(scope),
            2: urls.map(droppedFileMIMEType).joined(separator: "\u{1}")
        ]
        for url in urls where url.hasDirectoryPath {
            sendEvent(.shiori(id: "OnDirectoryDrop", references: [0: url.path, 1: String(scope)]))
        }
        Task {
            do {
                let response = try await session.response(for: .shiori(
                    id: "OnFileDrop2",
                    references: joinedReferences
                ))
                if let script = response?.script {
                    scriptPlayer.play(script, balloon: balloon)
                    if let response {
                        forwardCommunication(from: currentGhost, response: response)
                    }
                    return
                }
                guard let url = urls.first,
                      url.pathExtension.caseInsensitiveCompare("nar") != .orderedSame,
                      let viewerEventID = droppedFileViewerEventID(url),
                      NSWorkspace.shared.open(url)
                else { return }
                sendEvent(.shiori(id: viewerEventID, references: joinedReferences))
            } catch {
                AppLogStore.shared.error(
                    "ファイルドロップ処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Files: \(urls.map(\.path).joined(separator: "\n"))"
                )
            }
        }
    }

    private func handleURLDrop(scope: Int, url: URL) {
        if handleXUkagakaLink(url) {
            return
        }
        guard let session, let balloon else { return }
        let plannedAction = url.pathExtension.caseInsensitiveCompare("nar") == .orderedSame ? "nar" : "unknown"
        let queryReferences = [
            0: url.absoluteString,
            1: String(scope),
            2: droppedFileMIMEType(url),
            3: plannedAction
        ]
        Task {
            do {
                if let response = try await session.response(for: .shiori(
                    id: "OnURLQuery",
                    references: queryReferences
                )), let script = response.script {
                    scriptPlayer.play(script, balloon: balloon)
                    forwardCommunication(from: currentGhost, response: response)
                    return
                }
                guard plannedAction == "nar" else { return }
                sendEvent(.shiori(id: "OnURLDropping", references: [
                    0: url.absoluteString, 1: String(scope)
                ]))
                let localURL = try await downloadDroppedNar(from: url)
                sendEvent(.shiori(id: "OnURLDropped", references: [
                    0: localURL.path, 1: url.absoluteString, 2: String(scope)
                ]))
                installNars(from: [localURL])
            } catch {
                sendEvent(.shiori(id: "OnURLDropFailure", references: [
                    0: "", 1: urlDropFailureReason(error), 2: url.absoluteString, 3: String(scope)
                ]))
            }
        }
    }

    private func handleXUkagakaLink(_ url: URL) -> Bool {
        guard let values = xUkagakaLinkValues(url),
              values["type"]?.caseInsensitiveCompare("event") == .orderedSame,
              let target = values["ghost"], let info = values["info"]
        else { return false }
        if let currentGhost, ghost(currentGhost, matches: target) {
            sendEvent(.shiori(id: "OnXUkagakaLinkOpen", references: [0: info]))
        } else if let runtime = calledGhosts.values.first(where: { ghost($0.ghost, matches: target) }) {
            runtime.send(.shiori(id: "OnXUkagakaLinkOpen", references: [0: info]))
        }
        return true
    }

    private func sendSecondChange() {
        guard !isTransitioningGhost else { return }
        let references = secondChangeReferences(for: surfaceWindowController)
        if let session {
            let canTalk = scriptPlayer.canTalk
            var primaryReferences = references
            // UKADOC / SSP standard: 1 for talkable, 0 while dialogue is being played.
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
                    AppLogStore.shared.error(
                        "OnSecondChangeエラー: \(error.localizedDescription)",
                        category: "SHIORI",
                        details: String(describing: error),
                        ghostName: currentGhost?.name
                    )
                    showError(error.localizedDescription)
                }
            }
        }
        for runtime in calledGhosts.values {
            runtime.sendSecondChange(references: secondChangeReferences(for: runtime.surfaceController))
        }
    }

    private func sendClockEvents(at date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        defer { lastClockMinute = components }
        guard let previous = lastClockMinute else { return }

        let minuteChanged = previous.year != components.year
            || previous.month != components.month
            || previous.day != components.day
            || previous.hour != components.hour
            || previous.minute != components.minute
        if minuteChanged {
            sendTimedEvent(id: "OnMinuteChange", waitsUntilTalkable: false)
        }
        if previous.hour != components.hour {
            pendingHourTimeSignal = true
            for runtime in calledGhosts.values {
                runtime.scheduleHourTimeSignal()
            }
        }
        if pendingHourTimeSignal, scriptPlayer.canTalk {
            pendingHourTimeSignal = false
            sendTimedEvent(id: "OnHourTimeSignal", waitsUntilTalkable: true, includesCalledGhosts: false)
        }
        for runtime in calledGhosts.values {
            runtime.flushHourTimeSignal(references: secondChangeReferences(for: runtime.surfaceController))
        }
    }

    private func sendTimedEvent(
        id: String,
        waitsUntilTalkable: Bool,
        includesCalledGhosts: Bool = true
    ) {
        let canTalk = scriptPlayer.canTalk
        guard !waitsUntilTalkable || canTalk else { return }
        var references = secondChangeReferences(for: surfaceWindowController)
        references[3] = canTalk ? "1" : "0"
        if let session {
            Task {
                guard let response = try? await session.response(for: .shiori(id: id, references: references)) else {
                    return
                }
                guard canTalk else { return }
                if let script = response.script, let balloon {
                    scriptPlayer.play(script, balloon: balloon)
                }
                forwardCommunication(from: currentGhost, response: response)
            }
        }
        guard includesCalledGhosts else { return }
        for runtime in calledGhosts.values {
            runtime.sendTimedEvent(
                id: id,
                references: secondChangeReferences(for: runtime.surfaceController),
                waitsUntilTalkable: waitsUntilTalkable
            )
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

    private func currentSurfaceReferences(for controller: SurfaceWindowController) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: [0, 1].compactMap { scope in
            controller.surfaceID(for: scope).map { (scope, String($0)) }
        })
    }

    private func transition(to ghost: InstalledGhost, forceReload: Bool = false) async {
        guard forceReload || currentGhost?.id != ghost.id else { return }
        let previousGhost = currentGhost
        let statusToken = statusWindowController.show("「\(ghost.name)」を起動中…")
        defer { statusWindowController.hide(token: statusToken) }
        isTransitioningGhost = true
        defer { isTransitioningGhost = false }
        if let called = calledGhosts.removeValue(forKey: ghost.id) {
            _ = await called.stop()
        }
        await closeCurrentGhost(reason: .ghostChanging(name: ghost.name))
        guard !Task.isCancelled else { return }
        switch await activate(ghost) {
        case .success:
            AppLogStore.shared.info("「\(ghost.name)」の起動が完了しました", category: "Ghost", ghostName: ghost.name)
            return
        case let .failure(error):
            AppLogStore.shared.error(
                "「\(ghost.name)」の起動に失敗しました: \(error.localizedDescription)",
                category: "Ghost",
                details: String(describing: error),
                ghostName: ghost.name
            )
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
                    AppLogStore.shared.warning(
                        "起動失敗のため「\(fallback.name)」へ切り替えました",
                        category: "Ghost",
                        details: "Failed ghost: \(ghost.name)\nError: \(error)",
                        ghostName: ghost.name
                    )
                    showError("「\(ghost.name)」は起動できませんでした。現在は代わりに「\(fallback.name)」を表示しています。\n\n原因: \(error.localizedDescription)")
                    return
                }
            }
            currentGhost = nil
            selectedGhostID = nil
            showError("「\(ghost.name)」を起動できず、代わりに起動できるゴーストも見つからなかった。\n\(error.localizedDescription)")
        }
    }

    private func closeCurrentGhost(reason: GhostStopReason) async {
        guard let activeSession = session else { return }
        session = nil
        configureContextMenu()

        do {
            _ = try? await activeSession.handle(event: .shiori(id: "OnDestroy", references: [:]))
            guard let closeScript = try await activeSession.stop(reason: reason), let balloon else { return }
            await scriptPlayer.playAndWait(closeScript, balloon: balloon)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(1))
        } catch {
            AppLogStore.shared.warning(
                "ゴースト終了時のイベント処理エラー: \(error.localizedDescription)",
                category: "Ghost",
                details: String(describing: error),
                ghostName: currentGhost?.name
            )
            if !isTransitioningGhost {
                showError(error.localizedDescription)
            }
        }
    }

    private func activate(_ ghost: InstalledGhost) async -> Result<Void, any Error> {
        AppLogStore.shared.info("「\(ghost.name)」の起動を開始しました", category: "Ghost", ghostName: ghost.name)
        scriptPlayer.cancel()
        surfaceWindowController.hideAll()
        surfaceWindowController.setPresentationHidden(true)
        session = nil
        balloon = nil
        currentGhost = ghost
        teachHistory = []
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
                guard !scriptPlayer.isTimeCritical else { return }
                if case .click = event.kind {
                    lastClickedRegion = "scope \(event.scope): \(event.region ?? "範囲外")"
                }
                sendEvent(.mouse(event))
            }
            surfaceWindowController.onSurfaceChange = { scope, previous, current in
                sendEvent(.shiori(
                    id: "OnSurfaceChange",
                    references: currentSurfaceReferences(for: surfaceWindowController)
                ))
                notifyOtherGhostsSurfaceChange(
                    ghost: ghost,
                    controller: surfaceWindowController,
                    scope: scope,
                    previous: previous,
                    current: current,
                    excluding: ghost.id
                )
            }
            surfaceWindowController.onNarDrop = { _, urls in
                installNars(from: urls)
            }
            surfaceWindowController.onFileDropping = { scope, urls in
                guard let first = urls.first else { return }
                sendEvent(.shiori(id: "OnFileDropping", references: [0: first.path, 1: String(scope)]))
            }
            surfaceWindowController.onFileDrop = { scope, urls in
                sendFileDropEvents(scope: scope, urls: urls)
            }
            surfaceWindowController.onURLDropping = { scope, url in
                sendEvent(.shiori(id: "OnURLDragDropping", references: [
                    0: url.absoluteString, 1: String(scope)
                ]))
            }
            surfaceWindowController.onURLDrop = { scope, url in
                handleURLDrop(scope: scope, url: url)
            }
            surfaceWindowController.onTextDrop = { scope, value in
                sendEvent(.shiori(id: "OnTextDrop", references: [
                    0: value.replacingOccurrences(of: "\n", with: "\u{1}"), 1: String(scope)
                ]))
            }

            installedBalloons = try balloonLoader.loadInstalled(from: ContentRoot.balloonReadDirectories)
            let loadedBalloon = selectionStore.resolveBalloon(
                for: ghost,
                from: installedBalloons,
                defaultDirectoryName: networkSettings.defaultBalloonDirectoryName
            )
            guard let loadedBalloon else {
                throw AppError.missingResource("balloon")
            }
            balloon = loadedBalloon
            configureContextMenu()
            scriptPlayer.onError = { error in
                AppLogStore.shared.error(
                    "スクリプト実行エラー: \(error.localizedDescription)",
                    category: "Script",
                    details: String(describing: error),
                    ghostName: ghost.name
                )
                showError(error.localizedDescription)
            }
            scriptPlayer.onDialogueContent = {
                surfaceWindowController.setPresentationHidden(false)
            }
            scriptPlayer.onPlaybackFinished = {
                surfaceWindowController.setPresentationHidden(false)
            }
            scriptPlayer.onDialogueDismissed = {
                sendEvent(.shiori(
                    id: "OnSurfaceRestore",
                    references: currentSurfaceReferences(for: surfaceWindowController)
                ))
            }
            scriptPlayer.onBalloonClose = { script in
                sendEvent(.shiori(id: "OnBalloonClose", references: [0: script]))
            }
            scriptPlayer.onBalloonTimeout = { script in
                sendEvent(.shiori(id: "OnBalloonTimeout", references: [0: script, 1: "0"]))
            }
            scriptPlayer.onChoice = { id, arguments in
                if ["configuration", "configurationdialog"].contains(id.lowercased()) {
                    networkSettings.selectedPane = .advanced
                    openSettings()
                } else if id.caseInsensitiveCompare("ghostexplorer") == .orderedSame {
                    showGhostPicker()
                } else if id.caseInsensitiveCompare("shellexplorer") == .orderedSame {
                    showShellPicker()
                } else if id.caseInsensitiveCompare("balloonexplorer") == .orderedSame {
                    showBalloonPicker()
                } else if id.caseInsensitiveCompare("On_Update") == .orderedSame {
                    Task { await updateCurrentGhost() }
                } else if let url = URL(string: id), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                } else if id.caseInsensitiveCompare("CANCEL_NOTALK") == .orderedSame {
                    scriptPlayer.cancel()
                } else {
                    sendEvent(.choice(id: id, arguments: arguments))
                }
            }
            scriptPlayer.onChoiceSelectEx = { label, id, arguments in
                sendEvent(.shiori(id: "OnChoiceSelectEx", references: Dictionary(
                    uniqueKeysWithValues: ([label, id] + arguments).enumerated().map { ($0.offset, $0.element) }
                )))
            }
            scriptPlayer.onAnchorSelectEx = { label, id, arguments in
                sendEvent(.shiori(id: "OnAnchorSelectEx", references: Dictionary(
                    uniqueKeysWithValues: ([label, id] + arguments).enumerated().map { ($0.offset, $0.element) }
                )))
            }
            scriptPlayer.onAnchorSelect = { id in
                sendEvent(.shiori(id: "OnAnchorSelect", references: [0: id]))
            }
            scriptPlayer.onChoiceEnter = { label, id, arguments in
                sendEvent(.shiori(id: "OnChoiceEnter", references: linkEventReferences(label, id, arguments)))
            }
            scriptPlayer.onChoiceHover = { label, id, arguments in
                sendEvent(.shiori(id: "OnChoiceHover", references: linkEventReferences(label, id, arguments)))
            }
            scriptPlayer.onAnchorEnter = { label, id, arguments in
                sendEvent(.shiori(id: "OnAnchorEnter", references: linkEventReferences(label, id, arguments)))
            }
            scriptPlayer.onAnchorHover = { label, id, arguments in
                sendEvent(.shiori(id: "OnAnchorHover", references: linkEventReferences(label, id, arguments)))
            }
            scriptPlayer.onSoundStop = { file, reason in
                sendEvent(.shiori(id: "OnSoundStop", references: [0: file, 1: reason]))
            }
            scriptPlayer.onSoundError = { file, error in
                let nsError = error as NSError
                sendEvent(.shiori(id: "OnSoundError", references: [
                    0: "play", 1: String(nsError.code), 2: file, 3: error.localizedDescription
                ]))
            }
            scriptPlayer.onChoiceTimeout = { script in
                sendEvent(.shiori(id: "OnChoiceTimeout", references: [0: script]))
            }
            scriptPlayer.onOpen = { target in
                guard let url = URL(string: target),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme)
                else { return }
                NSWorkspace.shared.open(url)
            }
            scriptPlayer.configure(resourceBaseDirectory: ghost.rootDirectory.appending(
                path: "ghost/master",
                directoryHint: .isDirectory
            ))
            let mainName = ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name
            scriptPlayer.configure(environmentVariables: [
                "selfname": mainName,
                "selfname2": mainName,
                "keroname": ghost.characters.first(where: { $0.scope == 1 })?.name ?? "",
                "lastghostname": lastGhostName,
                "lastobjectname": lastObjectName
            ])
            scriptPlayer.onContentAction = { action in
                handleContentAction(action)
            }
            scriptPlayer.onOtherEvent = { target, id, arguments, reflectsResponse in
                await handleOtherEvent(
                    target: target,
                    id: id,
                    arguments: arguments,
                    reflectsResponse: reflectsResponse,
                    excluding: ghost.id
                )
            }
            scriptPlayer.onOtherGhostTalk = { target, script in
                handleOtherGhostTalk(target: target, script: script, excluding: ghost.id)
            }
            scriptPlayer.onOtherSurfaceChange = { target, scope, surfaceID in
                handleOtherSurfaceChange(target: target, scope: scope, surfaceID: surfaceID, excluding: ghost.id)
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
            scriptPlayer.onPropertyValue = { property in
                await registerCurrentGhostProperties()
                return try? await propertySystem.value(for: property)
            }
            scriptPlayer.onGetProperties = { eventID, properties in
                guard let activeSession = session else { return nil }
                await registerCurrentGhostProperties()
                let values = await propertySystem.values(for: properties)
                return try? await activeSession.handle(event: .shiori(
                    id: eventID,
                    references: Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset, $0.element) })
                ))
            }
            scriptPlayer.onSetProperty = { property, value in
                try? await propertySystem.setValue(value, for: property)
            }
            scriptPlayer.onInputBox = { id, _, initialValue in
                guard let activeSession = session else { return nil }
                guard let value = await textInputWindowController.showPrompt(
                    id: id,
                    title: String(localized: "文字を入力"),
                    initialValue: initialValue,
                    actionTitle: String(localized: "OK")
                ) else {
                    return try? await activeSession.handle(event: .shiori(
                        id: "OnUserInputCancel",
                        references: [0: id, 1: "close", 2: ""]
                    ))
                }
                if id.hasPrefix("On") {
                    return try? await activeSession.handle(event: .shiori(
                        id: id,
                        references: [0: value, 1: ""]
                    ))
                }
                return try? await activeSession.handle(event: .shiori(
                    id: "OnUserInput",
                    references: [0: id, 1: value, 2: ""]
                ))
            }
            scriptPlayer.onCloseInputBox = { id in
                textInputWindowController.close(id: id)
            }
            scriptPlayer.onCommunicateBox = { initialValue in
                guard let activeSession = session else { return nil }
                guard let value = await textInputWindowController.showPrompt(
                    title: String(localized: "文字を入力"),
                    initialValue: initialValue,
                    actionTitle: String(localized: "OK")
                ) else {
                    return try? await activeSession.handle(event: .shiori(
                        id: "OnCommunicateInputCancel",
                        references: [0: "", 1: "cancel"]
                    ))
                }
                return try? await activeSession.handle(event: .shiori(
                    id: "OnCommunicate",
                    references: [0: "user", 1: value]
                ))
            }
            scriptPlayer.onTeachBox = { initialValue in
                guard let activeSession = session else { return nil }
                _ = try? await activeSession.handle(event: .shiori(
                    id: "OnTeachStart",
                    references: [:]
                ))
                guard let value = await textInputWindowController.showPrompt(
                    title: String(localized: "文字を入力"),
                    initialValue: initialValue,
                    actionTitle: String(localized: "OK")
                ) else {
                    return try? await activeSession.handle(event: .shiori(
                        id: "OnTeachInputCancel",
                        references: [0: "", 1: "cancel"]
                    ))
                }
                teachHistory.append(value)
                return try? await activeSession.handle(event: .shiori(
                    id: "OnTeach",
                    references: Dictionary(uniqueKeysWithValues: teachHistory.enumerated().map {
                        ($0.offset, $0.element)
                    })
                ))
            }
            scriptPlayer.onHTTP = { request in
                if request.waitsForCompletion {
                    return await handleHTTP(request)
                }
                cancelHTTP(url: request.url)
                inFlightHTTPTasks[request.url] = Task {
                    let response = await handleHTTP(request)
                    guard !Task.isCancelled else { return }
                    inFlightHTTPTasks.removeValue(forKey: request.url)
                    if let response, let balloon, !response.rawValue.isEmpty {
                        scriptPlayer.play(response, balloon: balloon)
                    }
                }
                return nil
            }
            scriptPlayer.onCancelHTTP = { url in
                cancelHTTP(url: url)
            }
            scriptPlayer.onNetworkDiagnostic = { command in
                await handleNetworkDiagnostic(command)
            }
            scriptPlayer.onWebSocket = { command in
                await handleWebSocket(command)
            }
            scriptPlayer.onArchive = { command in
                await handleArchive(command)
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
            _ = try? await ghostSession.start(event: .shiori(id: "OnInitialize", references: [:]))
            let shellDefinition = try shellLoader.load(from: shellChoice.directory)
            for event in startupInformationEvents(
                ghost: ghost,
                shell: shellChoice,
                balloon: loadedBalloon,
                shellDefinition: shellDefinition,
                installedGhosts: model.ghosts,
                installedBalloons: installedBalloons,
                installedHeadlines: installedHeadlines,
                surfaceWindowNumbers: surfaceWindowController.windowNumbers,
                balloonWindowNumbers: balloonWindowController.windowNumbers,
                otherGhosts: calledGhosts.values.map { runtime in
                    [
                        runtime.ghost.characters.first(where: { $0.scope == 0 })?.name ?? runtime.ghost.name,
                        String(runtime.surfaceController.surfaceID(for: 0) ?? -1),
                        String(runtime.surfaceController.surfaceID(for: 1) ?? -1)
                    ].joined(separator: "\u{1}")
                }
            ) {
                _ = try? await ghostSession.handle(event: .shiori(id: event.id, references: event.references))
            }
            if let script = try await ghostSession.handle(event: .shiori(
                id: "OnBoot",
                references: [0: shellChoice.name]
            )) {
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
        if AIGhostManifestLoader.supports(masterDirectoryURL: masterDirectory) {
            let baseURL = networkSettings.aiBaseURL.isEmpty
                ? nil : URL(string: networkSettings.aiBaseURL)
            let configuration = AIProviderConfiguration(
                kind: networkSettings.aiProvider,
                baseURL: baseURL,
                model: networkSettings.aiModel,
                apiKey: networkSettings.aiAPIKey
            )
            return try AIPersonalityEngine(
                manifest: AIGhostManifestLoader.load(masterDirectoryURL: masterDirectory),
                client: AIProviderClientFactory.make(configuration: configuration)
            )
        }
        if NativeYayaPersonalityEngine.supports(masterDirectoryURL: masterDirectory) {
            return try NativeYayaPersonalityEngine(
                masterDirectoryURL: ContentRoot.writableYayaMasterDirectory(
                    for: ghost,
                    source: masterDirectory
                )
            )
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
        if NativeFirstPersonalityEngine.supports(masterDirectoryURL: masterDirectory) {
            return try NativeFirstPersonalityEngine(masterDirectoryURL: masterDirectory)
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

    private func cancelHTTP(url: String?) {
        if let url {
            inFlightHTTPTasks.removeValue(forKey: url)?.cancel()
        } else {
            for (_, task) in inFlightHTTPTasks {
                task.cancel()
            }
            inFlightHTTPTasks.removeAll()
        }
    }

    private func handleHTTP(_ command: SakuraScriptHTTPRequest) async -> SakuraScript? {
        guard let activeSession = session, let currentGhost else { return nil }
        guard var url = URL(string: command.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        if command.method == "GET", !command.parameters.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            let suffix = command.parameters.joined(separator: "&")
            components.percentEncodedQuery = [components.percentEncodedQuery, suffix]
                .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: "&")
            url = components.url ?? url
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = command.method
            request.timeoutInterval = min(max(command.timeoutSeconds ?? 60, 0.1), 300)
            for header in command.headers {
                let fields = header.split(separator: ":", maxSplits: 1).map(String.init)
                if fields.count == 2 {
                    request.setValue(fields[1].trimmingCharacters(in: .whitespaces), forHTTPHeaderField: fields[0])
                }
            }
            if !command.parameters.isEmpty, command.method != "GET" {
                request.httpBody = Data(command.parameters.joined(separator: "&").utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            guard (200 ..< 300).contains(statusCode) else { throw URLError(.badServerResponse) }

            if command.isFeed {
                do {
                    let feed = try RSSFeedClient.parse(data)
                    guard let eventID = command.eventID else { return nil }
                    let successID = eventID.hasPrefix("On") ? eventID : "OnExecuteRSSComplete"
                    var references: [Int: String] = [:]
                    for (index, item) in feed.items.enumerated() {
                        references[index] = [
                            item.title,
                            item.link,
                            item.published,
                            item.author,
                            item.summary
                        ].joined(separator: "\u{1}")
                    }
                    return try await activeSession.handle(event: .shiori(id: successID, references: references))
                } catch {
                    guard let eventID = command.eventID else { return nil }
                    let failureID = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExecuteRSSFailure"
                    return try? await activeSession.handle(event: .shiori(id: failureID, references: [
                        0: command.url,
                        4: "parse"
                    ]))
                }
            }

            let result: String
            switch command.output {
            case let .file(requestedName):
                let masterDirectory = currentGhost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
                let varDirectory = masterDirectory.appending(path: "var", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: varDirectory, withIntermediateDirectories: true)
                let fallbackName = url.lastPathComponent.isEmpty ? "index.html" : url.lastPathComponent
                let filename = URL(fileURLWithPath: requestedName ?? fallbackName).lastPathComponent
                let destination = varDirectory.appending(path: filename, directoryHint: .notDirectory)
                try data.write(to: destination, options: .atomic)
                result = destination.path
            case let .memory(characterEncoding):
                result = Self.httpResponseText(data.prefix(128 * 1024), encoding: characterEncoding)
                    .replacingOccurrences(of: "\r\n", with: "\u{1}")
                    .replacingOccurrences(of: "\r", with: "\u{1}")
                    .replacingOccurrences(of: "\n", with: "\u{1}")
            }
            guard let eventID = command.eventID else { return nil }
            let successID = eventID.hasPrefix("On") ? eventID : "OnExecuteHTTPComplete"
            return try await activeSession.handle(event: .shiori(id: successID, references: [
                0: command.method,
                1: eventID,
                2: command.url,
                3: result,
                4: String(statusCode),
                5: httpResponse?.value(forHTTPHeaderField: "Set-Cookie") ?? "",
                6: Self.httpResponseHeaders(httpResponse)
            ]))
        } catch {
            guard let eventID = command.eventID else { return nil }
            let failureID = eventID.hasPrefix("On") ? "\(eventID)Failure" : (command.isFeed ? "OnExecuteRSSFailure" : "OnExecuteHTTPFailure")
            return try? await activeSession.handle(event: .shiori(id: failureID, references: [
                0: command.method,
                1: eventID,
                2: command.url,
                4: String(describing: error)
            ]))
        }
    }

    private static func httpResponseHeaders(_ response: HTTPURLResponse?) -> String {
        response?.allHeaderFields
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\u{1}") ?? ""
    }

    private func handleArchive(_ command: SakuraScriptArchiveCommand) async -> SakuraScript? {
        guard let activeSession = session, let currentGhost else { return nil }
        let runner = ArchiveOperationRunner()
        let masterDirectory = currentGhost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)

        func resolvePath(_ path: String) -> URL {
            let candidate = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : masterDirectory.appending(path: path)
            let rootPath = masterDirectory.resolvingSymlinksInPath().standardizedFileURL.path
            let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
                return masterDirectory.appending(path: "var/.utatane-rejected-path")
            }
            return candidate
        }

        switch command {
        case let .extract(archivePath, destinationPath, eventID, password):
            let archiveURL = resolvePath(archivePath)
            let destURL = resolvePath(destinationPath)
            do {
                let result = try runner.extract(archiveURL: archiveURL, destinationDirectoryURL: destURL, password: password)
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? eventID : "OnExtractArchiveComplete"
                return try await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ]))
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExtractArchiveFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: error.errorCode
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExtractArchiveFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: "open failed"
                ]))
            }
        case let .compress(archivePath, sourceDirectoryPath, eventID, password):
            let archiveURL = resolvePath(archivePath)
            let sourceURL = resolvePath(sourceDirectoryPath)
            do {
                let result = try runner.compress(destinationArchiveURL: archiveURL, sourceDirectoryURL: sourceURL, password: password)
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? eventID : "OnCompressArchiveComplete"
                return try await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ]))
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCompressArchiveFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: error.errorCode
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCompressArchiveFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: "open failed"
                ]))
            }
        case let .createNar(narPath, sourceDirectoryPath, eventID):
            let archiveURL = resolvePath(narPath)
            let sourceURL = resolvePath(sourceDirectoryPath)
            do {
                let references = narCreationEventReferences(sourceURL: sourceURL, archiveURL: archiveURL)
                _ = try? await activeSession.handle(event: .shiori(
                    id: "OnNarCreating",
                    references: references
                ))
                let result = try runner.compress(
                    destinationArchiveURL: archiveURL,
                    sourceDirectoryURL: sourceURL,
                    appliesNarExclusions: true
                )
                let standardResponse = try? await activeSession.handle(event: .shiori(
                    id: "OnNarCreated",
                    references: references
                ))
                guard let eventID else { return standardResponse }
                let id = eventID.hasPrefix("On") ? eventID : "OnCreateNarComplete"
                return try await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ])) ?? standardResponse
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCreateNarFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: error.errorCode
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCreateNarFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: "open failed"
                ]))
            }
        case let .dumpSurface(path, eventID):
            let destinationURL: URL
            if let path, !path.isEmpty {
                let resolved = resolvePath(path)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue {
                    destinationURL = resolved.appending(path: "surface0.png")
                } else if path.hasSuffix("/") {
                    destinationURL = resolved.appending(path: "surface0.png")
                } else {
                    destinationURL = resolved
                }
            } else {
                destinationURL = masterDirectory.appending(path: "var/surface0.png")
            }

            do {
                guard let image = surfaceWindowController.renderedImage(for: 0),
                      let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:])
                else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pngData.write(to: destinationURL, options: .atomic)
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? eventID : "OnDumpSurfaceComplete"
                return try await activeSession.handle(event: .shiori(id: id, references: [
                    0: destinationURL.path
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnDumpSurfaceFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: destinationURL.path
                ]))
            }
        case let .createUpdateData(directoryPath, eventID):
            let targetURL = directoryPath.map(resolvePath) ?? currentGhost.rootDirectory
            do {
                _ = try? await activeSession.handle(event: .shiori(id: "OnUpdatedataCreating", references: [:]))
                let generator = UpdateDataGenerator()
                let result = try generator.generate(in: targetURL)
                let standardResponse = try? await activeSession.handle(event: .shiori(
                    id: "OnUpdatedataCreated",
                    references: [:]
                ))
                guard let eventID else { return standardResponse }
                let id = eventID.hasPrefix("On") ? eventID : "OnCreateUpdateDataComplete"
                return try await activeSession.handle(event: .shiori(id: id, references: [
                    0: String(result.fileCount),
                    1: targetURL.path
                ])) ?? standardResponse
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCreateUpdateDataFailure"
                return try? await activeSession.handle(event: .shiori(id: id, references: [
                    0: targetURL.path
                ]))
            }
        }
    }

    private static func httpResponseText(_ data: Data.SubSequence, encoding: String?) -> String {
        let normalized = encoding?.lowercased().replacingOccurrences(of: "-", with: "_")
        let stringEncoding: String.Encoding = switch normalized {
        case "shift_jis", "shiftjis", "sjis": .shiftJIS
        case "euc_jp", "eucjp": .japaneseEUC
        case "utf_16", "utf16", "unicode": .unicode
        default: .utf8
        }
        return String(data: Data(data), encoding: stringEncoding) ?? ""
    }

    private func handleNetworkDiagnostic(_ command: SakuraScriptNetworkDiagnostic) async -> SakuraScript? {
        guard let session else { return nil }
        switch command {
        case let .ping(host, eventID, count, size, timeout, ttl):
            guard !host.isEmpty else { return nil }
            let result = await NetworkDiagnosticRunner.ping(
                host: host, count: count, size: size, timeoutMilliseconds: timeout, ttl: ttl
            )
            let summary = result.output.split(separator: "\n").first { $0.contains("packets transmitted") }
            let numbers = summary?.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) } ?? []
            let sent = numbers.first ?? count
            let received = numbers.dropFirst().first ?? (result.succeeded ? sent : 0)
            let id = eventID.hasPrefix("On") ? eventID : "OnPingComplete"
            return try? await session.handle(event: .shiori(id: id, references: [
                0: eventID,
                1: [host, String(sent), String(received), String(max(0, sent - received))].joined(separator: "\u{1}"),
                2: result.output.replacingOccurrences(of: "\n", with: "\u{1}")
            ]))
        case let .nslookup(host, eventID):
            guard !host.isEmpty else { return nil }
            let reverse = host.contains(":") || host.split(separator: ".").count == 4
            let result = await NetworkDiagnosticRunner.nslookup(host: host)
            let value = result.output.split(separator: "\n").compactMap { line -> String? in
                let fields = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard fields.count == 2, ["name", "ip_address"].contains(fields[0]) else { return nil }
                return fields[1].trimmingCharacters(in: .whitespaces)
            }.joined(separator: "\u{1}")
            let defaultID = result.succeeded && !value.isEmpty ? "OnNSLookupComplete" : "OnNSLookupFailure"
            let id = eventID.hasPrefix("On") ? eventID : defaultID
            return try? await session.handle(event: .shiori(id: id, references: [
                0: eventID, 1: host, 2: reverse ? "reverse" : "lookup", 3: value
            ]))
        }
    }

    private func handleWebSocket(_ command: SakuraScriptWebSocketCommand) async {
        switch command {
        case let .connect(url, eventID, headerLines, protocolName):
            await webSocketManager.connect(
                url: url,
                eventID: eventID,
                headers: webSocketHeaders(headerLines),
                protocolName: protocolName
            ) { event in
                await handleWebSocketEvent(event)
            }
        case let .sendText(url, value): await webSocketManager.sendText(url: url, value: value)
        case let .sendBinary(url, value): await webSocketManager.sendBinary(url: url, value: value)
        case let .close(url, code): await webSocketManager.close(url: url, code: code)
        case let .cancel(url): await webSocketManager.cancel(url: url)
        }
    }

    private func handleWebSocketEvent(_ event: WebSocketSessionEvent) async {
        guard let session, let balloon else { return }
        let payload = event.shioriEvent
        guard let response = try? await session.handle(event: .shiori(id: payload.id, references: payload.references)),
              !response.rawValue.isEmpty
        else { return }
        scriptPlayer.play(response, balloon: balloon)
    }

    private func webSocketHeaders(_ lines: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            let fields = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return nil }
            return (fields[0], fields[1].trimmingCharacters(in: .whitespaces))
        })
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
            let previousShell = selectedShell
            sendEvent(.shiori(
                id: "OnShellChanging",
                references: [
                    0: shell.name,
                    1: previousShell?.name ?? "",
                    2: shell.directory.path
                ]
            ))
            try show(shell: shell)
            sendEvent(.shiori(
                id: "OnShellChanged",
                references: [
                    0: shell.name,
                    1: currentGhost?.name ?? "",
                    2: shell.directory.path
                ]
            ))
        } catch {
            showError(error.localizedDescription)
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
        sendEvent(.shiori(id: "OnBalloonChange", references: [
            0: selectedBalloon.name,
            1: selectedBalloon.directory.lastPathComponent
        ]))
    }

    private func handleContentAction(
        _ action: SakuraScriptContentAction,
        calledRuntime: CalledGhostRuntime? = nil
    ) {
        switch action {
        case .randomGhost:
            let candidates = model.ghosts.filter { $0.id != currentGhost?.id }
            if let ghost = candidates.randomElement() {
                selectedGhostID = ghost.id
            }
        case .nextGhost:
            guard !model.ghosts.isEmpty else { return }
            let currentIndex = model.ghosts.firstIndex { $0.id == currentGhost?.id } ?? -1
            selectedGhostID = model.ghosts[(currentIndex + 1) % model.ghosts.count].id
        case let .changeGhost(target):
            if target.caseInsensitiveCompare("random") == .orderedSame {
                handleContentAction(.randomGhost, calledRuntime: calledRuntime)
                return
            }
            if target.caseInsensitiveCompare("sequential") == .orderedSame {
                handleContentAction(.nextGhost, calledRuntime: calledRuntime)
                return
            }
            guard let ghost = model.ghosts.first(where: { matches(target, name: $0.name, directory: $0.rootDirectory) })
            else { return }
            selectedGhostID = ghost.id
        case let .callGhost(target):
            let available = model.ghosts.filter { $0.id != currentGhost?.id && calledGhosts[$0.id] == nil }
            let ghost = target.caseInsensitiveCompare("random") == .orderedSame
                ? available.randomElement()
                : available.first(where: { matches(target, name: $0.name, directory: $0.rootDirectory) })
            guard let ghost
            else { return }
            call(ghost)
        case let .changeShell(target):
            if target.caseInsensitiveCompare("random") == .orderedSame {
                if let calledRuntime, let shell = calledRuntime.ghost.shells.randomElement() {
                    calledRuntime.select(shell: shell)
                } else if let shell = currentGhost?.shells.randomElement() {
                    select(shell: shell)
                }
                return
            }
            if let calledRuntime,
               let shell = calledRuntime.ghost.shells.first(where: {
                   matches(target, name: $0.name, directory: $0.directory)
               })
            {
                calledRuntime.select(shell: shell)
            } else if let shell = currentGhost?.shells.first(where: {
                matches(target, name: $0.name, directory: $0.directory)
            }) {
                select(shell: shell)
            }
        case let .changeBalloon(target):
            let selected = target.caseInsensitiveCompare("random") == .orderedSame
                ? installedBalloons.randomElement()
                : installedBalloons.first(where: { matches(target, name: $0.name, directory: $0.directory) })
            guard let selected else { return }
            if let calledRuntime {
                calledRuntime.select(balloon: selected)
            } else {
                select(balloon: selected)
            }
            configureContextMenu()
        case .updateGhost:
            Task { await updateCurrentGhost(reason: "script") }
        case .updateBalloon:
            Task { await updateCurrentBalloon() }
        case let .headline(target):
            let headline = target.caseInsensitiveCompare("random") == .orderedSame
                ? installedHeadlines.randomElement()
                : installedHeadlines.first(where: { matches(target, name: $0.name, directory: $0.id) })
            guard let headline else { return }
            Task {
                switch headline.kind {
                case let .rss(feedURL): await fetchRSS(url: feedURL)
                case .legacyDLL: await fetchLegacyHeadline(headline)
                }
            }
        case .closeGhost:
            if let calledRuntime {
                dismissCalledGhost(calledRuntime.ghost)
            } else if !isTransitioningGhost, !isClosingCurrentGhost {
                dismissCurrentGhost()
            }
        case let .install(source):
            switch source {
            case let .path(filePath):
                let fileURL = filePath.hasPrefix("/")
                    ? URL(fileURLWithPath: filePath)
                    : (currentGhost?.rootDirectory.appending(path: "ghost/master").appending(path: filePath) ?? URL(fileURLWithPath: filePath))
                installNar(from: fileURL)
            case let .url(urlString, _):
                guard let downloadURL = URL(string: urlString), ["http", "https"].contains(downloadURL.scheme?.lowercased()) else { return }
                Task {
                    guard let (data, response) = try? await URLSession.shared.data(from: downloadURL),
                          let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode)
                    else { return }
                    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let filename = downloadURL.lastPathComponent.isEmpty ? "download.nar" : downloadURL.lastPathComponent
                    let tempFile = tempDir.appending(path: filename)
                    try? data.write(to: tempFile)
                    installNar(from: tempFile)
                }
            }
        case .reloadGhost:
            if let calledRuntime {
                let ghost = calledRuntime.ghost
                dismissCalledGhost(ghost)
                call(ghost)
            } else if let currentGhost {
                let ghostID = currentGhost.id
                selectedGhostID = nil
                selectedGhostID = ghostID
            }
        case .reloadShell:
            if let calledRuntime {
                calledRuntime.select(shell: calledRuntime.shell)
            } else if let selectedShell {
                select(shell: selectedShell)
            }
        case .reloadBalloon:
            if let calledRuntime {
                calledRuntime.select(balloon: calledRuntime.balloon)
            } else if let balloon {
                select(balloon: balloon)
            }
        case .openConfigurationDialog:
            openSettings()
        case .openReadme:
            let ghost = calledRuntime?.ghost ?? currentGhost
            if let document = ghost.flatMap(ghostReadme) {
                NSWorkspace.shared.open(document.url)
            }
        case .openHelp:
            let ghost = calledRuntime?.ghost ?? currentGhost
            if let root = ghost?.rootDirectory {
                let candidates = [
                    root.appending(path: "help.html"),
                    root.appending(path: "ghost/master/help.html"),
                    root.appending(path: "readme.txt"),
                    root.appending(path: "ghost/master/readme.txt")
                ]
                if let targetURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    NSWorkspace.shared.open(targetURL)
                }
            }
        case let .openFile(filePath):
            let baseDir = (calledRuntime?.ghost ?? currentGhost)?.rootDirectory.appending(path: "ghost/master")
            let fileURL = filePath.hasPrefix("/") || filePath.contains(":")
                ? URL(fileURLWithPath: filePath)
                : (baseDir?.appending(path: filePath) ?? URL(fileURLWithPath: filePath))
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.open(fileURL)
            }
        case let .openFolder(folderPath):
            let baseDir = (calledRuntime?.ghost ?? currentGhost)?.rootDirectory.appending(path: "ghost/master")
            let folderURL = folderPath.hasPrefix("/") || folderPath.contains(":")
                ? URL(fileURLWithPath: folderPath)
                : (baseDir?.appending(path: folderPath) ?? URL(fileURLWithPath: folderPath))
            if FileManager.default.fileExists(atPath: folderURL.path) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
            }
        }
    }

    private func dismissCurrentGhost() {
        guard !isClosingCurrentGhost else { return }
        isClosingCurrentGhost = true
        Task {
            defer { isClosingCurrentGhost = false }
            await closeCurrentGhost(reason: .close)
            scriptPlayer.cancel()
            surfaceWindowController.hideAll()
            balloonWindowController.hideAll()
            session = nil
            currentGhost = nil
            selectedShell = nil
            balloon = nil
            selectedGhostID = nil
            showGhostPicker(requiresSelection: true)
            configureContextMenu()
        }
    }

    private func showGhostPicker(requiresSelection: Bool = false) {
        contentPickerController.show(
            title: String(localized: "ゴーストを選択"),
            entries: model.ghosts.map { .init(id: $0.id, name: $0.name) },
            selectedID: currentGhost?.id ?? selectedGhostID,
            actionTitle: String(localized: "切り替え"),
            allowsCancel: !requiresSelection
        ) { id in
            selectedGhostID = id
        }
    }

    private func showShellPicker() {
        guard let currentGhost else { return }
        contentPickerController.show(
            title: String(localized: "シェルを選択"),
            entries: currentGhost.shells.map { .init(id: $0.id, name: $0.name) },
            selectedID: selectedShell?.id,
            actionTitle: String(localized: "切り替え")
        ) { id in
            guard let shell = currentGhost.shells.first(where: { $0.id == id }) else { return }
            select(shell: shell)
        }
    }

    private func showBalloonPicker() {
        contentPickerController.show(
            title: String(localized: "バルーンを選択"),
            entries: installedBalloons.map { .init(id: $0.directory, name: $0.name) },
            selectedID: balloon?.directory,
            actionTitle: String(localized: "切り替え")
        ) { id in
            guard let selectedBalloon = installedBalloons.first(where: { $0.directory == id }) else { return }
            select(balloon: selectedBalloon)
        }
    }

    private func matches(_ target: String, name: String, directory: URL) -> Bool {
        name.caseInsensitiveCompare(target) == .orderedSame
            || directory.lastPathComponent.caseInsensitiveCompare(target) == .orderedSame
    }

    private func handleOtherGhostTalk(
        target: String,
        script: String,
        excluding originID: URL?
    ) {
        let isAll = target.caseInsensitiveCompare("__SYSTEM_ALL_GHOST__") == .orderedSame || target == "*"
        if let currentGhost,
           currentGhost.id != originID,
           isAll || ghost(currentGhost, matches: target),
           let balloon
        {
            scriptPlayer.play(SakuraScript(rawValue: script), balloon: balloon)
        }
        for runtime in calledGhosts.values where runtime.ghost.id != originID
            && (isAll || ghost(runtime.ghost, matches: target))
        {
            runtime.play(SakuraScript(rawValue: script))
        }
    }

    private func handleOtherSurfaceChange(
        target: String,
        scope: Int,
        surfaceID: Int,
        excluding originID: URL?
    ) {
        let isAll = target.caseInsensitiveCompare("__SYSTEM_ALL_GHOST__") == .orderedSame || target == "*"
        if let currentGhost,
           currentGhost.id != originID,
           isAll || ghost(currentGhost, matches: target)
        {
            try? surfaceWindowController.changeSurface(scope: scope, to: surfaceID)
        }
        for runtime in calledGhosts.values where runtime.ghost.id != originID
            && (isAll || ghost(runtime.ghost, matches: target))
        {
            runtime.changeSurface(to: surfaceID, scope: scope)
        }
    }

    private func notifyOtherGhostsSurfaceChange(
        ghost: InstalledGhost,
        controller: SurfaceWindowController,
        scope: Int,
        previous: Int?,
        current: Int,
        excluding originID: URL
    ) {
        let size = controller.renderedImage(for: scope)?.size ?? .zero
        let references: [Int: String] = [
            0: ghost.name,
            1: ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
            2: String(scope),
            3: String(current),
            4: previous.map(String.init) ?? "",
            5: "0,0,\(Int(size.width)),\(Int(size.height))"
        ]
        if currentGhost?.id != originID {
            sendEvent(.shiori(id: "OnOtherSurfaceChange", references: references))
        }
        for runtime in calledGhosts.values where runtime.ghost.id != originID {
            runtime.send(.shiori(id: "OnOtherSurfaceChange", references: references))
        }
    }

    private func handleOtherEvent(
        target: String,
        id: String,
        arguments: [String],
        reflectsResponse: Bool,
        excluding originID: URL
    ) async {
        let isAll = target.caseInsensitiveCompare("__SYSTEM_ALL_GHOST__") == .orderedSame
        let references = Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
            ($0.offset, $0.element)
        })
        if let currentGhost,
           currentGhost.id != originID,
           isAll || ghost(currentGhost, matches: target),
           let session,
           let response = try? await session.handle(event: .shiori(id: id, references: references)),
           reflectsResponse,
           !response.rawValue.isEmpty,
           let balloon
        {
            scriptPlayer.play(response, balloon: balloon)
        }
        for runtime in calledGhosts.values where runtime.ghost.id != originID
            && (isAll || ghost(runtime.ghost, matches: target))
        {
            await runtime.handleExternalEvent(
                id: id,
                arguments: arguments,
                reflectsResponse: reflectsResponse
            )
        }
    }

    private func ghostReadme(_ ghost: InstalledGhost) -> ReadmeDocument? {
        ReadmeResolver().resolve(
            contentDirectory: ghost.rootDirectory,
            descriptorURL: ghost.rootDirectory.appending(path: "ghost/master/descript.txt")
        )
    }

    private func readmeMenuItems() -> [SurfaceContextMenuItem] {
        var items: [SurfaceContextMenuItem] = []
        if let currentGhost, let document = ghostReadme(currentGhost) {
            items.append(.action(title: currentGhost.name, handler: { NSWorkspace.shared.open(document.url) }))
        }
        if let selectedShell,
           let document = ReadmeResolver().resolve(
               contentDirectory: selectedShell.directory,
               descriptorURL: selectedShell.directory.appending(path: "descript.txt")
           )
        {
            items.append(.action(title: selectedShell.name, handler: { NSWorkspace.shared.open(document.url) }))
        }
        if let balloon,
           let document = ReadmeResolver().resolve(
               contentDirectory: balloon.directory,
               descriptorURL: balloon.directory.appending(path: "descript.txt")
           )
        {
            items.append(.action(title: balloon.name, handler: { NSWorkspace.shared.open(document.url) }))
        }
        return items
    }

    private func configureContextMenu() {
        surfaceWindowController.contextMenuItems = {
            [
                .submenu(
                    title: String(localized: "ゴースト切り替え"),
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
                    title: String(localized: "Shell"),
                    items: (currentGhost?.shells ?? []).map { shell in
                        .action(
                            title: shell.name,
                            isSelected: shell.id == selectedShell?.id,
                            handler: { select(shell: shell) }
                        )
                    }
                ),
                .submenu(
                    title: String(localized: "バルーン"),
                    items: installedBalloons.map { candidate in
                        .action(
                            title: candidate.name,
                            isSelected: candidate.directory == balloon?.directory,
                            handler: { select(balloon: candidate) }
                        )
                    }
                ),
                .submenu(title: "README", items: readmeMenuItems()),
                .separator,
                .action(
                    title: String(localized: "ランダムトーク"),
                    isEnabled: session != nil,
                    handler: { sendEvent(.randomTalk) }
                ),
                .action(title: String(localized: "バルーンを閉じる"), handler: { scriptPlayer.cancel() }),
                .action(title: String(localized: "ウインドウ位置を初期化"), handler: {
                    sendEvent(.shiori(id: "OnResetWindowPos", references: [:]))
                    surfaceWindowController.resetWindowPositions()
                    balloonWindowController.resetWindowPositions()
                }),
                .submenu(
                    title: String(localized: "コンテンツ管理"),
                    items: [
                        .action(title: String(localized: "NARをインストール…"), handler: selectAndInstallNar),
                        .action(title: String(localized: "SSPフォルダから取り込む…"), handler: selectAndImportSSPDirectory),
                        .action(title: String(localized: "Finderで表示"), handler: showContentFolder)
                    ]
                ),
                .submenu(
                    title: String(localized: "ネットワーク更新"),
                    items: [
                        .action(
                            title: String(localized: "ゴーストを更新"),
                            isEnabled: currentGhost != nil && session != nil && !isUpdatingContent,
                            handler: { Task { await updateCurrentGhost() } }
                        ),
                        .action(
                            title: String(localized: "バルーンを更新"),
                            isEnabled: balloon != nil && !isUpdatingContent,
                            handler: { Task { await updateCurrentBalloon() } }
                        )
                    ]
                ),
                .submenu(
                    title: String(localized: "RSS / ヘッドライン"),
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
                        .action(title: String(localized: "URLを指定して取得…"), handler: showRSSInput)
                    ]
                ),
                .action(
                    title: String(localized: "設定"),
                    handler: {
                        networkSettings.selectedPane = .general
                        openSettings()
                    }
                ),
                .action(
                    title: String(localized: "デバッグ画面を表示"),
                    isSelected: networkSettings.showsDebugWindow,
                    handler: {
                        networkSettings.showsDebugWindow.toggle()
                        updateDebugWindowVisibility(bringForward: networkSettings.showsDebugWindow)
                    }
                ),
                .action(
                    title: String(localized: "現在のゴーストを再読み込み"),
                    isEnabled: currentGhost != nil && !isTransitioningGhost,
                    handler: { reloadCurrentGhost() }
                ),
                .separator,
                .action(title: String(localized: "Utataneを終了"), handler: { NSApplication.shared.terminate(nil) })
            ]
        }
        for runtime in calledGhosts.values {
            runtime.contextMenuItems = { calledGhostContextMenu(for: runtime) }
        }
    }

    private func callGhostMenu() -> SurfaceContextMenuItem {
        .submenu(
            title: String(localized: "ゴーストを呼ぶ"),
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
                title: String(localized: "ゴースト切り替え"),
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
                title: String(localized: "Shell"),
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
                title: String(localized: "バルーン"),
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
            .action(title: String(localized: "ランダムトーク"), handler: { runtime.send(.randomTalk) }),
            .action(title: String(localized: "ウインドウ位置を初期化"), handler: {
                runtime.resetWindowPositions()
            }),
            .action(title: String(localized: "このゴーストを閉じる"), handler: { dismissCalledGhost(runtime.ghost) }),
            .action(title: String(localized: "設定"), handler: {
                networkSettings.selectedPane = .general
                openSettings()
            }),
            .separator,
            .action(title: String(localized: "Utataneを終了"), handler: { NSApplication.shared.terminate(nil) })
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
                runtime.onError = { showError($0.localizedDescription) }
                runtime.onNarDrop = { installNars(from: $0) }
                runtime.onCommunication = { target, sentence in
                    deliverCommunication(from: ghost, target: target, sentence: sentence)
                }
                runtime.onContentAction = { action in
                    handleContentAction(action, calledRuntime: runtime)
                }
                runtime.onOtherEvent = { target, id, arguments, reflectsResponse in
                    await handleOtherEvent(
                        target: target,
                        id: id,
                        arguments: arguments,
                        reflectsResponse: reflectsResponse,
                        excluding: ghost.id
                    )
                }
                runtime.onOtherGhostTalk = { target, script in
                    handleOtherGhostTalk(target: target, script: script, excluding: ghost.id)
                }
                runtime.onOtherSurfaceChange = { target, scope, surfaceID in
                    handleOtherSurfaceChange(target: target, scope: scope, surfaceID: surfaceID, excluding: ghost.id)
                }
                runtime.onSurfaceChanged = { scope, previous, current in
                    notifyOtherGhostsSurfaceChange(
                        ghost: ghost,
                        controller: runtime.surfaceController,
                        scope: scope,
                        previous: previous,
                        current: current,
                        excluding: ghost.id
                    )
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
                showError(error.localizedDescription)
            }
        }
    }

    private func dismissCalledGhost(_ ghost: InstalledGhost) {
        guard let runtime = calledGhosts.removeValue(forKey: ghost.id) else { return }
        configureContextMenu()
        Task {
            let finalScript = await runtime.stop()
            sendEvent(.shiori(id: "OnOtherGhostClosed", references: [
                0: ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
                1: finalScript,
                2: ghost.name,
                7: runtime.shell.name
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
        let shellPercent = networkSettings.shellScalePercent
        let shellScale = Double(shellPercent) / 100
        let balloonScalePercent = networkSettings.linksBalloonScale
            ? networkSettings.shellScalePercent
            : networkSettings.balloonScalePercent
        if let previous = configuredShellScalePercent, previous != shellPercent {
            broadcastEvent(.shiori(id: "OnShellScaling", references: [
                0: String(shellPercent), 1: String(previous),
                2: String(shellPercent), 3: String(previous)
            ]))
        }
        if let previous = configuredBalloonScalePercent, previous != balloonScalePercent {
            broadcastEvent(.shiori(id: "OnBalloonScaling", references: [
                0: String(balloonScalePercent), 1: String(previous),
                2: String(balloonScalePercent), 3: String(previous)
            ]))
        }
        configuredShellScalePercent = shellPercent
        configuredBalloonScalePercent = balloonScalePercent
        surfaceWindowController.setDisplayScale(shellScale)
        surfaceWindowController.setPlacement(
            locksToDesktopBottom: networkSettings.locksShellToDesktopBottom,
            keepsOnScreen: networkSettings.keepsShellOnScreen
        )
        balloonWindowController.setDisplayScale(
            Double(balloonScalePercent) / 100,
            textScale: Double(networkSettings.balloonTextScalePercent) / 100
        )
        for runtime in calledGhosts.values {
            runtime.configureDisplay(
                shellPercent: shellPercent,
                balloonPercent: balloonScalePercent,
                textPercent: networkSettings.balloonTextScalePercent
            )
        }
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = switch networkSettings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func updateDebugWindowVisibility(bringForward: Bool = false) {
        guard let debugWindow else { return }
        if showsOnboarding || bringForward {
            debugWindow.makeKeyAndOrderFront(nil)
        } else if networkSettings.showsDebugWindow {
            // SwiftUI can reconnect the root window after presenting a panel.
            // Keep an already-enabled debug window visible without stealing focus.
            debugWindow.orderBack(nil)
        } else {
            debugWindow.orderOut(nil)
        }
    }

    private func installNar(from url: URL) {
        installNars(from: [url])
    }

    private func updateCurrentGhost(isAutomatic: Bool = false, reason: String? = nil) async {
        guard !isUpdatingContent,
              let ghost = currentGhost,
              let updateSession = session,
              let updateBalloon = balloon
        else { return }
        isUpdatingContent = true
        defer { isUpdatingContent = false }

        let directoryName = ghost.rootDirectory.lastPathComponent
        let updateReason = reason ?? (isAutomatic ? "auto" : "manual")
        networkSettings.recordContentUpdateAttempt(kind: .ghost, directoryName: directoryName)
        AppLogStore.shared.info("「\(ghost.name)」の更新確認を開始しました", category: "Update", ghostName: ghost.name)
        let statusToken = isAutomatic ? nil : statusWindowController.show("「\(ghost.name)」を更新中…")
        defer {
            if let statusToken {
                statusWindowController.hide(token: statusToken)
            }
        }

        do {
            let usesCustomUpdate = await playInstallationEvent(
                .shiori(id: "OnUpdateProcessExec", references: [0: updateReason]),
                session: updateSession,
                balloon: updateBalloon
            )
            if usesCustomUpdate {
                return
            }
            _ = await playInstallationEvent(
                .shiori(id: "OnUpdateBegin", references: [
                    0: ghost.name,
                    1: ghost.rootDirectory.path,
                    3: "ghost",
                    4: updateReason
                ]),
                session: updateSession,
                balloon: updateBalloon
            )
            let homeURL: URL
            if let configured = ContentNetworkUpdater.homeURL(in: ghost.rootDirectory) {
                homeURL = configured
            } else if let value = try await updateSession.handle(event: .shiori(id: "On_homeurl", references: [:])),
                      let configured = URL(string: value.rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                homeURL = configured
            } else {
                throw ContentNetworkUpdateError.invalidHomeURL
            }
            AppLogStore.shared.info("更新URL: \(homeURL.absoluteString)", category: "Update", ghostName: ghost.name)
            let result = try await ContentNetworkUpdater().update(
                rootDirectory: ghost.rootDirectory,
                homeURL: homeURL,
                progress: { progress in
                    await playUpdateProgress(
                        progress,
                        session: updateSession,
                        balloon: updateBalloon,
                        reason: updateReason
                    )
                }
            )
            networkSettings.recordContentUpdateSuccess(kind: .ghost, directoryName: directoryName)
            AppLogStore.shared.info(
                result.changedFiles.isEmpty ? "「\(ghost.name)」は最新です" : "「\(ghost.name)」を更新しました (\(result.changedFiles.count)ファイル)",
                category: "Update",
                details: result.changedFiles.isEmpty ? nil : result.changedFiles.joined(separator: "\n"),
                ghostName: ghost.name
            )
            _ = await playInstallationEvent(
                .shiori(id: "OnUpdateComplete", references: [
                    0: result.changedFiles.isEmpty ? "none" : "changed",
                    1: result.changedFiles.joined(separator: ","),
                    3: "ghost",
                    4: updateReason
                ]),
                session: updateSession,
                balloon: updateBalloon
            )
        } catch {
            AppLogStore.shared.error(
                "「\(ghost.name)」の更新に失敗しました: \(error.localizedDescription)",
                category: "Update",
                details: String(describing: error),
                ghostName: ghost.name
            )
            let handled = await playInstallationEvent(
                .shiori(id: "OnUpdateFailure", references: [
                    0: updateFailureReason(error),
                    1: updateFailurePath(error) ?? "",
                    3: "ghost",
                    4: updateReason
                ]),
                session: updateSession,
                balloon: updateBalloon
            )
            if !handled, !isAutomatic {
                showError(error.localizedDescription)
            }
        }
    }

    private func playUpdateProgress(
        _ progress: ContentUpdateProgress,
        session: GhostSession,
        balloon: BalloonDefinition,
        reason: String
    ) async {
        let event: GhostEvent = switch progress {
        case let .ready(files):
            .shiori(id: "OnUpdateReady", references: [
                0: String(max(0, files.count - 1)),
                1: files.joined(separator: ","),
                3: "ghost",
                4: reason
            ])
        case let .downloadBegin(path, index, total):
            .shiori(id: "OnUpdate.OnDownloadBegin", references: [
                0: path,
                1: String(index),
                2: String(max(0, total - 1)),
                3: "ghost",
                4: reason
            ])
        case let .checksumBegin(path, expected, actual):
            .shiori(id: "OnUpdate.OnMD5CompareBegin", references: [
                0: path, 1: expected, 2: actual, 3: "ghost", 4: reason
            ])
        case let .checksumComplete(path, expected, actual):
            .shiori(id: "OnUpdate.OnMD5CompareComplete", references: [
                0: path, 1: expected, 2: actual, 3: "ghost", 4: reason
            ])
        case let .checksumFailure(path, expected, actual):
            .shiori(id: "OnUpdate.OnMD5CompareFailure", references: [
                0: path, 1: expected, 2: actual, 3: "ghost", 4: reason
            ])
        }
        _ = await playInstallationEvent(event, session: session, balloon: balloon)
    }

    private func updateFailureReason(_ error: Error) -> String {
        switch error {
        case ContentNetworkUpdateError.checksumMismatch: "md5 miss"
        case let ContentNetworkUpdateError.downloadFailed(_, underlyingError):
            if underlyingError.localizedCaseInsensitiveContains("timed out")
                || underlyingError.localizedCaseInsensitiveContains("timeout")
            {
                "timeout"
            } else if let status = underlyingError
                .split(whereSeparator: { !$0.isNumber })
                .compactMap({ Int($0) })
                .first(where: { 400 ... 599 ~= $0 })
            {
                String(status)
            } else {
                "fileio"
            }
        default: "fileio"
        }
    }

    private func updateFailurePath(_ error: Error) -> String? {
        switch error {
        case let ContentNetworkUpdateError.checksumMismatch(path): path
        case let ContentNetworkUpdateError.downloadFailed(path, _): path
        default: nil
        }
    }

    private func updateCurrentBalloon(isAutomatic: Bool = false) async {
        guard !isUpdatingContent, let updateBalloon = balloon else { return }
        isUpdatingContent = true
        defer { isUpdatingContent = false }

        let directoryName = updateBalloon.directory.lastPathComponent
        networkSettings.recordContentUpdateAttempt(kind: .balloon, directoryName: directoryName)
        AppLogStore.shared.info("バルーン「\(updateBalloon.name)」の更新確認を開始しました", category: "Update")
        let statusToken = isAutomatic
            ? nil
            : statusWindowController.show("バルーン「\(updateBalloon.name)」を更新中…")
        defer {
            if let statusToken {
                statusWindowController.hide(token: statusToken)
            }
        }

        do {
            guard let homeURL = ContentNetworkUpdater.homeURL(in: updateBalloon.directory) else {
                throw ContentNetworkUpdateError.invalidHomeURL
            }
            AppLogStore.shared.info("バルーン更新URL: \(homeURL.absoluteString)", category: "Update")
            let result = try await ContentNetworkUpdater().update(
                rootDirectory: updateBalloon.directory,
                homeURL: homeURL
            )
            try reloadInstalledBalloons(preserving: updateBalloon.directory)
            networkSettings.recordContentUpdateSuccess(kind: .balloon, directoryName: directoryName)
            AppLogStore.shared.info(
                result.changedFiles.isEmpty ? "バルーン「\(updateBalloon.name)」は最新です" : "バルーン「\(updateBalloon.name)」を更新しました (\(result.changedFiles.count)ファイル)",
                category: "Update",
                details: result.changedFiles.isEmpty ? nil : result.changedFiles.joined(separator: "\n")
            )
            if !isAutomatic {
                if let statusToken {
                    statusWindowController.hide(token: statusToken)
                }
                let completionToken = statusWindowController.show(
                    result.changedFiles.isEmpty
                        ? "バルーンは最新です"
                        : "バルーンを更新しました（\(result.changedFiles.count)ファイル）"
                )
                try? await Task.sleep(for: .seconds(2))
                statusWindowController.hide(token: completionToken)
            }
        } catch {
            AppLogStore.shared.error(
                "バルーン「\(updateBalloon.name)」の更新に失敗しました: \(error.localizedDescription)",
                category: "Update",
                details: String(describing: error)
            )
            if !isAutomatic {
                showError(error.localizedDescription)
            }
        }
    }

    private func reloadInstalledBalloons(preserving selectedDirectory: URL) throws {
        installedBalloons = try balloonLoader.loadInstalled(from: ContentRoot.balloonReadDirectories)
        guard let refreshedSelectedBalloon = installedBalloons.first(where: {
            $0.directory.standardizedFileURL == selectedDirectory.standardizedFileURL
        }) else {
            throw AppError.missingResource("更新後のバルーン")
        }
        balloon = refreshedSelectedBalloon
        for runtime in calledGhosts.values where !runtime.player.isDialogueActive {
            guard let refreshed = installedBalloons.first(where: {
                $0.directory.standardizedFileURL == runtime.balloon.directory.standardizedFileURL
            }) else { continue }
            runtime.select(balloon: refreshed)
        }
        configureContextMenu()
    }

    private func showRSSInput() {
        textInputWindowController.show(.init(
            title: String(localized: "RSS/Atomを取得"),
            prompt: String(localized: "RSSまたはAtomフィードのURL"),
            placeholder: "https://example.com/feed.xml",
            actionTitle: String(localized: "取得"),
            onCommit: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed), url.scheme != nil else {
                    showError(String(localized: "RSS/AtomのURLが不正"))
                    return
                }
                Task { await fetchRSS(url: url) }
            }
        ))
    }

    private func fetchRSS(url: URL) async {
        guard let rssSession = session, let rssBalloon = balloon else { return }
        AppLogStore.shared.info("RSS/Atomフィード取得開始: \(url.absoluteString)", category: "Headline")
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
            AppLogStore.shared.info("RSS/Atomフィード取得完了: \(feed.title) (\(feed.items.count)件)", category: "Headline")
            _ = await playInstallationEvent(
                .shiori(id: "OnRSSComplete", references: references),
                session: rssSession,
                balloon: rssBalloon
            )
        } catch {
            AppLogStore.shared.error(
                "RSS/Atom取得エラー (\(url.absoluteString)): \(error.localizedDescription)",
                category: "Headline",
                details: String(describing: error)
            )
            let handled = await playInstallationEvent(
                .shiori(id: "OnRSSFailure", references: [0: "can't analyze"]),
                session: rssSession,
                balloon: rssBalloon
            )
            if !handled {
                showError(error.localizedDescription)
            }
        }
    }

    private func fetchLegacyHeadline(_ headline: InstalledHeadline) async {
        guard let headlineSession = session, let headlineBalloon = balloon else { return }
        guard let sourceURL = headline.siteURL else {
            AppLogStore.shared.warning("HEADLINEセンサーの取得URLが未設定: \(headline.name)", category: "Headline")
            showError("HEADLINEセンサーの取得URLが設定されていない")
            return
        }
        let usesNativeConfig = ConfigHeadlineSensor.canLoad(headline)
        let windowsConfiguration = ContentRoot.windowsHeadlineConfiguration()
        guard usesNativeConfig || windowsConfiguration != nil else {
            AppLogStore.shared.warning("HEADLINE DLLの実行にWine設定が必要: \(headline.name)", category: "Headline")
            showError("このHEADLINE DLLを使うにはWine設定が必要")
            return
        }
        AppLogStore.shared.info("HEADLINE取得開始: \(headline.name) (\(sourceURL.absoluteString))", category: "Headline")
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
            AppLogStore.shared.info("HEADLINE取得完了: \(headline.name) (\(displayedItems.count)件)", category: "Headline")
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
            AppLogStore.shared.error(
                "HEADLINEセンサーエラー (\(headline.name)): \(error.localizedDescription)",
                category: "Headline",
                details: String(describing: error)
            )
            let handled = await playInstallationEvent(
                .shiori(id: "OnHeadlinesenseFailure", references: [0: reason]),
                session: headlineSession,
                balloon: headlineBalloon
            )
            if !handled {
                showError(error.localizedDescription)
            }
        }
    }

    private func selectAndInstallNar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "nar") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "インストール")
        if panel.runModal() == .OK {
            installNars(from: panel.urls)
        }
    }

    private func selectAndImportSSPDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "選択")
        if panel.runModal() == .OK, let url = panel.url {
            importSSPContents(from: url)
        }
    }

    private func showError(_ message: String) {
        alertController.showError(message)
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
        let headerSummary = request.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        AppLogStore.shared.debug("SSTP \(request.method) \(request.version)", category: "SSTP", details: headerSummary)
        if let command = request.value(for: "Command") {
            return handleMCPBridgeCommand(
                command,
                ghostID: request.value(for: "Ghost-ID"),
                script: request.value(for: "Script")
            )
        }
        guard let activeSession = session, let activeBalloon = balloon else {
            AppLogStore.shared.warning("SSTP: セッションなしのため 503 応答", category: "SSTP")
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
        guard let script else {
            AppLogStore.shared.debug("SSTP: レスポンスなし 204", category: "SSTP")
            return SSTPResponse(statusCode: 204, reason: "No Content")
        }
        AppLogStore.shared.info("SSTPスクリプト再生", category: "SSTP", details: script.rawValue)
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
        let activeGhostDirectories = activeGhostInstallTargets()
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
                for url in urls where url.lastPathComponent.hasPrefix("utatane-url-drop-") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            AppLogStore.shared.info("NARインストール開始 (\(urls.count)件)", category: "Install", details: urls.map(\.path).joined(separator: "\n"))
            do {
                _ = await playInstallationEvent(
                    .shiori(id: "OnInstallBegin", references: [:]),
                    session: installSession,
                    balloon: installBalloon
                )
                var installedItems: [NarInstalledItem] = []
                var bootGhostDirectories: [String] = []
                for url in urls {
                    let result = try await Task.detached {
                        try NarInstaller().install(
                            archiveURL: url,
                            roots: roots,
                            selectedGhostDirectory: selectedGhostDirectory,
                            activeGhostDirectories: activeGhostDirectories
                        )
                    }.value
                    installedItems.append(contentsOf: result.items)
                    if let bootGhostDirectory = result.bootGhostDirectory {
                        bootGhostDirectories.append(bootGhostDirectory)
                    }
                    let eventTarget = installationEventTarget(acceptedGhostName: result.acceptedGhostName)
                    if let acceptedGhostName = result.acceptedGhostName,
                       eventTarget.session !== installSession
                    {
                        _ = await playInstallationEvent(
                            .shiori(id: "OnInstallReroute", references: [
                                0: acceptedGhostName,
                                1: result.primaryType.rawValue,
                                2: result.items.first?.name ?? ""
                            ]),
                            session: installSession,
                            balloon: installBalloon
                        )
                    }
                    let references = installCompletionReferences(for: result.items)
                    let handled = await playInstallationEvent(
                        .shiori(id: "OnInstallCompleteEx", references: references),
                        session: eventTarget.session,
                        balloon: eventTarget.balloon
                    )
                    if !handled {
                        _ = await playInstallationEvent(
                            .shiori(id: "OnInstallComplete", references: legacyInstallCompletionReferences(for: result)),
                            session: eventTarget.session,
                            balloon: eventTarget.balloon
                        )
                    }
                }
                await model.load()
                if let bootGhostDirectory = bootGhostDirectories.last,
                   let bootGhost = model.ghosts.first(where: {
                       $0.rootDirectory.lastPathComponent.caseInsensitiveCompare(bootGhostDirectory) == .orderedSame
                   })
                {
                    selectedGhostID = bootGhost.id
                    currentGhost = bootGhost
                } else if selectedGhostID == nil {
                    selectedGhostID = model.ghosts.first?.id
                }
                showsOnboarding = model.ghosts.isEmpty
                updateDebugWindowVisibility()
                if let refreshedGhost = model.ghosts.first(where: {
                    $0.id.standardizedFileURL == selectedGhostID?.standardizedFileURL
                }) {
                    currentGhost = refreshedGhost
                }
                installedBalloons = try balloonLoader.loadInstalled(from: ContentRoot.balloonReadDirectories)
                reloadHeadlines()
                configureContextMenu()

                if let lastGhost = installedItems.last(where: { $0.type == .ghost }) {
                    lastGhostName = lastGhost.name
                }
                if let lastObject = installedItems.last {
                    lastObjectName = lastObject.name
                }
                scriptPlayer.updateEnvironmentVariables([
                    "lastghostname": lastGhostName,
                    "lastobjectname": lastObjectName
                ])
                for runtime in calledGhosts.values {
                    runtime.updateEnvironmentVariables([
                        "lastghostname": lastGhostName,
                        "lastobjectname": lastObjectName
                    ])
                }

                AppLogStore.shared.info(
                    "NARインストール完了 (\(installedItems.count)件)",
                    category: "Install",
                    details: installedItems.map { "\($0.type): \($0.name)" }.joined(separator: "\n")
                )
                if urls.count > 1 {
                    _ = await playInstallationEvent(
                        .shiori(id: "OnInstallCompleteAll", references: installCompletionReferences(for: installedItems)),
                        session: installSession,
                        balloon: installBalloon
                    )
                }
                let completionToken = statusWindowController.show(
                    installedItems.count == 1
                        ? "「\(installedItems[0].name)」をインストールした"
                        : "\(installedItems.count)件をインストールした"
                )
                try? await Task.sleep(for: .seconds(2))
                statusWindowController.hide(token: completionToken)
            } catch {
                AppLogStore.shared.error(
                    "NARインストール失敗: \(error.localizedDescription)",
                    category: "Install",
                    details: String(describing: error)
                )
                if case let NarInstallError.refused(accept, type, name) = error {
                    _ = await playInstallationEvent(
                        .shiori(id: "OnInstallRefuse", references: [0: accept, 1: type, 2: name]),
                        session: installSession,
                        balloon: installBalloon
                    )
                } else {
                    _ = await playInstallationEvent(
                        .shiori(id: "OnInstallFailure", references: [0: installFailureReason(error)]),
                        session: installSession,
                        balloon: installBalloon
                    )
                }
                showError(error.localizedDescription)
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
                showError("再読み込み対象のゴーストが見つからない: \(activeGhost.name)")
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
                installedBalloons = try balloonLoader.loadInstalled(from: ContentRoot.balloonReadDirectories)
                if selectedGhostID == nil {
                    selectedGhostID = model.ghosts.first?.id
                }
                showsOnboarding = model.ghosts.isEmpty
                updateDebugWindowVisibility()
            } catch {
                showError(error.localizedDescription)
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
            showError(error.localizedDescription)
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
        case .unsupportedType, .missingArchive, .archiveTooLarge, .destinationExists, .refused:
            return "unsupported"
        }
    }

    private func activeGhostInstallTargets() -> [String: URL] {
        var targets: [String: URL] = [:]
        func add(_ ghost: InstalledGhost) {
            targets[ghost.name] = ghost.rootDirectory
            for character in ghost.characters {
                if let name = character.name, !name.isEmpty {
                    targets[name] = ghost.rootDirectory
                }
            }
        }
        if let currentGhost {
            add(currentGhost)
        }
        for runtime in calledGhosts.values {
            add(runtime.ghost)
        }
        return targets
    }

    private func installationEventTarget(
        acceptedGhostName: String?
    ) -> (session: GhostSession?, balloon: BalloonDefinition?) {
        guard let acceptedGhostName else { return (session, balloon) }
        if let currentGhost, ghost(currentGhost, matches: acceptedGhostName) {
            return (session, balloon)
        }
        if let runtime = calledGhosts.values.first(where: { ghost($0.ghost, matches: acceptedGhostName) }) {
            return (runtime.session, runtime.balloon)
        }
        return (session, balloon)
    }

    private func installCompletionReferences(for items: [NarInstalledItem]) -> [Int: String] {
        let separator = "\u{1}"
        return [
            0: items.map(\.type.rawValue).joined(separator: separator),
            1: items.map(\.name).joined(separator: separator),
            2: items.map(\.url.path).joined(separator: separator)
        ]
    }

    private func legacyInstallCompletionReferences(for result: NarInstallResult) -> [Int: String] {
        let identifier = result.items.count > 1 && result.items.contains(where: { $0.type == .balloon })
            ? "\(result.primaryType.rawValue) with balloon"
            : result.primaryType.rawValue
        return [
            0: identifier,
            1: result.items.first?.name ?? "",
            2: result.items.dropFirst().first?.name ?? ""
        ]
    }

    private func requestApplicationTermination() {
        Task {
            for runtime in calledGhosts.values {
                _ = await runtime.stop()
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
func startupInformationEvents(
    ghost: InstalledGhost,
    shell: InstalledShell,
    balloon: BalloonDefinition,
    shellDefinition: ShellDefinition,
    installedGhosts: [InstalledGhost]? = nil,
    installedBalloons: [BalloonDefinition]? = nil,
    installedHeadlines: [InstalledHeadline] = [],
    surfaceWindowNumbers: [Int] = [],
    balloonWindowNumbers: [Int] = [],
    otherGhosts: [String] = []
) -> [(id: String, references: [Int: String])] {
    let process = ProcessInfo.processInfo
    let locale = Locale.current
    let languageCode = locale.language.languageCode?.identifier ?? ""
    let countryCode = locale.region?.identifier ?? ""
    let mainName = ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name
    let partnerName = ghost.characters.first(where: { $0.scope == 1 })?.name ?? ""
    let surfaceList = shellDefinition.surfaces.keys.sorted().map(String.init).joined(separator: ",")
    let physicalMemoryKB = process.physicalMemory / 1024
    let timeZone = TimeZone.current
    let languageName = locale.localizedString(forLanguageCode: languageCode) ?? languageCode
    let ghosts = (installedGhosts ?? [ghost]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let balloons = (installedBalloons ?? [balloon]).sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? version
    let indexed: ([String]) -> [Int: String] = { values in
        Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset, $0.element) })
    }
    return [
        ("basewareversion", [0: version, 1: "Utatane", 2: build]),
        ("uniqueid", [0: ghost.rootDirectory.lastPathComponent]),
        ("capability", indexed([
            "request.charset", "request.sender", "request.securitylevel", "request.id",
            "request.event", "request.reference", "response.charset", "response.sender",
            "response.value", "response.reference"
        ])),
        ("ownerghostname", [0: ghost.name]),
        ("hwnd", [
            0: surfaceWindowNumbers.map(String.init).joined(separator: "\u{1}"),
            1: balloonWindowNumbers.map(String.init).joined(separator: "\u{1}")
        ]),
        ("otherghostname", indexed(otherGhosts.sorted())),
        ("installedsakuraname", indexed(ghosts.map {
            $0.characters.first(where: { $0.scope == 0 })?.name ?? $0.name
        })),
        ("installedkeroname", indexed(ghosts.map {
            $0.characters.first(where: { $0.scope == 1 })?.name ?? ""
        })),
        ("installedghostname", indexed(ghosts.map(\.name))),
        ("installedshellname", indexed(ghost.shells.map(\.name).sorted())),
        ("installedballoonname", indexed(balloons.map(\.name))),
        ("installedheadlinename", indexed(installedHeadlines.map(\.name).sorted())),
        ("ghostpathlist", indexed(ContentRoot.ghostReadDirectories.map(\.path))),
        ("balloonpathlist", indexed(ContentRoot.balloonReadDirectories.map(\.path))),
        ("headlinepathlist", [0: ContentRoot.headlinesDirectory.path]),
        ("installedplugin", [:]),
        ("configuredbiffname", [:]),
        ("pluginpathlist", [:]),
        ("calendarskinpathlist", [:]),
        ("calendarpluginpathlist", [:]),
        ("rateofusegraph", [0: [ghost.name, mainName, partnerName, "0", "0", "0", "boot"]
                .joined(separator: "\u{1}")]),
        ("enable_log", [0: "1"]),
        ("enable_debug", [0: _isDebugAssertConfiguration() ? "1" : "0"]),
        ("OnNotifySelfInfo", [
            0: ghost.name, 1: mainName, 2: partnerName,
            3: shell.name, 4: shell.directory.path,
            5: balloon.name, 6: balloon.directory.path
        ]),
        ("OnNotifyBalloonInfo", [
            0: balloon.name, 1: balloon.directory.path,
            2: balloonSurfaceList(in: balloon.directory)
        ]),
        ("OnNotifyShellInfo", [0: shell.name, 1: shell.directory.path, 2: surfaceList]),
        ("OnNotifyUserInfo", [0: NSUserName(), 1: NSFullUserName(), 2: "", 3: "undef"]),
        ("OnNotifyOSInfo", [
            0: "macOS,\(process.operatingSystemVersionString),macOS",
            1: "\(process.processorCount)-core,0,\(process.activeProcessorCount) active cores",
            2: "\(physicalMemoryKB),\(physicalMemoryKB)",
            3: String(Int(process.systemUptime / 60))
        ]),
        ("OnNotifyFontInfo", Dictionary(uniqueKeysWithValues: NSFontManager.shared.availableFonts
                .sorted().enumerated().map { ($0.offset, $0.element) })),
        ("OnNotifyInternationalInfo", [
            0: String(-(timeZone.secondsFromGMT() / 60)),
            1: timeZone.isDaylightSavingTime() ? "1" : "0",
            2: countryCode,
            3: languageCode
        ]),
        ("OnDarkTheme", darkThemeReferences()),
        ("OnLanguageChange", [0: languageName, 1: locale.identifier, 2: "", 3: ""])
    ]
}

@MainActor
func darkThemeReferences() -> [Int: String] {
    let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return [0: isDark ? "1" : "0", 1: isDark ? "1" : "0"]
}

private func balloonSurfaceList(in directory: URL) -> String {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    var surfaces: [Int: Set<Int>] = [:]
    for name in names {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()
        let scopeAndStyle: (Int, Int)? = if stem.hasPrefix("balloons"), let style = Int(stem.dropFirst("balloons".count)) {
            (0, style)
        } else if stem.hasPrefix("balloonk"), let style = Int(stem.dropFirst("balloonk".count)) {
            (1, style)
        } else {
            nil
        }
        if let (scope, style) = scopeAndStyle {
            surfaces[scope, default: []].insert(style)
        }
    }
    return surfaces.keys.sorted().map { scope in
        "\(scope):" + surfaces[scope, default: []].sorted().map(String.init).joined(separator: ",")
    }.joined(separator: " ")
}

func droppedFileMIMEType(_ url: URL) -> String {
    if url.hasDirectoryPath {
        return "inode/directory"
    }
    return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
}

func droppedFileViewerEventID(_ url: URL) -> String? {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
    if type.conforms(to: .image) {
        return "OnPictureViewerOpen"
    }
    if type.conforms(to: .audio) || type.conforms(to: .movie) {
        return "OnMediaPlayerOpen"
    }
    let archiveExtensions = ["zip", "lzh", "lha", "rar", "7z", "tar", "gz", "bz2", "xz"]
    if archiveExtensions.contains(url.pathExtension.lowercased()) {
        return "OnArchiveViewerOpen"
    }
    return nil
}

enum URLDropDownloadError: Error {
    case httpStatus(Int)
    case invalidResponse
}

func downloadDroppedNar(from url: URL) async throws -> URL {
    let (temporaryURL, response) = try await URLSession.shared.download(from: url)
    guard let response = response as? HTTPURLResponse else { throw URLDropDownloadError.invalidResponse }
    guard (200 ..< 300).contains(response.statusCode) else {
        throw URLDropDownloadError.httpStatus(response.statusCode)
    }
    let destination = FileManager.default.temporaryDirectory.appending(
        path: "utatane-url-drop-\(UUID().uuidString).nar",
        directoryHint: .notDirectory
    )
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
    return destination
}

func urlDropFailureReason(_ error: Error) -> String {
    if case let URLDropDownloadError.httpStatus(status) = error {
        return String(status)
    }
    if let error = error as? URLError, error.code == .timedOut {
        return "timeout"
    }
    return "fileio"
}

func xUkagakaLinkValues(_ url: URL) -> [String: String]? {
    guard url.scheme?.caseInsensitiveCompare("x-ukagaka-link") == .orderedSame,
          let separator = url.absoluteString.firstIndex(of: ":")
    else { return nil }
    let payload = url.absoluteString[url.absoluteString.index(after: separator)...]
    let pairs: [(String, String)] = payload.split(separator: "&").compactMap { field in
        let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2,
              let key = String(pair[0]).removingPercentEncoding,
              let value = String(pair[1]).removingPercentEncoding
        else { return nil }
        return (key.lowercased(), value)
    }
    return pairs.reduce(into: [String: String]()) { values, pair in
        values[pair.0] = pair.1
    }
}

func narCreationEventReferences(sourceURL: URL, archiveURL: URL) -> [Int: String] {
    let metadata = try? NarInstaller().readInstallMetadata(
        from: sourceURL.appending(path: "install.txt", directoryHint: .notDirectory)
    )
    let baseType = metadata?["type"]?.lowercased() ?? "ghost"
    let identifier = metadata?["balloon.directory"] != nil && ["ghost", "shell"].contains(baseType)
        ? "\(baseType) with balloon"
        : baseType
    return [
        0: metadata?["name"] ?? sourceURL.lastPathComponent,
        1: archiveURL.path,
        2: identifier
    ]
}

func linkEventReferences(_ label: String?, _ id: String?, _ arguments: [String]) -> [Int: String] {
    guard let label, let id else { return [:] }
    return Dictionary(uniqueKeysWithValues: ([label, id] + arguments).enumerated().map {
        ($0.offset, $0.element)
    })
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

enum AppError: LocalizedError {
    case missingResource(String)
    case unsupportedShiori(String?)
    case windowsShioriUnavailable

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            String(localized: "アプリ内リソースが見つからない: \(name)")
        case let .unsupportedShiori(filename):
            String(localized: "このゴーストのSHIORIにはまだ対応していない: \(filename ?? "SHIORI不明")")
        case .windowsShioriUnavailable:
            String(localized: "この版のFIRSTにはネイティブ対応していない。配布版ではMateria用Wineホストも利用できない")
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
            headlinesDirectory
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func installBundledContent() throws {
        guard let bundledRoot = Bundle.main.resourceURL?.appending(
            path: "Bundled",
            directoryHint: .isDirectory
        ) else { return }
        try BundledContentInstaller().install(
            from: bundledRoot,
            ghostsDirectory: contentDirectory.appending(path: "Ghosts", directoryHint: .isDirectory),
            balloonsDirectory: contentDirectory.appending(path: "Balloons", directoryHint: .isDirectory)
        )
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

    static func writableYayaMasterDirectory(for ghost: InstalledGhost, source: URL) throws -> URL {
        #if DEBUG
            let bundledGhosts = repositoryRoot
                .appending(path: "Content/Bundled/Ghosts", directoryHint: .isDirectory)
                .standardizedFileURL
            let sourcePath = source.standardizedFileURL.path
            guard sourcePath.hasPrefix(bundledGhosts.path + "/") else { return source }

            let destination = contentDirectory
                .appending(path: "Debug/YAYA", directoryHint: .isDirectory)
                .appending(path: ghost.rootDirectory.lastPathComponent, directoryHint: .isDirectory)
                .appending(path: "master", directoryHint: .isDirectory)
            try synchronizeYayaMaster(from: source, to: destination)
            return destination
        #else
            return source
        #endif
    }

    private static func synchronizeYayaMaster(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let sourceItem as URL in enumerator {
            let relativePath = String(sourceItem.path.dropFirst(source.path.count + 1))
            let destinationItem = destination.appending(path: relativePath)
            let isDirectory = try sourceItem.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                try fileManager.createDirectory(at: destinationItem, withIntermediateDirectories: true)
            } else if !sourceItem.lastPathComponent.hasSuffix("_variable.cfg") {
                try fileManager.createDirectory(
                    at: destinationItem.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationItem.path) {
                    try fileManager.removeItem(at: destinationItem)
                }
                try fileManager.copyItem(at: sourceItem, to: destinationItem)
            } else if !fileManager.fileExists(atPath: destinationItem.path) {
                try fileManager.copyItem(at: sourceItem, to: destinationItem)
            }
        }
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
            guard let hostPath = environment["UTATANE_MATERIA_HOST"],
                  let materiaPath = environment["UTATANE_MATERIA_EXE"]
            else {
                return nil
            }
            hostExecutableURL = URL(filePath: hostPath, directoryHint: .notDirectory)
            materiaExecutableURL = URL(filePath: materiaPath, directoryHint: .notDirectory)
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

    static var ghostReadDirectories: [URL] {
        #if DEBUG
            let bundled = repositoryRoot.appending(path: "Content/Bundled/Ghosts", directoryHint: .isDirectory)
            return [bundled, ghostsDirectory]
        #else
            return [ghostsDirectory]
        #endif
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

    static var balloonReadDirectories: [URL] {
        #if DEBUG
            let bundled = repositoryRoot.appending(path: "Content/Bundled/Balloons", directoryHint: .isDirectory)
            return [bundled, balloonsDirectory]
        #else
            return [balloonsDirectory]
        #endif
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

import AppKit
import UniformTypeIdentifiers
import UtataneBalloon
import UtataneContent
import UtataneCore
import UtataneNetwork
import UtatanePlatformMacOS
import UtataneRuntime
import UtataneSakuraScript
import UtataneShell

@MainActor
final class CalledGhostRuntime {
    let ghost: InstalledGhost
    let surfaceController: SurfaceWindowController
    let balloonController: BalloonWindowController
    let player: SakuraScriptPlayer
    let session: GhostSession

    private let shellLoader: ShellLoader
    private let selectionStore: ContentSelectionStore
    private let weatherProvider = CurrentWeatherProvider()
    private let webSocketManager = WebSocketSessionManager()
    private let propertySystem: PropertySystem
    private let presentationSession: GhostPresentationSession?
    private let presentationGeometry: any PresentationGeometryProviding
    private let textInputWindowController = TextInputWindowController()
    private let systemDialogController = SystemDialogController()
    private let speechHistoryStore: SpeechHistoryStore
    private let speechHistoryWindowController: SpeechHistoryWindowController
    private let speechHistoryPresenter: SpeechHistoryPresenter?
    private let speechSynthesizer = SpeechSynthesisRouter()
    private var integratesSpeechHistory: Bool
    private let speechRecognitionEnabled: Bool
    private var speechHistoryTextScale: CGFloat = 1
    private var weatherTask: Task<Void, Never>?
    private var sntpCoordinator: SNTPEventCoordinator?
    private var inFlightHTTPTasks: [String: Task<Void, Never>] = [:]
    private var teachHistory: [String] = []
    private var pendingHourTimeSignal = false
    private let periodicEventRunner = CoalescingTaskRunner()
    private let mouseEventCoordinator = MouseEventResponseCoordinator()
    private var windowMode: GhostWindowMode
    private var windowLevelBehavior: GhostWindowLevelBehavior = .always
    private(set) var shell: InstalledShell
    private(set) var balloon: BalloonDefinition

    var layoutPresetStageFrame: CGRect? {
        presentationSession?.layoutPresetStageFrame
    }

    func restoreLayoutPreset(_ preset: LayoutPresetGhost) {
        presentationSession?.restoreLayoutPresetStageFrame(preset.stageFrame)
        surfaceController.restoreLayoutPresetPositions(preset.positions)
        balloonController.restoreLayoutPresetPositions(preset.balloonPositions)
    }

    var contextMenuItems: ((Int) -> [SurfaceContextMenuItem])? {
        didSet { surfaceController.contextMenuItems = { [weak self] scope in self?.contextMenuItems?(scope) ?? [] } }
    }

    var onError: ((Error) -> Void)?
    var onCommunication: ((String, String) -> Void)?
    var onNarDrop: (([URL]) -> Void)?
    var onOpenMessenger: (() -> Void)?
    var onContentAction: ((SakuraScriptContentAction) -> Void)?
    var onOtherEvent: ((String, String, [String], Bool) async -> Void)?
    var onOtherGhostTalk: ((String, String) -> Void)?
    var onOtherSurfaceChange: ((String, Int, Int) -> Void)?
    var onSurfaceChanged: ((Int, Int?, Int) -> Void)?
    var onSpeechSynthesisActivity: (@MainActor @Sendable (Bool) -> Void)? {
        didSet { player.onSpeechSynthesisActivity = onSpeechSynthesisActivity }
    }

    init(
        ghost: InstalledGhost,
        balloons: [BalloonDefinition],
        shellLoader: ShellLoader,
        selectionStore: ContentSelectionStore,
        defaultBalloonDirectoryName: String?,
        personalityEngine: any PersonalityEngine,
        characterDelayMilliseconds: Int,
        dialogueDismissalMilliseconds: Int,
        speechSynthesisEnabled: Bool,
        speechVoiceSettingsByScope: [Int: UtataneSettingsStore.SpeechVoiceSettings],
        speechRecognitionEnabled: Bool,
        speechHistoryStore: SpeechHistoryStore,
        integratesSpeechHistory: Bool,
        windowMode: GhostWindowMode,
        presentationSession: GhostPresentationSession? = nil,
        presentationGeometry: any PresentationGeometryProviding = SystemPresentationGeometryProvider()
    ) throws {
        let effectivePresentationGeometry = presentationSession?.geometryProvider ?? presentationGeometry
        self.ghost = ghost
        self.shellLoader = shellLoader
        self.selectionStore = selectionStore
        self.speechHistoryStore = speechHistoryStore
        speechHistoryWindowController = SpeechHistoryWindowController(store: speechHistoryStore)
        let historyContext = SpeechHistoryContext(
            ghostIdentifier: ghost.id.path,
            ghostName: ghost.name,
            speakerNames: Dictionary(uniqueKeysWithValues: ghost.characters.compactMap { character in
                character.name.map { (character.scope, $0) }
            })
        )
        speechHistoryPresenter = presentationSession.map {
            SpeechHistoryPresenter(
                store: speechHistoryStore,
                context: historyContext,
                presentationSession: $0
            )
        }
        self.integratesSpeechHistory = integratesSpeechHistory
        self.speechRecognitionEnabled = speechRecognitionEnabled
        self.windowMode = windowMode
        self.presentationSession = presentationSession
        self.presentationGeometry = effectivePresentationGeometry
        var propertyValues = Self.propertyValues(for: ghost).merging(
            MacOSPropertySnapshot.values(geometryProvider: effectivePresentationGeometry)
        ) { current, _ in current }
        propertyValues["baseware.windowmode"] = windowMode.sspIdentifier
        propertySystem = PropertySystem(configuration: .init(
            basewareName: "Utatane",
            basewareVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            values: propertyValues
        ))

        guard let selectedShell = selectionStore.resolveShell(for: ghost) else {
            throw AppError.missingResource("shell")
        }
        guard let selectedBalloon = selectionStore.resolveBalloon(
            for: ghost,
            from: balloons,
            defaultDirectoryName: defaultBalloonDirectoryName
        ) else {
            throw AppError.missingResource("balloon")
        }
        shell = selectedShell
        balloon = selectedBalloon

        let positionStore = WindowPositionStore()
        positionStore.setContentID(ghost.id)
        if let presentationSession {
            surfaceController = SurfaceWindowController(
                positionStore: positionStore,
                presentationSession: presentationSession
            )
            balloonController = BalloonWindowController(
                positionStore: positionStore,
                presentationSession: presentationSession
            )
        } else {
            surfaceController = SurfaceWindowController(
                positionStore: positionStore,
                geometryProvider: effectivePresentationGeometry
            )
            balloonController = BalloonWindowController(
                positionStore: positionStore,
                geometryProvider: effectivePresentationGeometry
            )
        }
        player = SakuraScriptPlayer(
            surfaceWindowController: surfaceController,
            balloonWindowController: balloonController,
            geometryProvider: effectivePresentationGeometry
        )
        session = GhostSession(
            personalityEngine: personalityEngine,
            variableStore: GhostVariableStore(fileURL: ContentRoot.variableStoreURL(for: ghost)),
            logStore: .shared,
            ghostName: ghost.name
        )
        player.configurePlayback(
            characterDelayMilliseconds: characterDelayMilliseconds,
            postDialogueDismissalMilliseconds: dialogueDismissalMilliseconds
        )
        player.configureSpeechSynthesis(
            synthesizer: speechSynthesisEnabled ? speechSynthesizer : nil,
            configuration: speechSynthesisEnabled ? { scope in
                (speechVoiceSettingsByScope[scope] ?? .init()).synthesisConfiguration
            } : nil
        )
        player.configure(resourceBaseDirectory: ghost.rootDirectory.appending(
            path: "ghost/master",
            directoryHint: .isDirectory
        ))
        let mainName = ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name
        player.configureSpeechHistory(
            store: speechHistoryStore,
            context: historyContext
        )
        player.configure(environmentVariables: [
            "selfname": mainName,
            "selfname2": mainName,
            "keroname": ghost.characters.first(where: { $0.scope == 1 })?.name ?? ""
        ])
        configureCallbacks()
        surfaceController.onUserDressupChange = { [weak player] changes in
            Task { await player?.notifyDressupChanges(changes, source: "user") }
        }
    }

    func start(
        caller: InstalledGhost,
        desktopWallpaperEvent: DesktopWallpaperChangeEvent? = nil
    ) async throws -> String? {
        try show(shell: shell)
        surfaceController.setPresentationHidden(true)
        _ = try? await session.start(event: .shiori(id: "OnInitialize", references: [:]))
        if let definition = try? shellLoader.load(from: shell.directory) {
            for event in startupInformationEvents(
                ghost: ghost,
                shell: shell,
                balloon: balloon,
                shellDefinition: definition,
                windowMode: windowMode,
                speechSynthesisEnabled: player.isSpeechSynthesisEnabled,
                speechRecognitionEnabled: speechRecognitionEnabled
            ) {
                _ = try? await session.handle(event: .notification(
                    id: event.id,
                    references: event.references
                ))
            }
        }
        if let desktopWallpaperEvent {
            _ = try? await session.handle(event: desktopWallpaperGhostEvent(desktopWallpaperEvent))
        }
        let script = try await session.handle(
            event: SHIORIEventFactory.ghostCalled(
                callerCharacterName: caller.characters.first(where: { $0.scope == 0 })?.name ?? caller.name,
                callerScript: "",
                callerGhostName: caller.name,
                callerGhostPath: caller.rootDirectory.path,
                shellName: shell.name
            ),
            fallingBackTo: SHIORIEventFactory.boot(shellName: shell.name)
        )
        surfaceController.setPresentationHidden(false)
        if let script {
            player.play(script, balloon: balloon)
        }
        return script?.rawValue
    }

    func send(_ event: GhostEvent) {
        send([event])
    }

    private func dispatchMouseEvent(_ event: GhostMouseEvent) {
        mouseEventCoordinator.submit(
            event,
            request: requestMouseEvent,
            receive: receiveMouseResponse
        )
    }

    private func requestMouseEvent(_ event: GhostEvent) async -> PersonalityResponse? {
        do {
            return try await session.response(for: event)
        } catch {
            AppLogStore.shared.error(
                "マウスイベント処理エラー: \(error.localizedDescription)",
                category: "SHIORI",
                details: String(describing: error),
                ghostName: ghost.name
            )
            onError?(error)
            return nil
        }
    }

    private func receiveMouseResponse(_ response: PersonalityResponse) {
        if let script = response.script, !script.rawValue.isEmpty {
            player.play(script, balloon: balloon)
        }
        forwardCommunication(response)
    }

    func send(_ event: GhostEvent, fallingBackTo fallback: GhostEvent) {
        Task {
            do {
                let response = try await session.response(for: event)
                if let script = response?.script, !script.rawValue.isEmpty {
                    player.play(script, balloon: balloon)
                    if let response {
                        forwardCommunication(response)
                    }
                    return
                }
                guard let fallbackResponse = try await session.response(for: fallback) else { return }
                if let script = fallbackResponse.script, !script.rawValue.isEmpty {
                    player.play(script, balloon: balloon)
                }
                forwardCommunication(fallbackResponse)
            } catch {
                AppLogStore.shared.error(
                    "SHIORIイベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Event: \(event)\nFallback: \(fallback)\nError: \(error)",
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    func sendWindowModeChange(references: [Int: String]) {
        send([
            .shiori(id: "OnWindowModeChange", references: references),
            .shiori(id: "OnDisplayChange", references: displayChangeReferences())
        ])
    }

    private func send(_ events: [GhostEvent]) {
        Task {
            do {
                for event in events {
                    guard let response = try await session.response(for: event) else { continue }
                    if let script = response.script {
                        player.play(script, balloon: balloon)
                    }
                    forwardCommunication(response)
                }
            } catch {
                AppLogStore.shared.error(
                    "SHIORIイベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Events: \(events)\nError: \(error)",
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    func sendNowPlayingTrack(_ track: NowPlayingTrack) {
        let route = track.sspEventRoute
        Task {
            do {
                let extended = try await session.response(for: .shiori(
                    id: route.extendedEventID,
                    references: track.sspExtendedReferences
                ))
                if let extended {
                    forwardCommunication(extended)
                    if let script = extended.script, !script.rawValue.isEmpty {
                        player.play(script, balloon: balloon)
                        return
                    }
                }
                guard let legacyEventID = route.legacyEventID,
                      let legacy = try await session.response(for: .shiori(
                          id: legacyEventID,
                          references: [0: track.title, 1: track.artist]
                      )) else { return }
                if let script = legacy.script, !script.rawValue.isEmpty {
                    player.play(script, balloon: balloon)
                }
                forwardCommunication(legacy)
            } catch {
                AppLogStore.shared.error(
                    "再生情報イベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Title: \(track.title)\nError: \(error)",
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    func sendSecondChange(references: [Int: String]) {
        let canTalk = player.canTalk
        var references = references
        // UKADOC / SSP standard: 1 for talkable, 0 while dialogue is being played.
        references[3] = canTalk ? "1" : "0"
        periodicEventRunner.submit { [self] in
            do {
                guard let response = try await session.response(for: .shiori(
                    id: "OnSecondChange",
                    references: references
                )) else { return }
                guard !Task.isCancelled, canTalk else { return }
                if let script = response.script {
                    player.play(script, balloon: balloon)
                }
                forwardCommunication(response)
            } catch {
                AppLogStore.shared.error(
                    "OnSecondChangeエラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: String(describing: error),
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    func sendTimedEvent(id: String, references: [Int: String], waitsUntilTalkable: Bool) {
        let canTalk = player.canTalk
        guard !waitsUntilTalkable || canTalk else { return }
        var references = references
        references[3] = canTalk ? "1" : "0"
        Task {
            guard let response = try? await session.response(for: .shiori(id: id, references: references)) else {
                return
            }
            guard canTalk else { return }
            if let script = response.script {
                player.play(script, balloon: balloon)
            }
            forwardCommunication(response)
        }
    }

    func scheduleHourTimeSignal() {
        pendingHourTimeSignal = true
    }

    func flushHourTimeSignal(references: [Int: String]) {
        guard pendingHourTimeSignal, player.canTalk else { return }
        pendingHourTimeSignal = false
        sendTimedEvent(id: "OnHourTimeSignal", references: references, waitsUntilTalkable: true)
    }

    func communicate(from sender: String, sentence: String) async -> PersonalityResponse? {
        let response = try? await session.response(for: .shiori(
            id: "OnCommunicate",
            references: [0: sender, 1: sentence]
        ))
        if let script = response?.script {
            player.play(script, balloon: balloon)
        }
        return response
    }

    func handleExternalEvent(id: String, arguments: [String], reflectsResponse: Bool) async {
        guard let response = try? await session.handle(event: .shiori(
            id: id,
            references: Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                ($0.offset, $0.element)
            })
        )) else { return }
        if reflectsResponse, !response.rawValue.isEmpty {
            player.play(response, balloon: balloon)
        }
    }

    func notify(_ event: GhostEvent) async {
        _ = try? await session.handle(event: event)
    }

    func prepareVanish() async {
        await playAndWait(eventID: "OnVanishSelecting")
    }

    func cancelVanish() async {
        await playAndWait(eventID: "OnVanishCancel")
    }

    func notifyOtherGhostVanished(references: [Int: String]) async {
        var references = references
        references[7] = shell.name
        let otherScript = try? await session.handle(event: .shiori(
            id: "OnOtherGhostVanished",
            references: references
        ))
        if let otherScript {
            player.play(otherScript, balloon: balloon)
            return
        }
        if let fallback = try? await session.handle(event: .shiori(
            id: "OnVanished",
            references: references
        )) {
            player.play(fallback, balloon: balloon)
        }
    }

    func stop() async -> String {
        await stop(reason: .close)
    }

    func stopForVanish() async -> String {
        await stop(reason: .vanish)
    }

    private func stop(reason: GhostStopReason) async -> String {
        periodicEventRunner.cancel()
        mouseEventCoordinator.cancel()
        await webSocketManager.cancelAll()
        cancelHTTP(url: nil)
        var finalScript = ""
        _ = try? await session.handle(event: .shiori(id: "OnDestroy", references: [:]))
        if let script = try? await session.stop(reason: reason) {
            finalScript = script.rawValue
            await player.playAndWait(script, balloon: balloon)
        }
        player.cancel()
        surfaceController.resetContent()
        balloonController.resetContent()
        speechHistoryPresenter?.discard()
        speechHistoryWindowController.close()
        return finalScript
    }

    private func playAndWait(eventID: String) async {
        guard let script = try? await session.handle(event: .shiori(id: eventID, references: [:])) else {
            return
        }
        await player.playAndWait(script, balloon: balloon)
    }

    func setIntegratesSpeechHistory(_ integrates: Bool) {
        integratesSpeechHistory = integrates
        if !integrates {
            speechHistoryPresenter?.hide()
        }
    }

    func setWindowMode(_ mode: GhostWindowMode) async {
        windowMode = mode
        await propertySystem.register(values: ["baseware.windowmode": mode.sspIdentifier])
    }

    private func displayChangeReferences() -> [Int: String] {
        guard let screen = presentationGeometry.mainScreen else { return [:] }
        return [
            0: String(screen.bitsPerPixel),
            1: String(Int(screen.frame.width)),
            2: String(Int(screen.frame.height))
        ]
    }

    func showSpeechHistory() {
        if integratesSpeechHistory, speechHistoryPresenter?.show() == true {
            speechHistoryWindowController.close()
            return
        }
        speechHistoryWindowController.show(
            ghostIdentifier: ghost.id.path,
            ghostName: ghost.name,
            textScale: speechHistoryTextScale
        )
    }

    func select(shell newShell: InstalledShell) {
        do {
            let previousShell = shell
            send(SHIORIEventFactory.shellChanging(
                newShellName: newShell.name,
                previousShellName: previousShell.name,
                newShellPath: newShell.directory.path
            ))
            try show(shell: newShell)
            send(SHIORIEventFactory.shellChanged(
                shellName: newShell.name,
                ghostName: ghost.name,
                shellPath: newShell.directory.path
            ))
        } catch {
            AppLogStore.shared.error(
                "シェル切り替えエラー「\(newShell.name)」: \(error.localizedDescription)",
                category: "Shell",
                details: String(describing: error),
                ghostName: ghost.name
            )
            onError?(error)
        }
    }

    func select(balloon newBalloon: BalloonDefinition) {
        player.cancel()
        balloon = newBalloon
        selectionStore.setBalloonDirectoryName(newBalloon.directory.lastPathComponent, for: ghost.id)
        send(SHIORIEventFactory.balloonChange(
            name: newBalloon.name,
            path: newBalloon.directory.path
        ))
    }

    func configurePlayback(characterDelayMilliseconds: Int, dismissalMilliseconds: Int) {
        player.configurePlayback(
            characterDelayMilliseconds: characterDelayMilliseconds,
            postDialogueDismissalMilliseconds: dismissalMilliseconds
        )
    }

    func configureSpeechSynthesis(
        enabled: Bool,
        settingsByScope: [Int: UtataneSettingsStore.SpeechVoiceSettings]
    ) {
        player.configureSpeechSynthesis(
            synthesizer: enabled ? speechSynthesizer : nil,
            configuration: enabled ? { scope in
                (settingsByScope[scope] ?? .init()).synthesisConfiguration
            } : nil
        )
    }

    func configureDisplay(
        shellPercent: Int,
        automaticallyFitsLargeSurfaces: Bool,
        balloonPercent: Int,
        textPercent: Int,
        windowLevelBehavior: GhostWindowLevelBehavior
    ) {
        surfaceController.setDisplayScale(Double(shellPercent) / 100)
        surfaceController.setAutomaticallyFitsLargeSurfaces(automaticallyFitsLargeSurfaces)
        balloonController.setDisplayScale(
            Double(balloonPercent) / 100,
            textScale: Double(textPercent) / 100,
            surfaceScale: Double(shellPercent) / 100
        )
        speechHistoryTextScale = CGFloat(textPercent) / 100
        speechHistoryPresenter?.setTextScale(speechHistoryTextScale)
        self.windowLevelBehavior = windowLevelBehavior
        applyWindowLevel(isTalking: player.isDialogueActive)
    }

    func configureWindowLevel(_ behavior: GhostWindowLevelBehavior) {
        windowLevelBehavior = behavior
        applyWindowLevel(isTalking: player.isDialogueActive)
    }

    private func applyWindowLevel(isTalking: Bool) {
        let staysOnTop = windowLevelBehavior.staysOnTop(isTalking: isTalking)
        surfaceController.setStayOnTop(staysOnTop)
        balloonController.setStayOnTop(staysOnTop)
    }

    func resetWindowPositions() {
        send(.shiori(id: "OnResetWindowPos", references: [:]))
        surfaceController.resetWindowPositions()
        balloonController.resetWindowPositions()
    }

    private func show(shell newShell: InstalledShell) throws {
        player.cancel()
        let definition = try shellLoader.load(from: newShell.directory)
        balloonController.configure(shell: definition)
        try surfaceController.show(
            shell: definition,
            defaultSurfaceIDs: Dictionary(uniqueKeysWithValues: ghost.characters.map {
                ($0.scope, $0.defaultSurfaceID)
            })
        )
        player.configure(defaultBalloonSurfaceIDs: Dictionary(uniqueKeysWithValues: ghost.characters.map {
            ($0.scope, $0.defaultBalloonSurfaceID)
        }))
        shell = newShell
        selectionStore.setShellDirectoryName(newShell.directory.lastPathComponent, for: ghost.id)
    }

    private func currentSurfaceReferences() -> [Int: String] {
        Dictionary(uniqueKeysWithValues: [0, 1].compactMap { scope in
            surfaceController.surfaceID(for: scope).map { (scope, String($0)) }
        })
    }

    private func configureCallbacks() {
        surfaceController.onMouseEvent = { [weak self] event in
            guard let self, !player.isTimeCritical else { return }
            dispatchMouseEvent(event)
        }
        surfaceController.onMouseGesture = { [weak self] event in
            guard let self, !player.isTimeCritical else { return }
            send(.shiori(id: "OnMouseGesture", references: event.references))
        }
        surfaceController.onSurfaceChange = { [weak self] scope, previous, current in
            guard let self else { return }
            send(.shiori(id: "OnSurfaceChange", references: currentSurfaceReferences()))
            onSurfaceChanged?(scope, previous, current)
        }
        surfaceController.onNarDrop = { [weak self] _, urls in self?.onNarDrop?(urls) }
        surfaceController.onFileDropping = { [weak self] scope, urls in
            guard let event = FileDropEventRouter.dropping(scope: scope, urls: urls) else { return }
            self?.send(event)
        }
        surfaceController.onFileDrop = { [weak self] scope, urls in
            self?.sendFileDropEvents(scope: scope, urls: urls)
        }
        surfaceController.onURLDropping = { [weak self] scope, url in
            self?.send(.shiori(id: "OnURLDragDropping", references: [0: url.absoluteString, 1: String(scope)]))
        }
        surfaceController.onURLDrop = { [weak self] scope, url in
            self?.handleURLDrop(scope: scope, url: url)
        }
        surfaceController.onTextDrop = { [weak self] scope, value in
            self?.send(SHIORIEventFactory.textDrop(value, scope: scope))
        }
        player.onError = { [weak self] error in
            guard let self else { return }
            AppLogStore.shared.error(
                "スクリプト実行エラー: \(error.localizedDescription)",
                category: "Script",
                details: String(describing: error),
                ghostName: ghost.name
            )
            onError?(error)
        }
        player.onDialogueContent = { [weak self] in
            self?.surfaceController.setPresentationHidden(false)
            self?.applyWindowLevel(isTalking: true)
        }
        player.onPlaybackFinished = { [weak self] in
            self?.surfaceController.setPresentationHidden(false)
            self?.applyWindowLevel(isTalking: false)
        }
        player.onSurfaceRestore = { [weak self] in
            guard let self else { return }
            send(.shiori(id: "OnSurfaceRestore", references: currentSurfaceReferences()))
        }
        player.onBalloonClose = { [weak self] script in
            self?.send(.shiori(id: "OnBalloonClose", references: [0: script]))
        }
        player.onBalloonTimeout = { [weak self] script in
            self?.send(.shiori(id: "OnBalloonTimeout", references: [0: script, 1: "0"]))
        }
        player.onChoice = { [weak self] id, arguments in
            if let url = URL(string: id), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                NSWorkspace.shared.open(url)
            } else {
                self?.send(.choice(id: id, arguments: arguments))
            }
        }
        player.onChoiceSelection = { [weak self] label, id, arguments in
            self?.sendChoiceSelection(label: label, id: id, arguments: arguments)
        }
        player.onChoiceSelectEx = nil
        player.onAnchorSelectEx = { [weak self] label, id, arguments in
            self?.sendAnchorSelection(label: label, id: id, arguments: arguments)
        }
        player.onAnchorSelect = nil
        player.onChoiceEnter = { [weak self] label, id, arguments in
            self?.send(.shiori(id: "OnChoiceEnter", references: linkEventReferences(label, id, arguments)))
        }
        player.onChoiceHover = { [weak self] label, id, arguments in
            self?.send(.shiori(id: "OnChoiceHover", references: linkEventReferences(label, id, arguments)))
        }
        player.onAnchorEnter = { [weak self] label, id, arguments in
            self?.send(.shiori(id: "OnAnchorEnter", references: linkEventReferences(label, id, arguments)))
        }
        player.onAnchorHover = { [weak self] label, id, arguments in
            self?.send(.shiori(id: "OnAnchorHover", references: linkEventReferences(label, id, arguments)))
        }
        player.onSoundStop = { [weak self] file, reason in
            self?.send(.shiori(id: "OnSoundStop", references: [0: file, 1: reason]))
        }
        player.onSoundLoop = { [weak self] file in
            self?.send(.shiori(id: "OnSoundLoop", references: [0: file]))
        }
        player.onSoundError = { [weak self] file, error in
            let nsError = error as NSError
            self?.send(.shiori(id: "OnSoundError", references: [
                0: "play", 1: String(nsError.code), 2: file, 3: error.localizedDescription
            ]))
        }
        player.onChoiceTimeout = { [weak self] script in
            self?.send(.shiori(id: "OnChoiceTimeout", references: [0: script]))
        }
        player.onOpen = { [weak self] target in
            if target.caseInsensitiveCompare("messenger") == .orderedSame {
                self?.onOpenMessenger?()
                return
            }
            if target.caseInsensitiveCompare("backlogviewer") == .orderedSame {
                self?.showSpeechHistory()
                return
            }
            guard let url = URL(string: target),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme)
            else { return }
            NSWorkspace.shared.open(url)
        }
        player.onContentAction = { [weak self] action in self?.onContentAction?(action) }
        player.onOtherEvent = { [weak self] target, id, arguments, reflectsResponse in
            await self?.onOtherEvent?(target, id, arguments, reflectsResponse)
        }
        player.onEmbeddedEvent = { [weak self] id, arguments in
            guard let self else { return nil }
            return try? await session.handle(event: .shiori(
                id: id,
                references: Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                    ($0.offset, $0.element)
                })
            ))
        }
        player.onPropertyValue = { [weak self] property in
            guard let self else { return nil }
            await propertySystem.register(values: MacOSPropertySnapshot.values(
                geometryProvider: presentationGeometry
            ))
            return try? await propertySystem.value(for: property)
        }
        player.onGetProperties = { [weak self] eventID, properties in
            guard let self else { return nil }
            await propertySystem.register(values: MacOSPropertySnapshot.values(
                geometryProvider: presentationGeometry
            ))
            let values = await propertySystem.values(for: properties)
            return try? await session.handle(event: .shiori(
                id: eventID,
                references: Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset, $0.element) })
            ))
        }
        player.onSetProperty = { [weak self] property, value in
            guard let self else { return }
            try? await propertySystem.setValue(value, for: property)
        }
        player.onSystemDialog = { [weak self] command in
            guard let self else { return nil }
            let result = systemDialogController.show(command)
            let eventID = command.id.hasPrefix("On")
                ? command.id
                : (result.value == nil ? "OnSystemDialogCancel" : "OnSystemDialog")
            var references = [0: command.kind.rawValue, 1: command.id]
            if let value = result.value {
                references[2] = value
            }
            return try? await session.handle(event: .shiori(id: eventID, references: references))
        }
        player.onCloseSystemDialog = { [weak self] id in
            self?.systemDialogController.close(id: id)
        }
        player.onInputBox = { [weak self] id, timeoutMilliseconds, initialValue in
            guard let self else { return nil }
            let autocomplete = try? await session.handle(event: .shiori(
                id: "inputbox.autocomplete",
                references: [0: "inputbox", 1: id]
            ))
            guard let value = await textInputWindowController.showPrompt(
                id: id,
                title: String(localized: "文字を入力"),
                initialValue: initialValue,
                autocompleteValues: TextInputWindowController.autocompleteValues(
                    from: autocomplete?.rawValue
                ),
                actionTitle: String(localized: "OK"),
                appearance: textInputAppearance(style: .input),
                timeoutMilliseconds: timeoutMilliseconds
            ) else {
                return try? await session.handle(event: .shiori(
                    id: "OnUserInputCancel",
                    references: [0: id, 1: "close", 2: ""]
                ))
            }
            if id.hasPrefix("On") {
                return try? await session.handle(event: .shiori(
                    id: id,
                    references: [0: value, 1: ""]
                ))
            }
            return try? await session.handle(event: .shiori(
                id: "OnUserInput",
                references: [0: id, 1: value, 2: ""]
            ))
        }
        player.onCloseInputBox = { [weak self] id in
            self?.textInputWindowController.close(id: id)
        }
        player.onHTTP = { [weak self] request in
            guard let self else { return nil }
            if request.waitsForCompletion {
                return await handleHTTP(request)
            }
            cancelHTTP(url: request.url)
            inFlightHTTPTasks[request.url] = Task { [weak self] in
                guard let self else { return }
                let response = await handleHTTP(request)
                guard !Task.isCancelled else { return }
                inFlightHTTPTasks.removeValue(forKey: request.url)
                if let response, !response.rawValue.isEmpty {
                    player.play(response, balloon: balloon)
                }
            }
            return nil
        }
        player.onCancelHTTP = { [weak self] url in self?.cancelHTTP(url: url) }
        player.onNetworkDiagnostic = { [weak self] command in
            guard let self else { return nil }
            return await handleNetworkDiagnostic(command)
        }
        player.onWebSocket = { [weak self] command in
            await self?.handleWebSocket(command)
        }
        player.onArchive = { [weak self] command in
            guard let self else { return nil }
            return await handleArchive(command)
        }
        player.onCommunicateBox = { [weak self] initialValue in
            guard let self else { return nil }
            let autocomplete = try? await session.handle(event: .shiori(
                id: "inputbox.autocomplete",
                references: [0: "communicatebox"]
            ))
            guard let value = await textInputWindowController.showPrompt(
                title: String(localized: "文字を入力"),
                initialValue: initialValue,
                autocompleteValues: TextInputWindowController.autocompleteValues(
                    from: autocomplete?.rawValue
                ),
                actionTitle: String(localized: "OK"),
                appearance: textInputAppearance(style: .communicate)
            ) else {
                return try? await session.handle(event: SHIORIEventFactory.communicateInputCancel)
            }
            return try? await session.handle(event: .shiori(
                id: "OnCommunicate",
                references: [0: "user", 1: value]
            ))
        }
        player.onTeachBox = { [weak self] initialValue in
            guard let self else { return nil }
            _ = try? await session.handle(event: SHIORIEventFactory.teachStart)
            let autocomplete = try? await session.handle(event: .shiori(
                id: "inputbox.autocomplete",
                references: [0: "teachbox"]
            ))
            guard let value = await textInputWindowController.showPrompt(
                title: String(localized: "文字を入力"),
                initialValue: initialValue,
                autocompleteValues: TextInputWindowController.autocompleteValues(
                    from: autocomplete?.rawValue
                ),
                actionTitle: String(localized: "OK"),
                appearance: textInputAppearance(style: .teach)
            ) else {
                return try? await session.handle(event: SHIORIEventFactory.teachInputCancel)
            }
            teachHistory.append(value)
            return try? await session.handle(event: SHIORIEventFactory.teach(history: teachHistory))
        }
        player.onOtherGhostTalk = { [weak self] target, script in
            self?.onOtherGhostTalk?(target, script)
        }
        player.onOtherSurfaceChange = { [weak self] target, scope, surfaceID in
            self?.onOtherSurfaceChange?(target, scope, surfaceID)
        }
        player.onWeatherGet = { [weak self] eventID in
            guard let self else { return nil }
            weatherTask?.cancel()
            weatherTask = Task { [weak self] in
                await self?.fetchWeatherAndPlay(eventID: eventID)
            }
            return nil
        }
        player.onSNTPStart = { [weak self] in
            guard let self else { return nil }
            if sntpCoordinator == nil {
                sntpCoordinator = SNTPEventCoordinator { [weak self] id, references in
                    guard let self else { return nil }
                    return try? await session.handle(event: .shiori(id: id, references: references))
                }
            }
            return await sntpCoordinator?.start()
        }
        player.onSNTPCorrect = { [weak self] in
            await self?.sntpCoordinator?.correct()
        }
    }

    private static func propertyValues(for ghost: InstalledGhost) -> [String: String] {
        var values = [
            "currentghost.name": ghost.name,
            "currentghost.sakuraname": ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name,
            "currentghost.keroname": ghost.characters.first(where: { $0.scope == 1 })?.name ?? "",
            "currentghost.path": ghost.rootDirectory.path,
            "currentghost.shelllist.count": String(ghost.shells.count)
        ]
        for (index, shell) in ghost.shells.enumerated() {
            let prefix = "currentghost.shelllist.index(\(index))"
            values["\(prefix).name"] = shell.name
            values["\(prefix).path"] = shell.directory.path
            values["\(prefix).index"] = String(index)
            values["currentghost.shelllist(\(shell.name)).name"] = shell.name
            values["currentghost.shelllist(\(shell.name)).path"] = shell.directory.path
            values["currentghost.shelllist(\(shell.name)).index"] = String(index)
        }
        values["currentghost.shelllist.current.name"] = ghost.shells.first?.name ?? ""
        values["currentghost.shelllist.current.path"] = ghost.shells.first?.directory.path ?? ""
        values["currentghost.shelllist.current.index"] = "0"
        return values
    }

    func play(_ script: SakuraScript) {
        player.play(script, balloon: balloon)
    }

    func changeSurface(to surfaceID: Int, scope: Int = 0) {
        try? surfaceController.changeSurface(scope: scope, to: surfaceID)
    }

    private func sendFileDropEvents(scope: Int, urls: [URL]) {
        guard !urls.isEmpty else { return }
        for event in FileDropEventRouter.directoryEvents(scope: scope, urls: urls) {
            send(event)
        }
        Task {
            do {
                guard let droppedEvent = FileDropEventRouter.dropped(scope: scope, urls: urls) else { return }
                let response = try await session.response(for: droppedEvent)
                if let script = response?.script {
                    player.play(script, balloon: balloon)
                    if let response {
                        forwardCommunication(response)
                    }
                    return
                }
                guard let url = urls.first,
                      let viewerEvent = FileDropEventRouter.viewerOpened(scope: scope, urls: urls),
                      NSWorkspace.shared.open(url)
                else { return }
                send(viewerEvent)
            } catch {
                AppLogStore.shared.error(
                    "ファイルドロップ処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Files: \(urls.map(\.path).joined(separator: "\n"))",
                    ghostName: ghost.name
                )
            }
        }
    }

    private func handleURLDrop(scope: Int, url: URL) {
        let plannedAction = url.pathExtension.caseInsensitiveCompare("nar") == .orderedSame ? "nar" : "unknown"
        let queryReferences = [
            0: url.absoluteString,
            1: String(scope),
            2: FileDropEventRouter.mimeType(url),
            3: plannedAction
        ]
        Task {
            do {
                if let response = try await session.response(for: .shiori(
                    id: "OnURLQuery",
                    references: queryReferences
                )), let script = response.script {
                    player.play(script, balloon: balloon)
                    forwardCommunication(response)
                    return
                }
                guard plannedAction == "nar" else { return }
                send(.shiori(id: "OnURLDropping", references: [
                    0: url.absoluteString, 1: String(scope)
                ]))
                let localURL = try await downloadDroppedNar(from: url)
                send(.shiori(id: "OnURLDropped", references: [
                    0: localURL.path, 1: url.absoluteString, 2: String(scope)
                ]))
                onNarDrop?([localURL])
            } catch {
                send(.shiori(id: "OnURLDropFailure", references: [
                    0: "", 1: urlDropFailureReason(error), 2: url.absoluteString, 3: String(scope)
                ]))
            }
        }
    }

    func updateEnvironmentVariables(_ variables: [String: String]) {
        player.updateEnvironmentVariables(variables)
    }

    private func handleHTTP(_ command: SakuraScriptHTTPRequest) async -> SakuraScript? {
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
            let cookie = httpResponse?.value(forHTTPHeaderField: "Set-Cookie") ?? ""
            let headers = Self.httpResponseHeaders(httpResponse)
            if !(200 ..< 300).contains(statusCode) {
                guard let eventID = command.eventID else { return nil }
                let event = if command.isFeed {
                    SHIORIEventFactory.executeRSSFailure(
                        eventID: eventID,
                        method: command.method,
                        url: command.url,
                        reason: String(statusCode),
                        cookie: cookie,
                        headers: headers
                    )
                } else {
                    SHIORIEventFactory.executeHTTPFailure(
                        eventID: eventID,
                        method: command.method,
                        url: command.url,
                        reason: String(statusCode),
                        cookie: cookie,
                        headers: headers
                    )
                }
                return try? await session.handle(event: event)
            }

            if command.isFeed {
                do {
                    let feed = try RSSFeedClient.parse(data)
                    guard let eventID = command.eventID else { return nil }
                    let records = feed.items.map { item in
                        [
                            item.title,
                            item.link,
                            RSSFeedClient.sspTimestamp(item.published),
                            item.author,
                            item.summary
                        ].joined(separator: "\u{1}")
                    }
                    return try await session.handle(event: SHIORIEventFactory.executeRSSComplete(
                        eventID: eventID,
                        records: records
                    ))
                } catch {
                    guard let eventID = command.eventID else { return nil }
                    return try? await session.handle(event: SHIORIEventFactory.executeRSSFailure(
                        eventID: eventID,
                        method: command.method,
                        url: command.url,
                        reason: "parse",
                        cookie: cookie,
                        headers: headers
                    ))
                }
            }

            let result: String
            switch command.output {
            case let .file(requestedName):
                let masterDirectory = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
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
            return try await session.handle(event: SHIORIEventFactory.executeHTTPComplete(
                eventID: eventID,
                method: command.method,
                url: command.url,
                result: result,
                statusCode: String(statusCode),
                cookie: cookie,
                headers: headers
            ))
        } catch {
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorTimedOut
            {
                let timeout = min(max(command.timeoutSeconds ?? 60, 0.1), 300)
                send(.shiori(id: "OnNetworkHeavy", references: [
                    0: String(timeout), 1: String(timeout)
                ]))
            }
            guard let eventID = command.eventID else { return nil }
            let reason = Self.httpFailureReason(error)
            let event = if command.isFeed {
                SHIORIEventFactory.executeRSSFailure(
                    eventID: eventID,
                    method: command.method,
                    url: command.url,
                    reason: reason
                )
            } else {
                SHIORIEventFactory.executeHTTPFailure(
                    eventID: eventID,
                    method: command.method,
                    url: command.url,
                    reason: reason
                )
            }
            return try? await session.handle(event: event)
        }
    }

    private static func httpResponseHeaders(_ response: HTTPURLResponse?) -> String {
        response?.allHeaderFields
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\u{1}") ?? ""
    }

    private static func httpFailureReason(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return "fileio"
        }
        guard error.domain == NSURLErrorDomain else {
            return String(error.code)
        }
        return switch URLError.Code(rawValue: error.code) {
        case .timedOut: "timeout"
        case .cancelled: "artificial"
        case .httpTooManyRedirects: "toomanyredirect"
        default: String(error.code)
        }
    }

    private func handleArchive(_ command: SakuraScriptArchiveCommand) async -> SakuraScript? {
        let runner = ArchiveOperationRunner()
        let masterDirectory = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)

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
                return try await session.handle(event: SHIORIEventFactory.extractArchiveComplete(
                    eventID: eventID,
                    fileCount: result.fileCount,
                    compressedBytes: result.compressedBytes,
                    uncompressedBytes: result.uncompressedBytes
                ))
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                return try? await session.handle(event: SHIORIEventFactory.extractArchiveFailure(
                    eventID: eventID,
                    reason: error.errorCode
                ))
            } catch {
                guard let eventID else { return nil }
                return try? await session.handle(event: SHIORIEventFactory.extractArchiveFailure(
                    eventID: eventID,
                    reason: "open failed"
                ))
            }
        case let .compress(archivePath, sourceDirectoryPath, eventID, password):
            let archiveURL = resolvePath(archivePath)
            let sourceURL = resolvePath(sourceDirectoryPath)
            do {
                let result = try runner.compress(destinationArchiveURL: archiveURL, sourceDirectoryURL: sourceURL, password: password)
                guard let eventID else { return nil }
                return try await session.handle(event: SHIORIEventFactory.compressArchiveComplete(
                    eventID: eventID,
                    fileCount: result.fileCount,
                    compressedBytes: result.compressedBytes,
                    uncompressedBytes: result.uncompressedBytes
                ))
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                return try? await session.handle(event: SHIORIEventFactory.compressArchiveFailure(
                    eventID: eventID,
                    reason: error.errorCode
                ))
            } catch {
                guard let eventID else { return nil }
                return try? await session.handle(event: SHIORIEventFactory.compressArchiveFailure(
                    eventID: eventID,
                    reason: "open failed"
                ))
            }
        case let .createNar(narPath, sourceDirectoryPath, eventID):
            let archiveURL = resolvePath(narPath)
            let sourceURL = resolvePath(sourceDirectoryPath)
            do {
                let references = narCreationEventReferences(sourceURL: sourceURL, archiveURL: archiveURL)
                _ = try? await session.handle(event: .shiori(id: "OnNarCreating", references: references))
                let result = try runner.compress(destinationArchiveURL: archiveURL, sourceDirectoryURL: sourceURL)
                let standardResponse = try? await session.handle(event: .shiori(
                    id: "OnNarCreated",
                    references: references
                ))
                guard let eventID else { return standardResponse }
                let id = eventID.hasPrefix("On") ? eventID : "OnCreateNarComplete"
                return try await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ])) ?? standardResponse
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCreateNarFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: error.errorCode
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCreateNarFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
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
                guard let image = surfaceController.renderedImage(for: 0),
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
                return try await session.handle(event: .shiori(id: id, references: [
                    0: destinationURL.path
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnDumpSurfaceFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
                    0: destinationURL.path
                ]))
            }
        case let .createUpdateData(directoryPath, eventID):
            let targetURL = directoryPath.map(resolvePath) ?? ghost.rootDirectory
            do {
                _ = try? await session.handle(event: .shiori(id: "OnUpdatedataCreating", references: [:]))
                let generator = UpdateDataGenerator()
                let result = try generator.generate(in: targetURL)
                let standardResponse = try? await session.handle(event: .shiori(
                    id: "OnUpdatedataCreated",
                    references: [:]
                ))
                guard let eventID else { return standardResponse }
                let id = eventID.hasPrefix("On") ? eventID : "OnCreateUpdateDataComplete"
                return try await session.handle(event: .shiori(id: id, references: [
                    0: String(result.fileCount),
                    1: targetURL.path
                ])) ?? standardResponse
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCreateUpdateDataFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
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

    private func cancelHTTP(url: String?) {
        if let url {
            inFlightHTTPTasks.removeValue(forKey: url)?.cancel()
        } else {
            inFlightHTTPTasks.values.forEach { $0.cancel() }
            inFlightHTTPTasks.removeAll()
        }
    }

    private func handleNetworkDiagnostic(_ command: SakuraScriptNetworkDiagnostic) async -> SakuraScript? {
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
            return try? await session.handle(event: SHIORIEventFactory.nsLookup(
                id: id,
                eventLabel: eventID,
                host: host,
                reverse: reverse,
                result: result.succeeded && !value.isEmpty ? value : nil
            ))
        }
    }

    private func sendAnchorSelection(label: String, id: String, arguments: [String]) {
        Task {
            do {
                let extended = try await session.response(for: SHIORIEventFactory.anchorSelectExtended(
                    label: label,
                    id: id,
                    arguments: arguments
                ))
                if let extended {
                    forwardCommunication(extended)
                    if let script = extended.script, !script.rawValue.isEmpty {
                        player.interrupt(with: script, balloon: balloon)
                        return
                    }
                }

                guard let legacy = try await session.response(for: SHIORIEventFactory.anchorSelect(id: id)) else {
                    return
                }
                if let script = legacy.script, !script.rawValue.isEmpty {
                    player.interrupt(with: script, balloon: balloon)
                }
                forwardCommunication(legacy)
            } catch {
                AppLogStore.shared.error(
                    "アンカー選択イベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Anchor: \(id)\nError: \(error)",
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    private func sendChoiceSelection(label: String, id: String, arguments: [String]) {
        if let url = URL(string: id), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }
        Task {
            do {
                let extended = try await session.response(for: SHIORIEventFactory.choiceSelectExtended(
                    label: label,
                    id: id,
                    arguments: arguments
                ))
                if let extended {
                    forwardCommunication(extended)
                    if let script = extended.script, !script.rawValue.isEmpty {
                        player.play(script, balloon: balloon)
                        return
                    }
                }

                guard let legacy = try await session.response(for: SHIORIEventFactory.choiceSelect(
                    id: id,
                    arguments: arguments
                )) else { return }
                if let script = legacy.script, !script.rawValue.isEmpty {
                    player.play(script, balloon: balloon)
                }
                forwardCommunication(legacy)
            } catch {
                AppLogStore.shared.error(
                    "選択肢イベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Choice: \(id)\nError: \(error)",
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    private func textInputAppearance(style: BalloonInputStyle) -> TextInputWindowController.Appearance {
        let loader = BalloonLoader()
        let effective = loader.effectiveInputDefinition(for: balloon, style: style)
        return TextInputWindowController.Appearance(
            balloon: effective,
            backgroundImageURL: loader.inputImageURL(style: style, in: balloon)
        )
    }

    private func handleWebSocket(_ command: SakuraScriptWebSocketCommand) async {
        switch command {
        case let .connect(url, eventID, headerLines, protocolName):
            await webSocketManager.connect(
                url: url,
                eventID: eventID,
                headers: Self.webSocketHeaders(headerLines),
                protocolName: protocolName
            ) { [weak self] event in
                await self?.handleWebSocketEvent(event)
            }
        case let .sendText(url, value): await webSocketManager.sendText(url: url, value: value)
        case let .sendBinary(url, value): await webSocketManager.sendBinary(url: url, value: value)
        case let .close(url, code): await webSocketManager.close(url: url, code: code)
        case let .cancel(url): await webSocketManager.cancel(url: url)
        }
    }

    private func handleWebSocketEvent(_ event: WebSocketSessionEvent) async {
        let payload = event.shioriEvent
        guard let response = try? await session.handle(event: .shiori(id: payload.id, references: payload.references)),
              !response.rawValue.isEmpty
        else { return }
        player.play(response, balloon: balloon)
    }

    private static func webSocketHeaders(_ lines: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            let fields = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return nil }
            return (fields[0], fields[1].trimmingCharacters(in: .whitespaces))
        })
    }

    private func fetchWeatherAndPlay(eventID: String) async {
        let script = await handleWeatherGet(eventID: eventID)
        player.play(script, balloon: balloon)
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
        if let response = try? await session.handle(event: .shiori(id: eventID, references: references)),
           !response.rawValue.isEmpty
        {
            return response
        }
        return SakuraScript(rawValue: "\\0\\s[6]\(fallback)\\e")
    }

    private func forwardCommunication(_ response: PersonalityResponse) {
        guard let target = response.references[0], !target.isEmpty,
              let sentence = response.references[1], !sentence.isEmpty else { return }
        onCommunication?(target, sentence)
    }
}

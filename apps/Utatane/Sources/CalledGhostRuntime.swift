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
    private let textInputWindowController = TextInputWindowController()
    private let systemDialogController = SystemDialogController()
    private var weatherTask: Task<Void, Never>?
    private var sntpCoordinator: SNTPEventCoordinator?
    private var inFlightHTTPTasks: [String: Task<Void, Never>] = [:]
    private var teachHistory: [String] = []
    private var pendingHourTimeSignal = false
    private(set) var shell: InstalledShell
    private(set) var balloon: BalloonDefinition

    var contextMenuItems: (() -> [SurfaceContextMenuItem])? {
        didSet { surfaceController.contextMenuItems = { [weak self] in self?.contextMenuItems?() ?? [] } }
    }

    var onError: ((Error) -> Void)?
    var onCommunication: ((String, String) -> Void)?
    var onNarDrop: (([URL]) -> Void)?
    var onContentAction: ((SakuraScriptContentAction) -> Void)?
    var onOtherEvent: ((String, String, [String], Bool) async -> Void)?
    var onOtherGhostTalk: ((String, String) -> Void)?
    var onOtherSurfaceChange: ((String, Int, Int) -> Void)?
    var onSurfaceChanged: ((Int, Int?, Int) -> Void)?

    init(
        ghost: InstalledGhost,
        balloons: [BalloonDefinition],
        shellLoader: ShellLoader,
        selectionStore: ContentSelectionStore,
        defaultBalloonDirectoryName: String?,
        personalityEngine: any PersonalityEngine,
        characterDelayMilliseconds: Int,
        dialogueDismissalMilliseconds: Int
    ) throws {
        self.ghost = ghost
        self.shellLoader = shellLoader
        self.selectionStore = selectionStore
        propertySystem = PropertySystem(configuration: .init(
            basewareName: "Utatane",
            basewareVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            values: Self.propertyValues(for: ghost).merging(MacOSPropertySnapshot.values()) { current, _ in current }
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
        surfaceController = SurfaceWindowController(positionStore: positionStore)
        balloonController = BalloonWindowController(positionStore: positionStore)
        player = SakuraScriptPlayer(
            surfaceWindowController: surfaceController,
            balloonWindowController: balloonController
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
        player.configure(resourceBaseDirectory: ghost.rootDirectory.appending(
            path: "ghost/master",
            directoryHint: .isDirectory
        ))
        let mainName = ghost.characters.first(where: { $0.scope == 0 })?.name ?? ghost.name
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

    func start(caller: InstalledGhost) async throws -> String? {
        try show(shell: shell)
        surfaceController.setPresentationHidden(true)
        _ = try? await session.start(event: .shiori(id: "OnInitialize", references: [:]))
        if let definition = try? shellLoader.load(from: shell.directory) {
            for event in startupInformationEvents(
                ghost: ghost,
                shell: shell,
                balloon: balloon,
                shellDefinition: definition
            ) {
                _ = try? await session.handle(event: .shiori(id: event.id, references: event.references))
            }
        }
        let script = try await session.handle(event: .shiori(id: "OnGhostCalled", references: [
            0: caller.characters.first(where: { $0.scope == 0 })?.name ?? caller.name,
            1: "",
            2: caller.name,
            3: caller.rootDirectory.path,
            7: shell.name
        ]))
        surfaceController.setPresentationHidden(false)
        if let script {
            player.play(script, balloon: balloon)
        }
        return script?.rawValue
    }

    func send(_ event: GhostEvent) {
        Task {
            do {
                guard let response = try await session.response(for: event) else { return }
                if let script = response.script {
                    player.play(script, balloon: balloon)
                }
                forwardCommunication(response)
            } catch {
                AppLogStore.shared.error(
                    "SHIORIイベント処理エラー: \(error.localizedDescription)",
                    category: "SHIORI",
                    details: "Event: \(event)\nError: \(error)",
                    ghostName: ghost.name
                )
                onError?(error)
            }
        }
    }

    func sendMusicTrack(_ track: NowPlayingTrack) {
        Task {
            do {
                let extended = try await session.response(for: .shiori(
                    id: "OnMusicPlayEx",
                    references: track.sspExtendedReferences
                ))
                if let extended {
                    forwardCommunication(extended)
                    if let script = extended.script, !script.rawValue.isEmpty {
                        player.play(script, balloon: balloon)
                        return
                    }
                }
                guard let legacy = try await session.response(for: .shiori(
                    id: "OnMusicPlay",
                    references: [0: track.title, 1: track.artist]
                )) else { return }
                if let script = legacy.script, !script.rawValue.isEmpty {
                    player.play(script, balloon: balloon)
                }
                forwardCommunication(legacy)
            } catch {
                AppLogStore.shared.error(
                    "音楽再生イベント処理エラー: \(error.localizedDescription)",
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
        Task {
            do {
                guard let response = try await session.response(for: .shiori(
                    id: "OnSecondChange",
                    references: references
                )) else { return }
                guard canTalk else { return }
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

    func stop() async -> String {
        await webSocketManager.cancelAll()
        cancelHTTP(url: nil)
        var finalScript = ""
        _ = try? await session.handle(event: .shiori(id: "OnDestroy", references: [:]))
        if let script = try? await session.stop(reason: .close) {
            finalScript = script.rawValue
            await player.playAndWait(script, balloon: balloon)
        }
        player.cancel()
        surfaceController.hideAll()
        balloonController.hideAll()
        return finalScript
    }

    func select(shell newShell: InstalledShell) {
        do {
            let previousShell = shell
            send(.shiori(id: "OnShellChanging", references: [
                0: newShell.name,
                1: previousShell.name,
                2: newShell.directory.path
            ]))
            try show(shell: newShell)
            send(.shiori(id: "OnShellChanged", references: [
                0: newShell.name,
                1: ghost.name,
                2: newShell.directory.path
            ]))
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
        send(.shiori(id: "OnBalloonChange", references: [
            0: newBalloon.name,
            1: newBalloon.directory.lastPathComponent
        ]))
    }

    func configurePlayback(characterDelayMilliseconds: Int, dismissalMilliseconds: Int) {
        player.configurePlayback(
            characterDelayMilliseconds: characterDelayMilliseconds,
            postDialogueDismissalMilliseconds: dismissalMilliseconds
        )
    }

    func configureDisplay(
        shellPercent: Int,
        automaticallyFitsLargeSurfaces: Bool,
        balloonPercent: Int,
        textPercent: Int
    ) {
        surfaceController.setDisplayScale(Double(shellPercent) / 100)
        surfaceController.setAutomaticallyFitsLargeSurfaces(automaticallyFitsLargeSurfaces)
        balloonController.setDisplayScale(Double(balloonPercent) / 100, textScale: Double(textPercent) / 100)
    }

    func resetWindowPositions() {
        send(.shiori(id: "OnResetWindowPos", references: [:]))
        surfaceController.resetWindowPositions()
        balloonController.resetWindowPositions()
    }

    private func show(shell newShell: InstalledShell) throws {
        player.cancel()
        let definition = try shellLoader.load(from: newShell.directory)
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
            send(.mouse(event))
        }
        surfaceController.onSurfaceChange = { [weak self] scope, previous, current in
            guard let self else { return }
            send(.shiori(id: "OnSurfaceChange", references: currentSurfaceReferences()))
            onSurfaceChanged?(scope, previous, current)
        }
        surfaceController.onNarDrop = { [weak self] _, urls in self?.onNarDrop?(urls) }
        surfaceController.onFileDropping = { [weak self] scope, urls in
            guard let first = urls.first else { return }
            self?.send(.shiori(id: "OnFileDropping", references: [0: first.path, 1: String(scope)]))
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
            self?.send(.shiori(id: "OnTextDrop", references: [
                0: value.replacingOccurrences(of: "\n", with: "\u{1}"), 1: String(scope)
            ]))
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
        player.onDialogueContent = { [weak self] in self?.surfaceController.setPresentationHidden(false) }
        player.onPlaybackFinished = { [weak self] in self?.surfaceController.setPresentationHidden(false) }
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
        player.onChoiceSelectEx = { [weak self] label, id, arguments in
            self?.send(.shiori(id: "OnChoiceSelectEx", references: Dictionary(
                uniqueKeysWithValues: ([label, id] + arguments).enumerated().map { ($0.offset, $0.element) }
            )))
        }
        player.onAnchorSelectEx = { [weak self] label, id, arguments in
            self?.send(.shiori(id: "OnAnchorSelectEx", references: Dictionary(
                uniqueKeysWithValues: ([label, id] + arguments).enumerated().map { ($0.offset, $0.element) }
            )))
        }
        player.onAnchorSelect = { [weak self] id in
            self?.send(.shiori(id: "OnAnchorSelect", references: [0: id]))
        }
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
        player.onSoundError = { [weak self] file, error in
            let nsError = error as NSError
            self?.send(.shiori(id: "OnSoundError", references: [
                0: "play", 1: String(nsError.code), 2: file, 3: error.localizedDescription
            ]))
        }
        player.onChoiceTimeout = { [weak self] script in
            self?.send(.shiori(id: "OnChoiceTimeout", references: [0: script]))
        }
        player.onOpen = { target in
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
            await propertySystem.register(values: MacOSPropertySnapshot.values())
            return try? await propertySystem.value(for: property)
        }
        player.onGetProperties = { [weak self] eventID, properties in
            guard let self else { return nil }
            await propertySystem.register(values: MacOSPropertySnapshot.values())
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
        player.onInputBox = { [weak self] id, _, initialValue in
            guard let self else { return nil }
            guard let value = await textInputWindowController.showPrompt(
                id: id,
                title: String(localized: "文字を入力"),
                initialValue: initialValue,
                actionTitle: String(localized: "OK")
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
            guard let value = await textInputWindowController.showPrompt(
                title: String(localized: "文字を入力"),
                initialValue: initialValue,
                actionTitle: String(localized: "OK")
            ) else {
                return try? await session.handle(event: .shiori(
                    id: "OnCommunicateInputCancel",
                    references: [0: "", 1: "cancel"]
                ))
            }
            return try? await session.handle(event: .shiori(
                id: "OnCommunicate",
                references: [0: "user", 1: value]
            ))
        }
        player.onTeachBox = { [weak self] initialValue in
            guard let self else { return nil }
            _ = try? await session.handle(event: .shiori(id: "OnTeachStart", references: [:]))
            guard let value = await textInputWindowController.showPrompt(
                title: String(localized: "文字を入力"),
                initialValue: initialValue,
                actionTitle: String(localized: "OK")
            ) else {
                return try? await session.handle(event: .shiori(
                    id: "OnTeachInputCancel",
                    references: [0: "", 1: "cancel"]
                ))
            }
            teachHistory.append(value)
            return try? await session.handle(event: .shiori(
                id: "OnTeach",
                references: Dictionary(uniqueKeysWithValues: teachHistory.enumerated().map {
                    ($0.offset, $0.element)
                })
            ))
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
        let joinedReferences = [
            0: urls.map(\.path).joined(separator: "\u{1}"),
            1: String(scope),
            2: urls.map(droppedFileMIMEType).joined(separator: "\u{1}")
        ]
        for url in urls where url.hasDirectoryPath {
            send(.shiori(id: "OnDirectoryDrop", references: [0: url.path, 1: String(scope)]))
        }
        Task {
            do {
                let response = try await session.response(for: .shiori(
                    id: "OnFileDrop2",
                    references: joinedReferences
                ))
                if let script = response?.script {
                    player.play(script, balloon: balloon)
                    if let response {
                        forwardCommunication(response)
                    }
                    return
                }
                guard let url = urls.first,
                      url.pathExtension.caseInsensitiveCompare("nar") != .orderedSame,
                      let viewerEventID = droppedFileViewerEventID(url),
                      NSWorkspace.shared.open(url)
                else { return }
                send(.shiori(id: viewerEventID, references: joinedReferences))
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
            2: droppedFileMIMEType(url),
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
                    return try await session.handle(event: .shiori(id: successID, references: references))
                } catch {
                    guard let eventID = command.eventID else { return nil }
                    let failureID = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExecuteRSSFailure"
                    return try? await session.handle(event: .shiori(id: failureID, references: [
                        0: command.url,
                        4: "parse"
                    ]))
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
            let successID = eventID.hasPrefix("On") ? eventID : "OnExecuteHTTPComplete"
            return try await session.handle(event: .shiori(id: successID, references: [
                0: command.method,
                1: eventID,
                2: command.url,
                3: result,
                4: String(statusCode),
                5: httpResponse?.value(forHTTPHeaderField: "Set-Cookie") ?? "",
                6: Self.httpResponseHeaders(httpResponse)
            ]))
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
            let failureID = eventID.hasPrefix("On") ? "\(eventID)Failure" : (command.isFeed ? "OnExecuteRSSFailure" : "OnExecuteHTTPFailure")
            return try? await session.handle(event: .shiori(id: failureID, references: [
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
                let id = eventID.hasPrefix("On") ? eventID : "OnExtractArchiveComplete"
                return try await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ]))
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExtractArchiveFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: error.errorCode
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnExtractArchiveFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
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
                return try await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ]))
            } catch let error as ArchiveOperationError {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCompressArchiveFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: error.errorCode
                ]))
            } catch {
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? "\(eventID)Failure" : "OnCompressArchiveFailure"
                return try? await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: "open failed"
                ]))
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

import AppKit
import UtataneBalloon
import UtataneCore
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
    private var weatherTask: Task<Void, Never>?
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
            variableStore: GhostVariableStore(fileURL: ContentRoot.variableStoreURL(for: ghost))
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
    }

    func start(caller: InstalledGhost) async throws -> String? {
        try show(shell: shell)
        surfaceController.setPresentationHidden(true)
        let script = try await session.start(event: .shiori(id: "OnGhostCalled", references: [
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
                onError?(error)
            }
        }
    }

    func sendSecondChange(references: [Int: String]) {
        let canTalk = !player.isDialogueActive
        var references = references
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
                onError?(error)
            }
        }
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

    func stop() async {
        if let script = try? await session.stop(reason: .close) {
            await player.playAndWait(script, balloon: balloon)
        }
        player.cancel()
        surfaceController.hideAll()
        balloonController.hideAll()
    }

    func select(shell newShell: InstalledShell) {
        do {
            try show(shell: newShell)
            send(.shiori(id: "OnShellChanged", references: [
                0: newShell.name,
                1: newShell.directory.lastPathComponent
            ]))
        } catch {
            onError?(error)
        }
    }

    func select(balloon newBalloon: BalloonDefinition) {
        player.cancel()
        balloon = newBalloon
        selectionStore.setBalloonDirectoryName(newBalloon.directory.lastPathComponent, for: ghost.id)
    }

    func configurePlayback(characterDelayMilliseconds: Int, dismissalMilliseconds: Int) {
        player.configurePlayback(
            characterDelayMilliseconds: characterDelayMilliseconds,
            postDialogueDismissalMilliseconds: dismissalMilliseconds
        )
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

    private func configureCallbacks() {
        surfaceController.onMouseEvent = { [weak self] event in
            guard let self, !player.isTimeCritical else { return }
            send(.mouse(event))
        }
        surfaceController.onNarDrop = { [weak self] _, urls in self?.onNarDrop?(urls) }
        player.onError = { [weak self] error in self?.onError?(error) }
        player.onDialogueContent = { [weak self] in self?.surfaceController.setPresentationHidden(false) }
        player.onPlaybackFinished = { [weak self] in self?.surfaceController.setPresentationHidden(false) }
        player.onDialogueDismissed = { [weak self] in
            self?.send(.shiori(id: "OnSurfaceRestore", references: [:]))
        }
        player.onChoice = { [weak self] id, arguments in
            if let url = URL(string: id), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                NSWorkspace.shared.open(url)
            } else {
                self?.send(.choice(id: id, arguments: arguments))
            }
        }
        player.onChoiceTimeout = { [weak self] in
            self?.send(.shiori(id: "OnChoiceTimeout", references: [:]))
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
        player.onInputBox = { [weak self] id, _, initialValue in
            guard let self, let value = promptForText(initialValue: initialValue) else { return nil }
            return try? await session.handle(event: .shiori(id: id, references: [0: value]))
        }
        player.onHTTPGet = { [weak self] url, eventID in
            guard let self else { return nil }
            return await handleHTTPGet(url: url, eventID: eventID)
        }
        player.onWeatherGet = { [weak self] eventID in
            guard let self else { return nil }
            weatherTask?.cancel()
            weatherTask = Task { [weak self] in
                await self?.fetchWeatherAndPlay(eventID: eventID)
            }
            return nil
        }
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
        guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return try? await session.handle(event: .shiori(id: eventID, references: [:]))
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "utatane-http-get-\(UUID().uuidString)", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(statusCode) else { throw URLError(.badServerResponse) }
            try data.write(to: temporaryURL, options: .atomic)
            return try await session.handle(event: .shiori(id: eventID, references: [
                0: source,
                1: String(statusCode),
                2: response.mimeType ?? "",
                3: temporaryURL.path
            ]))
        } catch {
            return try? await session.handle(event: .shiori(id: eventID, references: [:]))
        }
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

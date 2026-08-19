import AppKit
import UtataneBalloon
import UtataneCore
import UtatanePlatformMacOS
import UtataneRuntime
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
    private(set) var shell: InstalledShell
    private(set) var balloon: BalloonDefinition

    var contextMenuItems: (() -> [SurfaceContextMenuItem])? {
        didSet { surfaceController.contextMenuItems = { [weak self] in self?.contextMenuItems?() ?? [] } }
    }

    var onError: ((Error) -> Void)?
    var onCommunication: ((String, String) -> Void)?
    var onNarDrop: (([URL]) -> Void)?

    init(
        ghost: InstalledGhost,
        balloons: [BalloonDefinition],
        shellLoader: ShellLoader,
        selectionStore: ContentSelectionStore,
        personalityEngine: any PersonalityEngine,
        characterDelayMilliseconds: Int,
        dialogueDismissalMilliseconds: Int
    ) throws {
        self.ghost = ghost
        self.shellLoader = shellLoader
        self.selectionStore = selectionStore

        guard let selectedShell = ghost.shells.first(where: {
            $0.directory.lastPathComponent == selectionStore.shellDirectoryName(for: ghost.id)
        }) ?? ghost.shells.first(where: { $0.directory == ghost.defaultShellDirectory }) ?? ghost.shells.first else {
            throw AppError.missingResource("shell")
        }
        guard let selectedBalloon = balloons.first(where: {
            $0.directory.lastPathComponent == selectionStore.balloonDirectoryName(for: ghost.id)
        }) ?? balloons.first else {
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
        surfaceController.onMouseEvent = { [weak self] event in self?.send(.mouse(event)) }
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
        player.onEmbeddedEvent = { [weak self] id, arguments in
            guard let self else { return nil }
            return try? await session.handle(event: .shiori(
                id: id,
                references: Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                    ($0.offset, $0.element)
                })
            ))
        }
    }

    private func forwardCommunication(_ response: PersonalityResponse) {
        guard let target = response.references[0], !target.isEmpty,
              let sentence = response.references[1], !sentence.isEmpty else { return }
        onCommunication?(target, sentence)
    }
}

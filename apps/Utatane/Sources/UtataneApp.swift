import SwiftUI
import UtataneBalloon
import UtataneCore
import UtataneGhostKit
import UtatanePlatformMacOS
import UtataneRuntime
import UtataneSakuraScript
import UtataneShell

@main
struct UtataneApp: App {
    private let model: GhostListModel
    private let shellLoader: ShellLoader
    private let surfaceWindowController: SurfaceWindowController
    private let balloonLoader: BalloonLoader
    private let scriptPlayer: SakuraScriptPlayer

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
        balloonLoader = BalloonLoader()
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
                balloonLoader: balloonLoader,
                scriptPlayer: scriptPlayer
            )
        }
    }
}

private struct UtataneRootView: View {
    let model: GhostListModel
    let shellLoader: ShellLoader
    let surfaceWindowController: SurfaceWindowController
    let balloonLoader: BalloonLoader
    let scriptPlayer: SakuraScriptPlayer

    @State private var previewError: String?
    @State private var lastClickedRegion: String?
    @State private var balloon: BalloonDefinition?
    @State private var session: GhostSession?
    @State private var selectedGhostID: URL?

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
            }
            .padding(12)
        }
        .task {
            await model.load()
            selectedGhostID = selectedGhostID ?? model.ghosts.first?.id
        }
        .task(id: selectedGhostID) {
            guard let selectedGhostID,
                  let ghost = model.ghosts.first(where: { $0.id == selectedGhostID })
            else { return }
            await activate(ghost)
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
        .onDisappear {
            scriptPlayer.cancel()
            guard let session else { return }
            Task {
                _ = try? await session.stop()
            }
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

    private func activate(_ ghost: InstalledGhost) async {
        if let session {
            _ = try? await session.stop()
        }
        scriptPlayer.cancel()
        surfaceWindowController.hideAll()
        session = nil
        balloon = nil

        do {
            let shell = try shellLoader.load(from: ghost.defaultShellDirectory)
            surfaceWindowController.onMouseClick = { scope, region in
                lastClickedRegion = "scope \(scope): \(region ?? "範囲外")"
                sendEvent(.mouseClick(region: region))
            }
            try surfaceWindowController.show(shell: shell, scope: 0, surfaceID: 0)
            try? surfaceWindowController.show(shell: shell, scope: 1, surfaceID: 10)

            let loadedBalloon = try balloonLoader.loadInstalled(
                from: ContentRoot.balloonsDirectory
            ).first
            balloon = loadedBalloon
            scriptPlayer.onError = { error in
                previewError = error.localizedDescription
            }
            scriptPlayer.onChoice = { id, arguments in
                sendEvent(.choice(id: id, arguments: arguments))
            }

            guard let dialogueURL = ContentRoot.dialogueURL(for: ghost) else {
                throw AppError.missingResource("default-dialogue.json")
            }
            let catalog = try DialogueCatalogLoader().load(from: dialogueURL)
            let ghostSession = GhostSession(
                personalityEngine: DialoguePersonalityEngine(catalog: catalog),
                variableStore: GhostVariableStore(fileURL: ContentRoot.variableStoreURL(for: ghost))
            )
            session = ghostSession
            if let script = try await ghostSession.start(), let loadedBalloon {
                scriptPlayer.play(script, balloon: loadedBalloon)
            }
        } catch {
            previewError = error.localizedDescription
        }
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

    private static var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

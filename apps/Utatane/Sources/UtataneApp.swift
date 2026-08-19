import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UtataneBalloon
import UtataneContent
import UtataneCore
import UtataneGhostKit
import UtatanePlatformMacOS
import UtataneRuntime
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
    private let balloonLoader: BalloonLoader
    private let scriptPlayer: SakuraScriptPlayer
    private let selectionStore: ContentSelectionStore

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
        selectionStore = ContentSelectionStore()
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
                scriptPlayer: scriptPlayer,
                selectionStore: selectionStore,
                applicationDelegate: applicationDelegate
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
    let selectionStore: ContentSelectionStore
    let applicationDelegate: UtataneApplicationDelegate

    @State private var previewError: String?
    @State private var lastClickedRegion: String?
    @State private var balloon: BalloonDefinition?
    @State private var session: GhostSession?
    @State private var selectedGhostID: URL?
    @State private var currentGhost: InstalledGhost?
    @State private var selectedShell: InstalledShell?
    @State private var installedBalloons: [BalloonDefinition] = []
    @State private var isImportingNar = false

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
            let restoredGhost = model.ghosts.first {
                $0.rootDirectory.lastPathComponent == selectionStore.ghostDirectoryName
            }
            selectedGhostID = selectedGhostID ?? restoredGhost?.id ?? model.ghosts.first?.id
        }
        .task(id: selectedGhostID) {
            guard let selectedGhostID,
                  let ghost = model.ghosts.first(where: { $0.id == selectedGhostID })
            else { return }
            await transition(to: ghost)
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
        .onDisappear {
            scriptPlayer.cancel()
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
        session = nil
        balloon = nil
        currentGhost = ghost
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
                sendEvent(.mouseClick(scope: scope, region: region))
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
            scriptPlayer.onChoice = { id, arguments in
                sendEvent(.choice(id: id, arguments: arguments))
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
                .separator,
                .action(title: "Utataneを終了", handler: { NSApplication.shared.terminate(nil) })
            ]
        }
    }

    private func installNar(from url: URL) {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        let roots = NarInstallationRoots(
            ghostsDirectory: ContentRoot.ghostsDirectory,
            balloonsDirectory: ContentRoot.balloonsDirectory
        )
        let selectedGhostDirectory = currentGhost?.rootDirectory
        Task {
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let result = try await Task.detached {
                    try NarInstaller().install(
                        archiveURL: url,
                        roots: roots,
                        selectedGhostDirectory: selectedGhostDirectory
                    )
                }.value
                await model.load()
                if result.primaryType == .ghost,
                   let installedGhostURL = result.installedURLs.first,
                   let installedGhost = model.ghosts.first(where: {
                       $0.rootDirectory.standardizedFileURL == installedGhostURL.standardizedFileURL
                   })
                {
                    selectedGhostID = installedGhost.id
                } else if let currentGhost = model.ghosts.first(where: {
                    $0.id.standardizedFileURL == selectedGhostID?.standardizedFileURL
                }) {
                    await transition(to: currentGhost, forceReload: true)
                }
            } catch {
                previewError = error.localizedDescription
            }
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

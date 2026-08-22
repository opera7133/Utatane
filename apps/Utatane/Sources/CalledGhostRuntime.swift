import AppKit
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
    var onOtherGhostTalk: ((String, String) -> Void)?
    var onOtherSurfaceChange: ((String, Int, Int) -> Void)?

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
        await webSocketManager.cancelAll()
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
        player.onHTTP = { [weak self] request in
            guard let self else { return nil }
            return await handleHTTP(request)
        }
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
            guard let self, let value = promptForText(initialValue: initialValue) else { return nil }
            return try? await session.handle(event: .shiori(id: "OnCommunicate", references: [0: value]))
        }
        player.onTeachBox = { [weak self] initialValue in
            guard let self, let value = promptForText(initialValue: initialValue) else { return nil }
            return try? await session.handle(event: .shiori(id: "OnTeach", references: [0: value]))
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
    }

    func play(_ script: SakuraScript) {
        player.play(script, balloon: balloon)
    }

    func changeSurface(to surfaceID: Int, scope: Int = 0) {
        try? surfaceController.changeSurface(scope: scope, to: surfaceID)
    }

    func updateEnvironmentVariables(_ variables: [String: String]) {
        player.updateEnvironmentVariables(variables)
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
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
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
                0: command.url,
                1: String(statusCode),
                2: response.mimeType ?? "",
                3: result
            ]))
        } catch {
            guard let eventID = command.eventID else { return nil }
            let failureID = eventID.hasPrefix("On") ? "\(eventID)Failure" : (command.isFeed ? "OnExecuteRSSFailure" : "OnExecuteHTTPFailure")
            return try? await session.handle(event: .shiori(id: failureID, references: [0: command.url]))
        }
    }

    private func handleArchive(_ command: SakuraScriptArchiveCommand) async -> SakuraScript? {
        let runner = ArchiveOperationRunner()
        let masterDirectory = ghost.rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)

        func resolvePath(_ path: String) -> URL {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return masterDirectory.appending(path: path)
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
                let result = try runner.compress(destinationArchiveURL: archiveURL, sourceDirectoryURL: sourceURL)
                guard let eventID else { return nil }
                let id = eventID.hasPrefix("On") ? eventID : "OnCreateNarComplete"
                return try await session.handle(event: .shiori(id: id, references: [
                    0: eventID,
                    1: String(result.fileCount),
                    2: String(result.compressedBytes),
                    3: String(result.uncompressedBytes)
                ]))
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

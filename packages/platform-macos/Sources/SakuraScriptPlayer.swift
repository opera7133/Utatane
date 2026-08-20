import Foundation
import UtataneBalloon
import UtataneSakuraScript

@MainActor
public final class SakuraScriptPlayer {
    private let parser = SakuraScriptParser()
    private let surfaceWindowController: SurfaceWindowController
    private let balloonWindowController: BalloonWindowController
    private var characterDelayMilliseconds = 50
    private var postDialogueDismissalMilliseconds: Int
    private var playbackTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var fastForwardRequested = false
    private var advanceRequested = false
    private var isWaitingForClick = false
    private var isPlaybackComplete = false
    private var defaultBalloonSurfaceIDs: [Int: Int] = [:]
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    public var onError: (@MainActor (Error) -> Void)?
    public var onChoice: (@MainActor (String, [String]) -> Void)?
    public var onEmbeddedEvent: (@MainActor (String, [String]) async -> SakuraScript?)?
    public var onInputBox: (@MainActor (String, Int?, String) async -> SakuraScript?)?
    public var onHTTPGet: (@MainActor (String, String) async -> SakuraScript?)?
    public var onWeatherGet: (@MainActor (String) async -> SakuraScript?)?
    public var onDialogueContent: (@MainActor () -> Void)?
    public var onDialogueDismissed: (@MainActor () -> Void)?
    public var onPlaybackFinished: (@MainActor () -> Void)?

    public var isDialogueActive: Bool {
        playbackTask != nil || isPlaybackComplete
    }

    public init(
        surfaceWindowController: SurfaceWindowController,
        balloonWindowController: BalloonWindowController,
        postDialogueDismissalMilliseconds: Int = 10000
    ) {
        self.surfaceWindowController = surfaceWindowController
        self.balloonWindowController = balloonWindowController
        self.postDialogueDismissalMilliseconds = postDialogueDismissalMilliseconds
        balloonWindowController.onClick = { [weak self] _ in
            self?.advance()
        }
        balloonWindowController.onLinkClick = { [weak self] id, arguments in
            self?.cancel()
            self?.onChoice?(id, arguments)
        }
    }

    public func play(
        _ script: SakuraScript,
        balloon: BalloonDefinition,
        characterDelayMilliseconds: Int? = nil
    ) {
        finishPlaybackWait()
        playbackTask?.cancel()
        dismissalTask?.cancel()
        fastForwardRequested = false
        advanceRequested = false
        isWaitingForClick = false
        isPlaybackComplete = false
        balloonWindowController.hideAll()
        balloonWindowController.setWaitingForClick(false)
        let tokens = parser.parse(script)
        let effectiveCharacterDelay = characterDelayMilliseconds ?? self.characterDelayMilliseconds
        playbackTask = Task { [weak self] in
            await self?.run(
                tokens,
                balloon: balloon,
                characterDelayMilliseconds: effectiveCharacterDelay
            )
            guard !Task.isCancelled else { return }
            self?.playbackDidFinish()
        }
    }

    public func playAndWait(
        _ script: SakuraScript,
        balloon: BalloonDefinition,
        characterDelayMilliseconds: Int? = nil
    ) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                play(
                    script,
                    balloon: balloon,
                    characterDelayMilliseconds: characterDelayMilliseconds
                )
                playbackContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    public func configure(defaultBalloonSurfaceIDs: [Int: Int]) {
        self.defaultBalloonSurfaceIDs = defaultBalloonSurfaceIDs
    }

    public func configurePlayback(
        characterDelayMilliseconds: Int,
        postDialogueDismissalMilliseconds: Int
    ) {
        self.characterDelayMilliseconds = max(0, characterDelayMilliseconds)
        self.postDialogueDismissalMilliseconds = max(0, postDialogueDismissalMilliseconds)
    }

    public func cancel() {
        playbackTask?.cancel()
        dismissalTask?.cancel()
        playbackTask = nil
        dismissalTask = nil
        fastForwardRequested = false
        advanceRequested = false
        isWaitingForClick = false
        isPlaybackComplete = false
        balloonWindowController.setWaitingForClick(false)
        balloonWindowController.hideAll()
        finishPlaybackWait()
    }

    public func advance() {
        if isPlaybackComplete {
            dismissCompletedDialogue()
            return
        }
        if isWaitingForClick {
            advanceRequested = true
        } else {
            fastForwardRequested = true
        }
    }

    private func run(
        _ tokens: [SakuraScriptToken],
        balloon: BalloonDefinition,
        characterDelayMilliseconds: Int
    ) async {
        var scope = 0
        var textByScope: [Int: String] = [:]
        var linksByScope: [Int: [BalloonTextLink]] = [:]
        var anchorsByScope: [Int: ActiveAnchor] = [:]
        var activatedScopes = Set<Int>()
        defer {
            isWaitingForClick = false
            balloonWindowController.setWaitingForClick(false)
        }

        do {
            var pendingTokens = tokens
            while !pendingTokens.isEmpty {
                guard !Task.isCancelled else { return }
                let token = pendingTokens.removeFirst()
                switch token {
                case let .text(text):
                    for character in text {
                        guard !Task.isCancelled else { return }
                        textByScope[scope, default: ""].append(character)
                        try activateIfNeeded(
                            scope: scope,
                            balloon: balloon,
                            text: textByScope[scope, default: ""],
                            links: linksByScope[scope, default: []],
                            activatedScopes: &activatedScopes
                        )
                        updateContent(
                            scope: scope,
                            text: textByScope[scope, default: ""],
                            links: linksByScope[scope, default: []]
                        )
                        if !fastForwardRequested {
                            try await sleep(milliseconds: characterDelayMilliseconds)
                        }
                    }
                    fastForwardRequested = false
                case let .scope(newScope):
                    scope = newScope
                case let .surface(surfaceID):
                    try surfaceWindowController.changeSurface(scope: scope, to: surfaceID)
                case let .namedSurface(identifier):
                    try surfaceWindowController.changeSurface(scope: scope, named: identifier)
                case .lineBreak:
                    textByScope[scope, default: ""].append("\n")
                    try activateIfNeeded(
                        scope: scope,
                        balloon: balloon,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        activatedScopes: &activatedScopes
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []]
                    )
                case let .wait(milliseconds):
                    if fastForwardRequested {
                        fastForwardRequested = false
                    } else {
                        try await sleep(milliseconds: milliseconds)
                    }
                case let .waitForClick(clearOnResume):
                    fastForwardRequested = false
                    advanceRequested = false
                    isWaitingForClick = true
                    balloonWindowController.setWaitingForClick(true, scope: scope)
                    while !advanceRequested {
                        try await sleep(milliseconds: 50)
                    }
                    advanceRequested = false
                    isWaitingForClick = false
                    balloonWindowController.setWaitingForClick(false, scope: scope)
                    scope = 0
                    if clearOnResume {
                        textByScope.removeAll()
                        linksByScope.removeAll()
                        anchorsByScope.removeAll()
                    }
                case let .choice(label, id, arguments):
                    let start = textByScope[scope, default: ""].utf16.count
                    textByScope[scope, default: ""].append(label)
                    linksByScope[scope, default: []].append(
                        BalloonTextLink(
                            range: NSRange(location: start, length: label.utf16.count),
                            id: id,
                            arguments: arguments
                        )
                    )
                    try activateIfNeeded(
                        scope: scope,
                        balloon: balloon,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        activatedScopes: &activatedScopes
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []]
                    )
                case let .anchorStart(id, arguments):
                    anchorsByScope[scope] = ActiveAnchor(
                        id: id,
                        arguments: arguments,
                        start: textByScope[scope, default: ""].utf16.count
                    )
                case .anchorEnd:
                    guard let anchor = anchorsByScope.removeValue(forKey: scope) else { continue }
                    let end = textByScope[scope, default: ""].utf16.count
                    guard end > anchor.start else { continue }
                    linksByScope[scope, default: []].append(
                        BalloonTextLink(
                            range: NSRange(location: anchor.start, length: end - anchor.start),
                            id: anchor.id,
                            arguments: anchor.arguments
                        )
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []]
                    )
                case let .embeddedEvent(id, arguments):
                    if let embeddedScript = await onEmbeddedEvent?(id, arguments) {
                        pendingTokens.insert(contentsOf: parser.parse(embeddedScript), at: 0)
                    }
                case let .inputBox(id, timeoutMilliseconds, initialValue):
                    if let response = await onInputBox?(id, timeoutMilliseconds, initialValue) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .httpGet(url, eventID):
                    if let response = await onHTTPGet?(url, eventID) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .weatherGet(eventID):
                    if let response = await onWeatherGet?(eventID) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case .clear:
                    textByScope[scope] = ""
                    linksByScope[scope] = []
                    anchorsByScope[scope] = nil
                    updateContent(scope: scope, text: "", links: [])
                case .end:
                    return
                case .unknown:
                    continue
                }
            }
        } catch is CancellationError {
            return
        } catch {
            onError?(error)
        }
    }

    private func activate(
        scope: Int,
        balloon: BalloonDefinition,
        text: String,
        links: [BalloonTextLink]
    ) throws {
        guard let surfaceFrame = surfaceWindowController.windowFrame(for: scope)
            ?? surfaceWindowController.windowFrame
        else { return }
        let speaker: BalloonSpeaker = switch scope {
        case 0: .sakura
        case 1: .kero
        default: .character(scope: scope)
        }
        try balloonWindowController.show(
            balloon: balloon,
            text: text,
            scope: scope,
            speaker: speaker,
            style: defaultBalloonSurfaceIDs[scope] ?? 0,
            near: surfaceFrame
        )
        updateContent(scope: scope, text: text, links: links)
    }

    private func activateIfNeeded(
        scope: Int,
        balloon: BalloonDefinition,
        text: String,
        links: [BalloonTextLink],
        activatedScopes: inout Set<Int>
    ) throws {
        guard text.contains(where: { !$0.isWhitespace }) else { return }
        guard activatedScopes.insert(scope).inserted else { return }
        onDialogueContent?()
        try activate(scope: scope, balloon: balloon, text: text, links: links)
    }

    private func updateContent(scope: Int, text: String, links: [BalloonTextLink]) {
        balloonWindowController.updateContent(text: text, links: links, scope: scope)
    }

    private func playbackDidFinish() {
        playbackTask = nil
        isPlaybackComplete = true
        isWaitingForClick = false
        balloonWindowController.setWaitingForClick(false)
        finishPlaybackWait()
        onPlaybackFinished?()
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await sleep(milliseconds: postDialogueDismissalMilliseconds)
            } catch {
                return
            }
            dismissCompletedDialogue()
        }
    }

    private func finishPlaybackWait() {
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    private func dismissCompletedDialogue() {
        dismissalTask?.cancel()
        dismissalTask = nil
        let hadVisibleDialogue = !balloonWindowController.visibleScopes.isEmpty
        balloonWindowController.hideAll()
        isPlaybackComplete = false
        if hadVisibleDialogue {
            onDialogueDismissed?()
        }
    }

    private func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private struct ActiveAnchor {
    let id: String
    let arguments: [String]
    let start: Int
}

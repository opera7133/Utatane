import Foundation
import UtataneBalloon
import UtataneSakuraScript

@MainActor
public final class SakuraScriptPlayer {
    private let parser = SakuraScriptParser()
    private let surfaceWindowController: SurfaceWindowController
    private let balloonWindowController: BalloonWindowController
    private let postDialogueDismissalMilliseconds: Int
    private var playbackTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var fastForwardRequested = false
    private var advanceRequested = false
    private var isWaitingForClick = false
    private var isPlaybackComplete = false

    public var onError: (@MainActor (Error) -> Void)?
    public var onChoice: (@MainActor (String, [String]) -> Void)?

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
            self?.onChoice?(id, arguments)
        }
    }

    public func play(
        _ script: SakuraScript,
        balloon: BalloonDefinition,
        characterDelayMilliseconds: Int = 50
    ) {
        playbackTask?.cancel()
        dismissalTask?.cancel()
        fastForwardRequested = false
        advanceRequested = false
        isWaitingForClick = false
        isPlaybackComplete = false
        balloonWindowController.hideAll()
        balloonWindowController.setWaitingForClick(false)
        let tokens = parser.parse(script)
        playbackTask = Task { [weak self] in
            await self?.run(
                tokens,
                balloon: balloon,
                characterDelayMilliseconds: characterDelayMilliseconds
            )
            guard !Task.isCancelled else { return }
            self?.playbackDidFinish()
        }
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
        surfaceWindowController.resetToDefaultSurfaces()
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
        defer {
            isWaitingForClick = false
            balloonWindowController.setWaitingForClick(false)
        }

        do {
            try activate(scope: scope, balloon: balloon, text: "", links: [])

            for token in tokens {
                guard !Task.isCancelled else { return }
                switch token {
                case let .text(text):
                    for character in text {
                        guard !Task.isCancelled else { return }
                        textByScope[scope, default: ""].append(character)
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
                    try activate(
                        scope: scope,
                        balloon: balloon,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []]
                    )
                case let .surface(surfaceID):
                    try surfaceWindowController.changeSurface(scope: scope, to: surfaceID)
                case let .namedSurface(identifier):
                    try surfaceWindowController.changeSurface(scope: scope, named: identifier)
                case .lineBreak:
                    textByScope[scope, default: ""].append("\n")
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
                    try activate(
                        scope: scope,
                        balloon: balloon,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []]
                    )
                case let .choice(label, id, arguments):
                    if let last = textByScope[scope]?.last, last != "\n" {
                        textByScope[scope, default: ""].append("\n")
                    }
                    let start = textByScope[scope, default: ""].utf16.count
                    textByScope[scope, default: ""].append(label)
                    linksByScope[scope, default: []].append(
                        BalloonTextLink(
                            range: NSRange(location: start, length: label.utf16.count),
                            id: id,
                            arguments: arguments
                        )
                    )
                    textByScope[scope, default: ""].append("\n")
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
        let speaker: BalloonSpeaker = scope == 1 ? .kero : .sakura
        try balloonWindowController.show(
            balloon: balloon,
            text: text,
            scope: scope,
            speaker: speaker,
            near: surfaceFrame
        )
        updateContent(scope: scope, text: text, links: links)
    }

    private func updateContent(scope: Int, text: String, links: [BalloonTextLink]) {
        balloonWindowController.updateContent(text: text, links: links, scope: scope)
    }

    private func playbackDidFinish() {
        playbackTask = nil
        isPlaybackComplete = true
        isWaitingForClick = false
        balloonWindowController.setWaitingForClick(false)
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

    private func dismissCompletedDialogue() {
        dismissalTask?.cancel()
        dismissalTask = nil
        balloonWindowController.hideAll()
        surfaceWindowController.resetToDefaultSurfaces()
        isPlaybackComplete = false
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

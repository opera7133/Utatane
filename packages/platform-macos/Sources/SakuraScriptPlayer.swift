import AppKit
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
    private let soundPlayer = SakuraScriptSoundPlayer()
    private var environmentVariables: [String: String] = [:]
    private var eventTimers: [String: Task<Void, Never>] = [:]

    public var onError: (@MainActor (Error) -> Void)?
    public var onChoice: (@MainActor (String, [String]) -> Void)?
    public var onEmbeddedEvent: (@MainActor (String, [String]) async -> SakuraScript?)?
    public var onInputBox: (@MainActor (String, Int?, String) async -> SakuraScript?)?
    public var onHTTPGet: (@MainActor (String, String) async -> SakuraScript?)?
    public var onWeatherGet: (@MainActor (String) async -> SakuraScript?)?
    public var onOpen: (@MainActor (String) -> Void)?
    public var onContentAction: (@MainActor (SakuraScriptContentAction) -> Void)?
    public var onOtherEvent: (@MainActor (String, String, [String], Bool) async -> Void)?
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

    public func configure(resourceBaseDirectory: URL) {
        soundPlayer.resourceBaseDirectory = resourceBaseDirectory
    }

    public func configure(environmentVariables: [String: String]) {
        eventTimers.values.forEach { $0.cancel() }
        eventTimers.removeAll()
        self.environmentVariables = Dictionary(uniqueKeysWithValues: environmentVariables.map {
            ($0.key.lowercased(), $0.value)
        })
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
        var choicesByScope: [Int: ActiveAnchor] = [:]
        var textStyleByScope: [Int: BalloonTextStyle] = [:]
        var styleRunsByScope: [Int: [BalloonTextStyleRun]] = [:]
        var balloonStyleByScope = defaultBalloonSurfaceIDs
        var activatedScopes = Set<Int>()
        var isQuickSection = false

        func appendStyleRun(scope: Int, location: Int, length: Int) {
            guard length > 0 else { return }
            let style = textStyleByScope[scope] ?? BalloonTextStyle()
            guard style != BalloonTextStyle() else { return }
            if let last = styleRunsByScope[scope]?.last,
               last.style == style,
               NSMaxRange(last.range) == location
            {
                var runs = styleRunsByScope[scope] ?? []
                runs[runs.count - 1] = BalloonTextStyleRun(
                    range: NSRange(location: last.range.location, length: last.range.length + length),
                    style: style
                )
                styleRunsByScope[scope] = runs
                return
            }
            let run = BalloonTextStyleRun(
                range: NSRange(location: location, length: length),
                style: style
            )
            styleRunsByScope[scope, default: []].append(run)
        }
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
                        let start = textByScope[scope, default: ""].utf16.count
                        textByScope[scope, default: ""].append(character)
                        appendStyleRun(scope: scope, location: start, length: character.utf16.count)
                        try activateIfNeeded(
                            scope: scope,
                            balloon: balloon,
                            text: textByScope[scope, default: ""],
                            links: linksByScope[scope, default: []],
                            style: balloonStyleByScope[scope] ?? 0,
                            activatedScopes: &activatedScopes
                        )
                        updateContent(
                            scope: scope,
                            text: textByScope[scope, default: ""],
                            links: linksByScope[scope, default: []],
                            styles: styleRunsByScope[scope, default: []]
                        )
                        if !fastForwardRequested, !isQuickSection {
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
                case let .balloonSurface(style):
                    balloonStyleByScope[scope] = style
                    if activatedScopes.contains(scope) {
                        try balloonWindowController.changeStyle(style, scope: scope)
                    }
                case .lineBreak:
                    textByScope[scope, default: ""].append("\n")
                    try activateIfNeeded(
                        scope: scope,
                        balloon: balloon,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        style: balloonStyleByScope[scope] ?? 0,
                        activatedScopes: &activatedScopes
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        styles: styleRunsByScope[scope, default: []]
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
                        choicesByScope.removeAll()
                        textStyleByScope.removeAll()
                        styleRunsByScope.removeAll()
                    }
                case let .choice(label, id, arguments):
                    let start = textByScope[scope, default: ""].utf16.count
                    textByScope[scope, default: ""].append(label)
                    appendStyleRun(scope: scope, location: start, length: label.utf16.count)
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
                        style: balloonStyleByScope[scope] ?? 0,
                        activatedScopes: &activatedScopes
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        styles: styleRunsByScope[scope, default: []]
                    )
                case let .choiceStart(id, arguments):
                    choicesByScope[scope] = ActiveAnchor(
                        id: id,
                        arguments: arguments,
                        start: textByScope[scope, default: ""].utf16.count
                    )
                case .choiceEnd:
                    guard let choice = choicesByScope.removeValue(forKey: scope) else { continue }
                    let end = textByScope[scope, default: ""].utf16.count
                    guard end > choice.start else { continue }
                    linksByScope[scope, default: []].append(
                        BalloonTextLink(
                            range: NSRange(location: choice.start, length: end - choice.start),
                            id: choice.id,
                            arguments: choice.arguments
                        )
                    )
                    textByScope[scope, default: ""].append("\n")
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        styles: styleRunsByScope[scope, default: []]
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
                            arguments: anchor.arguments,
                            kind: .anchor
                        )
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        styles: styleRunsByScope[scope, default: []]
                    )
                case .marker:
                    textByScope[scope, default: ""].append("\u{FFFC}")
                    try activateIfNeeded(
                        scope: scope,
                        balloon: balloon,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        style: balloonStyleByScope[scope] ?? 0,
                        activatedScopes: &activatedScopes
                    )
                    updateContent(
                        scope: scope,
                        text: textByScope[scope, default: ""],
                        links: linksByScope[scope, default: []],
                        styles: styleRunsByScope[scope, default: []]
                    )
                case let .environmentVariable(name):
                    pendingTokens.insert(.text(environmentValue(for: name)), at: 0)
                case let .font(name, arguments):
                    applyFontCommand(
                        name: name,
                        arguments: arguments,
                        style: &textStyleByScope[scope, default: BalloonTextStyle()],
                        defaultHeight: Double(balloon.fontHeight)
                    )
                case let .quickSection(enabled):
                    isQuickSection = enabled ?? !isQuickSection
                case let .open(target):
                    onOpen?(target)
                case let .sound(command):
                    try await soundPlayer.execute(command)
                case let .embeddedEvent(id, arguments):
                    if let embeddedScript = await onEmbeddedEvent?(id, arguments) {
                        pendingTokens.insert(contentsOf: parser.parse(embeddedScript), at: 0)
                    }
                case let .raisedEvent(id, arguments):
                    if let raisedScript = await onEmbeddedEvent?(id, arguments) {
                        pendingTokens = parser.parse(raisedScript)
                    } else {
                        return
                    }
                case let .notifyEvent(id, arguments):
                    _ = await onEmbeddedEvent?(id, arguments)
                case let .otherEvent(target, id, arguments, reflectsResponse):
                    await onOtherEvent?(target, id, arguments, reflectsResponse)
                case let .timerEvent(milliseconds, repeats, reflectsResponse, id, arguments):
                    scheduleEventTimer(
                        milliseconds: milliseconds,
                        repeats: repeats,
                        reflectsResponse: reflectsResponse,
                        id: id,
                        arguments: arguments,
                        balloon: balloon
                    )
                case let .contentAction(action):
                    onContentAction?(action)
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
                    styleRunsByScope[scope] = []
                    updateContent(scope: scope, text: "", links: [], styles: [])
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

    private func scheduleEventTimer(
        milliseconds: Int,
        repeats: Bool,
        reflectsResponse: Bool,
        id: String,
        arguments: [String],
        balloon: BalloonDefinition
    ) {
        eventTimers[id]?.cancel()
        eventTimers[id] = nil
        guard milliseconds > 0 else { return }
        eventTimers[id] = Task { [weak self] in
            repeat {
                do {
                    try await Task.sleep(for: .milliseconds(milliseconds))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                let response = await onEmbeddedEvent?(id, arguments)
                if reflectsResponse, let response {
                    play(response, balloon: balloon)
                }
            } while repeats && !Task.isCancelled
            self?.eventTimers[id] = nil
        }
    }

    private func environmentValue(for name: String) -> String {
        if let configured = environmentVariables[name] {
            return configured
        }
        let now = Date()
        let calendar = Calendar.current
        switch name {
        case "month": return String(calendar.component(.month, from: now))
        case "day": return String(calendar.component(.day, from: now))
        case "hour": return String(calendar.component(.hour, from: now))
        case "minute": return String(calendar.component(.minute, from: now))
        case "second": return String(calendar.component(.second, from: now))
        case "username": return NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        case "screenwidth": return String(Int((NSScreen.main ?? NSScreen.screens.first)?.frame.width ?? 0))
        case "screenheight": return String(Int((NSScreen.main ?? NSScreen.screens.first)?.frame.height ?? 0))
        case "exh": return String(Int(ProcessInfo.processInfo.systemUptime))
        default: return "%\(name)"
        }
    }

    private func activate(
        scope: Int,
        balloon: BalloonDefinition,
        text: String,
        links: [BalloonTextLink],
        style: Int
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
            style: style,
            near: surfaceFrame
        )
        updateContent(scope: scope, text: text, links: links)
    }

    private func activateIfNeeded(
        scope: Int,
        balloon: BalloonDefinition,
        text: String,
        links: [BalloonTextLink],
        style: Int,
        activatedScopes: inout Set<Int>
    ) throws {
        guard text.contains(where: { !$0.isWhitespace }) else { return }
        guard activatedScopes.insert(scope).inserted else { return }
        onDialogueContent?()
        try activate(scope: scope, balloon: balloon, text: text, links: links, style: style)
    }

    private func updateContent(
        scope: Int,
        text: String,
        links: [BalloonTextLink],
        styles: [BalloonTextStyleRun] = []
    ) {
        balloonWindowController.updateContent(text: text, links: links, styles: styles, scope: scope)
    }

    private func applyFontCommand(
        name: String,
        arguments: [String],
        style: inout BalloonTextStyle,
        defaultHeight: Double
    ) {
        let value = arguments.first?.lowercased() ?? ""
        switch name {
        case "default", "disable":
            style = BalloonTextStyle()
        case "name":
            style.fontName = value == "default" ? nil : arguments.first
        case "height":
            if value == "default" {
                style.fontHeight = nil
            } else if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
                style.fontHeight = max(1, defaultHeight * percent / 100)
            } else if let height = Double(value) {
                if value.hasPrefix("+") || value.hasPrefix("-") {
                    style.fontHeight = max(1, (style.fontHeight ?? defaultHeight) + height)
                } else {
                    style.fontHeight = max(1, height)
                }
            }
        case "color":
            style.color = parseColor(arguments)
        case "bold":
            style.bold = fontFlag(value)
        case "italic":
            style.italic = fontFlag(value)
        case "strike":
            style.strike = fontFlag(value)
        case "underline":
            style.underline = fontFlag(value)
        default:
            break
        }
    }

    private func fontFlag(_ value: String) -> Bool {
        ["1", "true", "on"].contains(value)
    }

    private func parseColor(_ arguments: [String]) -> BalloonColor? {
        guard let first = arguments.first?.lowercased(), first != "default" else { return nil }
        let named: [String: BalloonColor] = [
            "black": BalloonColor(red: 0, green: 0, blue: 0),
            "white": BalloonColor(red: 255, green: 255, blue: 255),
            "red": BalloonColor(red: 255, green: 0, blue: 0),
            "green": BalloonColor(red: 0, green: 128, blue: 0),
            "blue": BalloonColor(red: 0, green: 0, blue: 255),
            "yellow": BalloonColor(red: 255, green: 255, blue: 0),
            "gray": BalloonColor(red: 128, green: 128, blue: 128),
            "grey": BalloonColor(red: 128, green: 128, blue: 128)
        ]
        if let color = named[first] {
            return color
        }
        if first.hasPrefix("#"), first.count == 7, let value = Int(first.dropFirst(), radix: 16) {
            return BalloonColor(red: value >> 16, green: (value >> 8) & 0xFF, blue: value & 0xFF)
        }
        guard arguments.count >= 3 else { return nil }
        let components = arguments.prefix(3).compactMap { component -> Int? in
            if component.hasSuffix("%"), let percent = Double(component.dropLast()) {
                return Int((percent * 255 / 100).rounded())
            }
            return Int(component)
        }
        guard components.count == 3 else { return nil }
        return BalloonColor(
            red: min(max(components[0], 0), 255),
            green: min(max(components[1], 0), 255),
            blue: min(max(components[2], 0), 255)
        )
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

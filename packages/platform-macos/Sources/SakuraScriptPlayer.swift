import AppKit
import CoreText
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
    private var currentBalloon: BalloonDefinition?
    private var completedDialogueTimeoutMilliseconds: Int?
    private var notifiesChoiceTimeout = false
    private var resourceBaseDirectory: URL?
    private var currentScriptRawValue = ""
    private var activatedLinkKind: BalloonTextLink.Kind?

    public private(set) var isTimeCritical = false

    public var onError: (@MainActor (Error) -> Void)?
    public var onChoice: (@MainActor (String, [String]) -> Void)?
    public var onChoiceSelectEx: (@MainActor (String, String, [String]) -> Void)?
    public var onAnchorSelect: (@MainActor (String) -> Void)?
    public var onAnchorSelectEx: (@MainActor (String, String, [String]) -> Void)?
    public var onChoiceEnter: (@MainActor (String?, String?, [String]) -> Void)?
    public var onChoiceHover: (@MainActor (String, String, [String]) -> Void)?
    public var onAnchorEnter: (@MainActor (String?, String?, [String]) -> Void)?
    public var onAnchorHover: (@MainActor (String, String, [String]) -> Void)?
    public var onSoundStop: (@MainActor (String, String) -> Void)?
    public var onSoundError: (@MainActor (String, Error) -> Void)?
    public var onChoiceTimeout: (@MainActor (String) -> Void)?
    public var onBalloonClose: (@MainActor (String) -> Void)?
    public var onBalloonTimeout: (@MainActor (String) -> Void)?
    public var onEmbeddedEvent: (@MainActor (String, [String]) async -> SakuraScript?)?
    public var onInputBox: (@MainActor (String, Int?, String) async -> SakuraScript?)?
    public var onHTTP: (@MainActor (SakuraScriptHTTPRequest) async -> SakuraScript?)?
    public var onCancelHTTP: (@MainActor (String?) -> Void)?
    public var onNetworkDiagnostic: (@MainActor (SakuraScriptNetworkDiagnostic) async -> SakuraScript?)?
    public var onWebSocket: (@MainActor (SakuraScriptWebSocketCommand) async -> Void)?
    public var onWeatherGet: (@MainActor (String) async -> SakuraScript?)?
    public var onArchive: (@MainActor (SakuraScriptArchiveCommand) async -> SakuraScript?)?
    public var onPropertyValue: (@MainActor (String) async -> String?)?
    public var onGetProperties: (@MainActor (String, [String]) async -> SakuraScript?)?
    public var onSetProperty: (@MainActor (String, String) async -> Void)?
    public var onCloseInputBox: (@MainActor (String) -> Void)?
    public var onCommunicateBox: (@MainActor (String) async -> SakuraScript?)?
    public var onTeachBox: (@MainActor (String) async -> SakuraScript?)?
    public var onOtherGhostTalk: (@MainActor (String, String) -> Void)?
    public var onOtherSurfaceChange: (@MainActor (String, Int, Int) -> Void)?
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
        soundPlayer.onStop = { [weak self] file, reason in self?.onSoundStop?(file, reason) }
        soundPlayer.onError = { [weak self] file, error in self?.onSoundError?(file, error) }
        balloonWindowController.onClick = { [weak self] _ in
            self?.advance()
        }
        balloonWindowController.onLinkActivate = { [weak self] link, label in
            guard let self else { return }
            activatedLinkKind = link.kind
            switch link.kind {
            case .choice:
                onChoiceSelectEx?(label, link.id, link.arguments)
            case .anchor:
                onAnchorSelectEx?(label, link.id, link.arguments)
                onAnchorSelect?(link.id)
            }
        }
        balloonWindowController.onLinkClick = { [weak self] id, arguments in
            guard let self else { return }
            let linkKind = activatedLinkKind
            activatedLinkKind = nil
            if id.lowercased().hasPrefix("script:") {
                let script = String(id.dropFirst("script:".count))
                let balloon = currentBalloon
                cancel()
                if let balloon {
                    play(SakuraScript(rawValue: script), balloon: balloon)
                }
            } else {
                cancel()
                if linkKind != .anchor {
                    onChoice?(id, arguments)
                }
            }
        }
        balloonWindowController.onLinkEnter = { [weak self] link, label in
            guard let self else { return }
            switch link?.kind {
            case .choice:
                onChoiceEnter?(label, link?.id, link?.arguments ?? [])
            case .anchor:
                onAnchorEnter?(label, link?.id, link?.arguments ?? [])
            case nil:
                onChoiceEnter?(nil, nil, [])
                onAnchorEnter?(nil, nil, [])
            }
        }
        balloonWindowController.onLinkHover = { [weak self] link, label in
            guard let self else { return }
            switch link.kind {
            case .choice: onChoiceHover?(label, link.id, link.arguments)
            case .anchor: onAnchorHover?(label, link.id, link.arguments)
            }
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
        isTimeCritical = false
        currentBalloon = balloon
        currentScriptRawValue = script.rawValue
        balloonWindowController.hideAll()
        balloonWindowController.setWaitingForClick(false)
        let tokens = parser.parse(script)
        configureCompletionTimeout(for: tokens)
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
        self.resourceBaseDirectory = resourceBaseDirectory
        soundPlayer.resourceBaseDirectory = resourceBaseDirectory
    }

    public func configure(environmentVariables: [String: String]) {
        eventTimers.values.forEach { $0.cancel() }
        eventTimers.removeAll()
        self.environmentVariables = Dictionary(uniqueKeysWithValues: environmentVariables.map {
            ($0.key.lowercased(), $0.value)
        })
    }

    public func updateEnvironmentVariables(_ variables: [String: String]) {
        for (key, value) in variables {
            environmentVariables[key.lowercased()] = value
        }
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
        isTimeCritical = false
        balloonWindowController.setWaitingForClick(false)
        balloonWindowController.hideAll()
        finishPlaybackWait()
    }

    public func advance() {
        if isPlaybackComplete {
            onBalloonClose?(currentScriptRawValue)
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
        var inlineImagesByScope: [Int: [NSRange: NSImage]] = [:]
        var balloonStyleByScope = defaultBalloonSurfaceIDs
        var activatedScopes = Set<Int>()
        var isQuickSection = false
        var synchronizedScopes: Set<Int>?
        var repaintLockedScopes: Set<Int> = []
        var manualRepaintScopes: Set<Int> = []
        var balloonRepaintLockedScopes: Set<Int> = []
        var manualBalloonRepaintScopes: Set<Int> = []
        var autoscrollByScope: [Int: Bool] = [:]
        var automaticLineWrappingByScope: [Int: Bool] = [:]
        var verticalAlignmentByScope: [Int: BalloonVerticalAlignment] = [:]
        var balloonMarkerScopes: Set<Int> = []
        var balloonNumberScopes: Set<Int> = []
        var balloonOffsetScopes: Set<Int> = []
        var currentCharacterDelayMilliseconds = characterDelayMilliseconds
        var preciseWaitStartedAt = ProcessInfo.processInfo.systemUptime
        var isSerikoTalkEnabled = true

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

        func deleteText(scope: Int, range: NSRange) {
            let source = textByScope[scope, default: ""] as NSString
            let deletion = NSIntersectionRange(range, NSRange(location: 0, length: source.length))
            guard deletion.length > 0 else { return }
            textByScope[scope] = source.replacingCharacters(in: deletion, with: "")
            linksByScope[scope] = linksByScope[scope, default: []].compactMap { link in
                guard NSIntersectionRange(link.range, deletion).length == 0 else { return nil }
                let location = link.range.location >= NSMaxRange(deletion)
                    ? link.range.location - deletion.length
                    : link.range.location
                return BalloonTextLink(
                    range: NSRange(location: location, length: link.range.length),
                    id: link.id,
                    arguments: link.arguments,
                    kind: link.kind,
                    fontColor: link.fontColor
                )
            }
            styleRunsByScope[scope] = styleRunsByScope[scope, default: []].flatMap { run in
                var pieces: [BalloonTextStyleRun] = []
                if run.range.location < deletion.location {
                    let length = min(NSMaxRange(run.range), deletion.location) - run.range.location
                    if length > 0 {
                        pieces.append(BalloonTextStyleRun(
                            range: NSRange(location: run.range.location, length: length),
                            style: run.style
                        ))
                    }
                }
                if NSMaxRange(run.range) > NSMaxRange(deletion) {
                    let start = max(run.range.location, NSMaxRange(deletion))
                    pieces.append(BalloonTextStyleRun(
                        range: NSRange(
                            location: start - deletion.length,
                            length: NSMaxRange(run.range) - start
                        ),
                        style: run.style
                    ))
                }
                return pieces
            }
            anchorsByScope[scope] = nil
            choicesByScope[scope] = nil
        }

        func deletionRange(scope: Int, unit: SakuraScriptClearUnit, count: Int, start: Int?) -> NSRange {
            let source = textByScope[scope, default: ""] as NSString
            let sourceLength = source.length
            guard count > 0, sourceLength > 0 else { return NSRange(location: 0, length: 0) }
            switch unit {
            case .character:
                let location = start.map { min(max(0, $0), sourceLength) }
                    ?? max(0, sourceLength - count)
                return NSRange(location: location, length: min(count, sourceLength - location))
            case .line:
                var starts = [0]
                for index in 0 ..< sourceLength where source.character(at: index) == 10 {
                    starts.append(index + 1)
                }
                let firstLine = min(max(0, start ?? max(0, starts.count - count)), starts.count - 1)
                let endLine = min(starts.count, firstLine + count)
                let location = starts[firstLine]
                let end = endLine < starts.count ? starts[endLine] : sourceLength
                return NSRange(location: location, length: end - location)
            }
        }

        func updateContent(
            scope: Int,
            autoscroll: Bool = true
        ) {
            balloonWindowController.updateContent(
                text: textByScope[scope, default: ""],
                links: linksByScope[scope, default: []],
                styles: styleRunsByScope[scope, default: []],
                inlineImages: inlineImagesByScope[scope, default: [:]],
                autoscroll: autoscroll,
                scope: scope
            )
        }

        func activate(scope: Int, style: Int) throws {
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
                text: textByScope[scope, default: ""],
                scope: scope,
                speaker: speaker,
                style: style,
                near: surfaceFrame
            )
            updateContent(scope: scope)
        }

        func activateIfNeeded(scope: Int) throws {
            let text = textByScope[scope, default: ""]
            guard text.contains(where: { !$0.isWhitespace }) else { return }
            guard activatedScopes.insert(scope).inserted else { return }
            onDialogueContent?()
            try activate(scope: scope, style: balloonStyleByScope[scope] ?? 0)
            balloonWindowController.setVerticalAlignment(
                verticalAlignmentByScope[scope] ?? .top,
                scope: scope
            )
        }

        defer {
            isWaitingForClick = false
            balloonWindowController.setWaitingForClick(false)
            for lockedScope in repaintLockedScopes.subtracting(manualRepaintScopes) {
                surfaceWindowController.setRepaintLocked(false, scope: lockedScope)
            }
            for lockedScope in balloonRepaintLockedScopes.subtracting(manualBalloonRepaintScopes) {
                balloonWindowController.setRepaintLocked(false, scope: lockedScope)
            }
            for wrappedScope in automaticLineWrappingByScope.keys {
                balloonWindowController.setAutomaticLineWrapping(true, scope: wrappedScope)
            }
            for markerScope in balloonMarkerScopes {
                balloonWindowController.setMarkerText("", scope: markerScope)
            }
            for numberScope in balloonNumberScopes {
                balloonWindowController.setNumber(file: "", current: "", maximum: "", scope: numberScope)
            }
            for offsetScope in balloonOffsetScopes {
                balloonWindowController.resetOffset(scope: offsetScope)
            }
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
                        let targetScopes = synchronizedScopes?.sorted() ?? [scope]
                        for targetScope in targetScopes {
                            let start = textByScope[targetScope, default: ""].utf16.count
                            textByScope[targetScope, default: ""].append(character)
                            appendStyleRun(
                                scope: targetScope,
                                location: start,
                                length: character.utf16.count
                            )
                            try activateIfNeeded(scope: targetScope)
                            balloonWindowController.setAutomaticLineWrapping(
                                automaticLineWrappingByScope[targetScope] ?? true,
                                scope: targetScope
                            )
                            updateContent(
                                scope: targetScope,
                                autoscroll: autoscrollByScope[targetScope] ?? true
                            )
                            if isSerikoTalkEnabled, !character.isWhitespace {
                                surfaceWindowController.playTalkAnimation(scope: targetScope)
                            }
                        }
                        if !fastForwardRequested, !isQuickSection {
                            try await sleep(milliseconds: currentCharacterDelayMilliseconds)
                        }
                    }
                    fastForwardRequested = false
                case let .scope(newScope):
                    scope = newScope
                case let .surface(surfaceID):
                    try surfaceWindowController.changeSurface(scope: scope, to: surfaceID)
                case let .namedSurface(identifier):
                    try surfaceWindowController.changeSurface(scope: scope, named: identifier)
                case let .animation(identifier, waitsForCompletion):
                    if waitsForCompletion {
                        await surfaceWindowController.playAnimationAndWait(
                            identifier: identifier,
                            scope: scope
                        )
                    } else {
                        surfaceWindowController.playAnimation(identifier: identifier, scope: scope)
                    }
                case let .stopAnimation(identifier):
                    surfaceWindowController.stopAnimation(identifier: identifier, scope: scope)
                case let .pauseAnimation(identifier):
                    surfaceWindowController.pauseAnimation(identifier: identifier, scope: scope)
                case let .resumeAnimation(identifier):
                    surfaceWindowController.resumeAnimation(identifier: identifier, scope: scope)
                case let .waitForAnimation(identifier):
                    await surfaceWindowController.waitForAnimation(identifier: identifier, scope: scope)
                case let .offsetAnimation(identifier, x, y):
                    surfaceWindowController.setAnimationOffset(
                        identifier: identifier,
                        x: x,
                        y: y,
                        scope: scope
                    )
                case let .repaintLock(locked, manual):
                    surfaceWindowController.setRepaintLocked(locked, scope: scope)
                    if locked {
                        repaintLockedScopes.insert(scope)
                        if manual {
                            manualRepaintScopes.insert(scope)
                        }
                    } else {
                        repaintLockedScopes.remove(scope)
                        manualRepaintScopes.remove(scope)
                    }
                case let .balloonRepaintLock(locked, manual):
                    balloonWindowController.setRepaintLocked(locked, scope: scope)
                    if locked {
                        balloonRepaintLockedScopes.insert(scope)
                        if manual {
                            manualBalloonRepaintScopes.insert(scope)
                        }
                    } else {
                        balloonRepaintLockedScopes.remove(scope)
                        manualBalloonRepaintScopes.remove(scope)
                    }
                case let .balloonMoveLock(locked):
                    balloonWindowController.setMovementLocked(locked, scope: scope)
                case let .surfaceAlpha(percent, durationMilliseconds, waitsForCompletion):
                    let alpha = percent.map { Double($0) / 100 }
                    if waitsForCompletion {
                        await surfaceWindowController.setAlpha(
                            alpha,
                            scope: scope,
                            durationMilliseconds: durationMilliseconds
                        )
                    } else {
                        Task { @MainActor [surfaceWindowController] in
                            await surfaceWindowController.setAlpha(
                                alpha,
                                scope: scope,
                                durationMilliseconds: durationMilliseconds
                            )
                        }
                    }
                case let .surfaceScaling(
                    horizontalPercent,
                    verticalPercent,
                    durationMilliseconds,
                    waitsForCompletion
                ):
                    let horizontal = Double(horizontalPercent) / 100
                    let vertical = Double(verticalPercent) / 100
                    if waitsForCompletion {
                        await surfaceWindowController.setRuntimeScale(
                            horizontal: horizontal,
                            vertical: vertical,
                            scope: scope,
                            durationMilliseconds: durationMilliseconds
                        )
                    } else {
                        Task { @MainActor [surfaceWindowController] in
                            await surfaceWindowController.setRuntimeScale(
                                horizontal: horizontal,
                                vertical: vertical,
                                scope: scope,
                                durationMilliseconds: durationMilliseconds
                            )
                        }
                    }
                case let .desktopAlignment(alignment):
                    let surfaceAlignment: SurfaceDesktopAlignment = switch alignment {
                    case .top: .top
                    case .bottom: .bottom
                    case .left: .left
                    case .right: .right
                    case .free: .free
                    case .defaultValue: .defaultValue
                    }
                    surfaceWindowController.setDesktopAlignment(surfaceAlignment, scope: scope)
                case let .balloonWait(wait):
                    switch wait {
                    case .defaultValue:
                        currentCharacterDelayMilliseconds = characterDelayMilliseconds
                    case let .multiplier(multiplier):
                        currentCharacterDelayMilliseconds = max(
                            0,
                            Int((Double(characterDelayMilliseconds) * multiplier).rounded())
                        )
                    case let .milliseconds(milliseconds):
                        currentCharacterDelayMilliseconds = milliseconds
                    }
                case let .balloonMarker(text):
                    balloonMarkerScopes.insert(scope)
                    balloonWindowController.setMarkerText(text, scope: scope)
                case let .balloonNumber(file, current, maximum):
                    balloonNumberScopes.insert(scope)
                    balloonWindowController.setNumber(
                        file: file,
                        current: current,
                        maximum: maximum,
                        scope: scope
                    )
                case let .balloonOffset(x, y):
                    balloonOffsetScopes.insert(scope)
                    balloonWindowController.setOffset(x: x.value, y: y.value, scope: scope)
                case let .balloonAlignment(alignment):
                    let windowAlignment: BalloonWindowAlignment = switch alignment {
                    case .left: .left
                    case .center, .top: .center
                    case .right: .right
                    case .bottom: .bottom
                    case .none: .automatic
                    }
                    balloonWindowController.setAlignment(windowAlignment, scope: scope)
                case let .serikoTalk(enabled):
                    isSerikoTalkEnabled = enabled
                case let .autoscroll(enabled):
                    autoscrollByScope[scope] = enabled
                case .balloonTimeout:
                    break
                case let .bind(category, part, enabled, notifiesEvents):
                    let changes = surfaceWindowController.changeBind(
                        scope: scope,
                        category: category,
                        part: part,
                        enabled: enabled
                    )
                    if notifiesEvents, !changes.isEmpty {
                        for change in changes {
                            _ = await onEmbeddedEvent?(
                                "OnDressupChanged",
                                [
                                    String(change.scope),
                                    change.group.part,
                                    change.enabled ? "1" : "0",
                                    change.group.category,
                                    "script"
                                ]
                            )
                        }
                        let dressupReferences = surfaceWindowController.dressupInfo().map { info in
                            let options = [
                                info.options.mustSelect ? "mustselect" : nil,
                                info.options.multiple ? "multiple" : nil
                            ].compactMap(\.self).joined(separator: ",")
                            return [
                                String(info.scope),
                                info.group.category,
                                info.group.part,
                                options,
                                info.enabled ? "1" : "0",
                                info.group.thumbnail
                            ].joined(separator: "\u{1}")
                        }
                        _ = await onEmbeddedEvent?("OnNotifyDressupInfo", dressupReferences)
                    }
                case let .balloonSurface(style):
                    balloonStyleByScope[scope] = style
                    if style < 0 {
                        balloonWindowController.hide(scope: scope)
                    } else if activatedScopes.contains(scope) {
                        try balloonWindowController.changeStyle(style, scope: scope)
                    }
                case let .lineBreak(scale):
                    for targetScope in synchronizedScopes?.sorted() ?? [scope] {
                        let start = textByScope[targetScope, default: ""].utf16.count
                        let source = textByScope[targetScope, default: ""] as NSString
                        let previousNewline = source.range(of: "\n", options: .backwards)
                        let lineStart = previousNewline.location == NSNotFound ? 0 : NSMaxRange(previousNewline)
                        textByScope[targetScope, default: ""].append("\n")
                        if let scale {
                            var breakStyle = BalloonTextStyle()
                            breakStyle.alignment = textStyleByScope[targetScope]?.alignment
                            breakStyle.lineHeight = max(1, Double(balloon.fontHeight) * scale)
                            styleRunsByScope[targetScope, default: []].append(BalloonTextStyleRun(
                                range: NSRange(location: lineStart, length: start - lineStart + 1),
                                style: breakStyle
                            ))
                        }
                        try activateIfNeeded(scope: targetScope)
                        balloonWindowController.setAutomaticLineWrapping(
                            automaticLineWrappingByScope[targetScope] ?? true,
                            scope: targetScope
                        )
                        updateContent(scope: targetScope)
                        textStyleByScope[targetScope, default: BalloonTextStyle()].alignment = nil
                    }
                case .automaticLineBreak:
                    let enabled = !(automaticLineWrappingByScope[scope] ?? true)
                    automaticLineWrappingByScope[scope] = enabled
                    balloonWindowController.setAutomaticLineWrapping(enabled, scope: scope)
                case let .partialClear(unit, count, start):
                    deleteText(
                        scope: scope,
                        range: deletionRange(scope: scope, unit: unit, count: count, start: start)
                    )
                    updateContent(
                        scope: scope,
                        autoscroll: autoscrollByScope[scope] ?? true
                    )
                case let .wait(milliseconds):
                    if fastForwardRequested {
                        fastForwardRequested = false
                    } else {
                        try await sleep(milliseconds: milliseconds)
                    }
                case let .waitUntil(milliseconds):
                    if let milliseconds {
                        let elapsed = Int((ProcessInfo.processInfo.systemUptime - preciseWaitStartedAt) * 1000)
                        if elapsed < milliseconds {
                            try await sleep(milliseconds: milliseconds - elapsed)
                        }
                    } else {
                        preciseWaitStartedAt = ProcessInfo.processInfo.systemUptime
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
                    preciseWaitStartedAt = ProcessInfo.processInfo.systemUptime
                    if clearOnResume {
                        textByScope.removeAll()
                        linksByScope.removeAll()
                        anchorsByScope.removeAll()
                        choicesByScope.removeAll()
                        textStyleByScope.removeAll()
                        styleRunsByScope.removeAll()
                    }
                case .timeCritical:
                    isTimeCritical = true
                case let .choice(label, id, arguments):
                    let start = textByScope[scope, default: ""].utf16.count
                    textByScope[scope, default: ""].append(label)
                    appendStyleRun(scope: scope, location: start, length: label.utf16.count)
                    linksByScope[scope, default: []].append(
                        BalloonTextLink(
                            range: NSRange(location: start, length: label.utf16.count),
                            id: id,
                            arguments: arguments,
                            fontColor: nil
                        )
                    )
                    try activateIfNeeded(scope: scope)
                    updateContent(scope: scope)
                case let .choiceStart(id, arguments):
                    choicesByScope[scope] = ActiveAnchor(
                        id: id,
                        arguments: arguments,
                        start: textByScope[scope, default: ""].utf16.count,
                        fontColor: nil
                    )
                case .choiceEnd:
                    guard let choice = choicesByScope.removeValue(forKey: scope) else { continue }
                    let end = textByScope[scope, default: ""].utf16.count
                    guard end > choice.start else { continue }
                    linksByScope[scope, default: []].append(
                        BalloonTextLink(
                            range: NSRange(location: choice.start, length: end - choice.start),
                            id: choice.id,
                            arguments: choice.arguments,
                            fontColor: choice.fontColor
                        )
                    )
                    textByScope[scope, default: ""].append("\n")
                    updateContent(scope: scope)
                case .choiceTimeout:
                    continue
                case let .anchorStart(id, arguments):
                    anchorsByScope[scope] = ActiveAnchor(
                        id: id,
                        arguments: arguments,
                        start: textByScope[scope, default: ""].utf16.count,
                        fontColor: textStyleByScope[scope]?.anchorFontColor
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
                            kind: .anchor,
                            fontColor: anchor.fontColor
                        )
                    )
                    updateContent(scope: scope)
                case .marker:
                    textByScope[scope, default: ""].append("\u{FFFC}")
                    try activateIfNeeded(scope: scope)
                    updateContent(scope: scope)
                case let .environmentVariable(name):
                    pendingTokens.insert(.text(environmentValue(for: name)), at: 0)
                case let .property(property):
                    await pendingTokens.insert(.text(onPropertyValue?(property) ?? ""), at: 0)
                case let .getProperties(eventID, properties):
                    if let response = await onGetProperties?(eventID, properties) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .setProperty(property, value):
                    await onSetProperty?(property, value)
                case let .font(name, arguments):
                    if name == "valign" {
                        let alignment: BalloonVerticalAlignment = switch arguments.first?.lowercased() {
                        case "center": .center
                        case "bottom": .bottom
                        default: .top
                        }
                        verticalAlignmentByScope[scope] = alignment
                        balloonWindowController.setVerticalAlignment(alignment, scope: scope)
                    }
                    applyFontCommand(
                        name: name,
                        arguments: arguments,
                        style: &textStyleByScope[scope, default: BalloonTextStyle()],
                        defaultHeight: Double(balloon.fontHeight),
                        fontDirectories: [resourceBaseDirectory, balloon.directory].compactMap(\.self)
                    )
                    if name == "align",
                       let alignment = textStyleByScope[scope]?.alignment
                    {
                        let text = textByScope[scope, default: ""] as NSString
                        let newline = text.range(of: "\n", options: .backwards)
                        let lineStart = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
                        let length = text.length - lineStart
                        if length > 0 {
                            var alignmentStyle = BalloonTextStyle()
                            alignmentStyle.alignment = alignment
                            styleRunsByScope[scope, default: []].append(BalloonTextStyleRun(
                                range: NSRange(location: lineStart, length: length),
                                style: alignmentStyle
                            ))
                            updateContent(scope: scope)
                        }
                    }
                case let .quickSection(enabled):
                    isQuickSection = enabled ?? !isQuickSection
                case let .synchronizeScopes(scopes):
                    if let scopes {
                        synchronizedScopes = Set(scopes)
                    } else {
                        synchronizedScopes = synchronizedScopes == nil ? [0, 1] : nil
                    }
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
                case let .stayOnTop(stayOnTop):
                    surfaceWindowController.setStayOnTop(stayOnTop)
                    balloonWindowController.setStayOnTop(stayOnTop)
                case let .moveSurface(x, y, time, isAsync, options):
                    await surfaceWindowController.moveSurface(
                        scope: scope,
                        x: x,
                        y: y,
                        time: time,
                        isAsync: isAsync,
                        options: options
                    )
                case .separateCharacters:
                    await surfaceWindowController.separateCharacters(scope: scope)
                case .approachCharacters:
                    await surfaceWindowController.approachCharacters(scope: scope)
                case let .setZOrder(order):
                    surfaceWindowController.setZOrder(order)
                case .resetZOrder:
                    surfaceWindowController.resetZOrder()
                case let .setStickyWindows(scopes):
                    surfaceWindowController.setStickyWindows(scopes: scopes)
                case .resetStickyWindows:
                    surfaceWindowController.resetStickyWindows()
                case let .inlineImage(path, _, _):
                    if let image = resolveInlineImage(path: path) {
                        let targetScope = scope
                        let currentLength = (textByScope[targetScope, default: ""] as NSString).length
                        textByScope[targetScope, default: ""].append("\u{FFFC}")
                        var currentImages = inlineImagesByScope[targetScope, default: [:]]
                        currentImages[NSRange(location: currentLength, length: 1)] = image
                        inlineImagesByScope[targetScope] = currentImages

                        try activateIfNeeded(scope: targetScope)
                        updateContent(
                            scope: targetScope,
                            autoscroll: autoscrollByScope[targetScope] ?? true
                        )
                    }
                case let .otherGhostTalk(target, script):
                    onOtherGhostTalk?(target, script)
                case let .otherSurfaceChange(target, scope, surfaceID):
                    onOtherSurfaceChange?(target, scope, surfaceID)
                case let .otherTimerEvent(target, milliseconds, repeats, reflectsResponse, id, arguments):
                    scheduleOtherEventTimer(
                        target: target,
                        milliseconds: milliseconds,
                        repeats: repeats,
                        reflectsResponse: reflectsResponse,
                        id: id,
                        arguments: arguments
                    )
                case let .cancelHTTP(url):
                    onCancelHTTP?(url)
                case let .closeInputBox(id):
                    onCloseInputBox?(id)
                case let .communicateBox(initialValue):
                    if let response = await onCommunicateBox?(initialValue) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .teachBox(initialValue):
                    if let response = await onTeachBox?(initialValue) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .archive(command):
                    if let response = await onArchive?(command) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .contentAction(action):
                    onContentAction?(action)
                case .resetWindowPositions:
                    surfaceWindowController.resetWindowPositions()
                    balloonWindowController.resetWindowPositions()
                case .resetBalloonPositions:
                    balloonWindowController.resetWindowPositions()
                case let .inputBox(id, timeoutMilliseconds, initialValue):
                    if let response = await onInputBox?(id, timeoutMilliseconds, initialValue) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .http(request):
                    if let response = await onHTTP?(request) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .networkDiagnostic(command):
                    if let response = await onNetworkDiagnostic?(command) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case let .webSocket(command):
                    await onWebSocket?(command)
                case let .weatherGet(eventID):
                    if let response = await onWeatherGet?(eventID) {
                        pendingTokens.insert(contentsOf: parser.parse(response), at: 0)
                    }
                case .clear:
                    textByScope[scope] = ""
                    linksByScope[scope] = []
                    anchorsByScope[scope] = nil
                    choicesByScope[scope] = nil
                    styleRunsByScope[scope] = []
                    inlineImagesByScope[scope] = [:]
                    updateContent(scope: scope)
                case .clearAll:
                    for activeScope in activatedScopes {
                        textByScope[activeScope] = ""
                        linksByScope[activeScope] = []
                        styleRunsByScope[activeScope] = []
                        inlineImagesByScope[activeScope] = [:]
                        updateContent(scope: activeScope)
                    }
                    textByScope.removeAll()
                    linksByScope.removeAll()
                    anchorsByScope.removeAll()
                    choicesByScope.removeAll()
                    styleRunsByScope.removeAll()
                    inlineImagesByScope.removeAll()
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

    private func scheduleOtherEventTimer(
        target: String,
        milliseconds: Int,
        repeats: Bool,
        reflectsResponse: Bool,
        id: String,
        arguments: [String]
    ) {
        let timerKey = "other:\(target):\(id)"
        eventTimers[timerKey]?.cancel()
        eventTimers[timerKey] = nil
        guard milliseconds > 0 else { return }
        eventTimers[timerKey] = Task { [weak self] in
            repeat {
                do {
                    try await Task.sleep(for: .milliseconds(milliseconds))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await onOtherEvent?(target, id, arguments, reflectsResponse)
            } while repeats && !Task.isCancelled
            self?.eventTimers[timerKey] = nil
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
        case "et":
            return ["42年", "150分", "3世紀", "999日", "3000万秒", "一昨日からずっと"].randomElement()!
        case "wronghour":
            let currentHour = calendar.component(.hour, from: now)
            let wrong = (currentHour + Int.random(in: 1 ... 11)) % 24
            return String(wrong)
        case "ms": return ["学生", "会社員", "旅人", "猫好き"].randomElement()!
        case "mz": return ["時計", "傘", "冷蔵庫", "パソコン"].randomElement()!
        case "ml": return ["人々", "鳥の群れ", "本の山", "星々"].randomElement()!
        case "mc": return ["架空電機", "月見商事", "北風出版", "うたたね工房"].randomElement()!
        case "mh": return ["喫茶店", "本屋", "食堂", "雑貨店"].randomElement()!
        case "mt": return ["必殺技", "早起き", "高速タイピング", "居眠り"].randomElement()!
        case "me": return ["カレー", "おにぎり", "プリン", "焼き芋"].randomElement()!
        case "mp": return ["東京", "月面", "商店街", "海辺"].randomElement()!
        case "m?": return ["何か", "不思議なもの", "例のあれ", "秘密"].randomElement()!
        case "dms": return ["猫に相談する話", "月へ運ぶ計画", "静かに片付ける方法", "明日試す約束"].randomElement()!
        default: return "%\(name)"
        }
    }

    private func resolveInlineImage(path: String) -> NSImage? {
        if path.hasPrefix("data:image/") {
            if let commaIndex = path.firstIndex(of: ",") {
                let base64String = String(path[path.index(after: commaIndex)...])
                if let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) {
                    return NSImage(data: data)
                }
            }
        }
        guard let baseDirectory = resourceBaseDirectory else { return nil }
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let url = baseDirectory.appending(path: normalizedPath)
        if FileManager.default.fileExists(atPath: url.path) {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private func applyFontCommand(
        name: String,
        arguments: [String],
        style: inout BalloonTextStyle,
        defaultHeight: Double,
        fontDirectories: [URL]
    ) {
        let value = arguments.first?.lowercased() ?? ""
        switch name {
        case "default", "disable":
            style = BalloonTextStyle()
        case "name":
            if value == "default" {
                style.fontName = nil
            } else {
                style.fontName = resolveFontName(
                    candidates: arguments,
                    size: defaultHeight,
                    directories: fontDirectories
                )
            }
        case "height":
            if value == "default" {
                style.fontHeight = nil
            } else if let scale = [
                "xx-small": 0.6,
                "x-small": 0.75,
                "small": 0.89,
                "medium": 1.0,
                "large": 1.2,
                "x-large": 1.5,
                "xx-large": 2.0
            ][value] {
                style.fontHeight = defaultHeight * scale
            } else if value == "smaller" {
                style.fontHeight = max(1, (style.fontHeight ?? defaultHeight) / 1.2)
            } else if value == "larger" {
                style.fontHeight = (style.fontHeight ?? defaultHeight) * 1.2
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
        case "align":
            style.alignment = switch value {
            case "center": .center
            case "right": .right
            case "left": .left
            default: nil
            }
        case "anchor.font.color":
            style.anchorFontColor = parseColor(arguments)
        case "shadowcolor":
            style.shadowColor = value == "none" ? nil : parseColor(arguments)
        case "shadowstyle":
            style.shadowStyle = ["offset", "outline"].contains(value) ? value : nil
        case "outline":
            style.outline = fontFlag(value)
        case "bold":
            style.bold = fontFlag(value)
        case "italic":
            style.italic = fontFlag(value)
        case "strike":
            style.strike = fontFlag(value)
        case "underline":
            style.underline = fontFlag(value)
        case "sub":
            style.baseline = fontFlag(value) ? -1 : 0
        case "sup":
            style.baseline = fontFlag(value) ? 1 : 0
        default:
            break
        }
    }

    private func resolveFontName(candidates: [String], size: Double, directories: [URL]) -> String? {
        for candidate in candidates {
            if NSFont(name: candidate, size: size) != nil {
                return candidate
            }
            for directory in directories {
                let root = directory.standardizedFileURL
                let file = root.appending(path: candidate).standardizedFileURL
                guard file.path.hasPrefix(root.path + "/"),
                      FileManager.default.fileExists(atPath: file.path),
                      CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
                else { continue }
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor]
                if let name = descriptors?.compactMap({ descriptor in
                    CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
                }).first(where: { NSFont(name: $0, size: size) != nil }) {
                    return name
                }
            }
        }
        return nil
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
        isTimeCritical = false
        isPlaybackComplete = true
        isWaitingForClick = false
        balloonWindowController.setWaitingForClick(false)
        finishPlaybackWait()
        onPlaybackFinished?()
        dismissalTask?.cancel()
        guard let timeout = completedDialogueTimeoutMilliseconds else { return }
        dismissalTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await sleep(milliseconds: timeout)
            } catch {
                return
            }
            let shouldNotifyChoiceTimeout = notifiesChoiceTimeout
            if !shouldNotifyChoiceTimeout {
                onBalloonTimeout?(currentScriptRawValue)
            }
            dismissCompletedDialogue()
            if shouldNotifyChoiceTimeout {
                onChoiceTimeout?(currentScriptRawValue)
            }
        }
    }

    private func configureCompletionTimeout(for tokens: [SakuraScriptToken]) {
        let hasChoices = tokens.contains { token in
            switch token {
            case .choice, .choiceStart: true
            default: false
            }
        }
        let choicePolicy = tokens.compactMap { token -> SakuraScriptChoiceTimeout? in
            if case let .choiceTimeout(policy) = token {
                return policy
            }
            return nil
        }.last ?? .defaultValue
        let balloonPolicy = tokens.compactMap { token -> SakuraScriptChoiceTimeout? in
            if case let .balloonTimeout(policy) = token {
                return policy
            }
            return nil
        }.last ?? .defaultValue
        let balloonTimeout = resolveTimeout(balloonPolicy)
        guard hasChoices else {
            completedDialogueTimeoutMilliseconds = balloonTimeout
            notifiesChoiceTimeout = false
            return
        }
        let choiceTimeout = resolveTimeout(choicePolicy)
        switch (choiceTimeout, balloonTimeout) {
        case let (choice?, balloon?) where choice <= balloon:
            completedDialogueTimeoutMilliseconds = choice
            notifiesChoiceTimeout = true
        case let (_, balloon?):
            completedDialogueTimeoutMilliseconds = balloon
            notifiesChoiceTimeout = false
        case (let choice?, nil):
            completedDialogueTimeoutMilliseconds = choice
            notifiesChoiceTimeout = true
        case (nil, nil):
            completedDialogueTimeoutMilliseconds = nil
            notifiesChoiceTimeout = false
        }
    }

    private func resolveTimeout(_ policy: SakuraScriptChoiceTimeout) -> Int? {
        switch policy {
        case .defaultValue: postDialogueDismissalMilliseconds
        case .disabled: nil
        case let .milliseconds(milliseconds): milliseconds
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
    let fontColor: BalloonColor?
}

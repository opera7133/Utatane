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
    private var currentBalloon: BalloonDefinition?
    private var completedDialogueTimeoutMilliseconds: Int?
    private var notifiesChoiceTimeout = false

    public private(set) var isTimeCritical = false

    public var onError: (@MainActor (Error) -> Void)?
    public var onChoice: (@MainActor (String, [String]) -> Void)?
    public var onChoiceTimeout: (@MainActor () -> Void)?
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
            guard let self else { return }
            if id.lowercased().hasPrefix("script:") {
                let script = String(id.dropFirst("script:".count))
                let balloon = currentBalloon
                cancel()
                if let balloon {
                    play(SakuraScript(rawValue: script), balloon: balloon)
                }
            } else {
                cancel()
                onChoice?(id, arguments)
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
        isTimeCritical = false
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
        var synchronizedScopes: Set<Int>?
        var repaintLockedScopes: Set<Int> = []
        var manualRepaintScopes: Set<Int> = []
        var autoscrollByScope: [Int: Bool] = [:]
        var currentCharacterDelayMilliseconds = characterDelayMilliseconds
        var preciseWaitStartedAt = ProcessInfo.processInfo.systemUptime

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
            for lockedScope in repaintLockedScopes.subtracting(manualRepaintScopes) {
                surfaceWindowController.setRepaintLocked(false, scope: lockedScope)
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
                            try activateIfNeeded(
                                scope: targetScope,
                                balloon: balloon,
                                text: textByScope[targetScope, default: ""],
                                links: linksByScope[targetScope, default: []],
                                style: balloonStyleByScope[targetScope] ?? 0,
                                activatedScopes: &activatedScopes
                            )
                            updateContent(
                                scope: targetScope,
                                text: textByScope[targetScope, default: ""],
                                links: linksByScope[targetScope, default: []],
                                styles: styleRunsByScope[targetScope, default: []],
                                autoscroll: autoscrollByScope[targetScope] ?? true
                            )
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
                    if activatedScopes.contains(scope) {
                        try balloonWindowController.changeStyle(style, scope: scope)
                    }
                case .lineBreak:
                    for targetScope in synchronizedScopes?.sorted() ?? [scope] {
                        textByScope[targetScope, default: ""].append("\n")
                        try activateIfNeeded(
                            scope: targetScope,
                            balloon: balloon,
                            text: textByScope[targetScope, default: ""],
                            links: linksByScope[targetScope, default: []],
                            style: balloonStyleByScope[targetScope] ?? 0,
                            activatedScopes: &activatedScopes
                        )
                        updateContent(
                            scope: targetScope,
                            text: textByScope[targetScope, default: ""],
                            links: linksByScope[targetScope, default: []],
                            styles: styleRunsByScope[targetScope, default: []]
                        )
                    }
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
                case .choiceTimeout:
                    continue
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
                    choicesByScope[scope] = nil
                    styleRunsByScope[scope] = []
                    updateContent(scope: scope, text: "", links: [], styles: [])
                case .clearAll:
                    for activeScope in activatedScopes {
                        updateContent(scope: activeScope, text: "", links: [], styles: [])
                    }
                    textByScope.removeAll()
                    linksByScope.removeAll()
                    anchorsByScope.removeAll()
                    choicesByScope.removeAll()
                    styleRunsByScope.removeAll()
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
        styles: [BalloonTextStyleRun] = [],
        autoscroll: Bool = true
    ) {
        balloonWindowController.updateContent(
            text: text,
            links: links,
            styles: styles,
            autoscroll: autoscroll,
            scope: scope
        )
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
        case "sub":
            style.baseline = fontFlag(value) ? -1 : 0
        case "sup":
            style.baseline = fontFlag(value) ? 1 : 0
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
            dismissCompletedDialogue()
            if shouldNotifyChoiceTimeout {
                onChoiceTimeout?()
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
}

public enum SakuraScriptToken: Sendable, Equatable {
    case text(String)
    case scope(Int)
    case surface(Int)
    case namedSurface(String)
    case animation(identifier: String, waitsForCompletion: Bool)
    case stopAnimation(String)
    case pauseAnimation(String)
    case resumeAnimation(String)
    case waitForAnimation(String)
    case offsetAnimation(identifier: String, x: Int, y: Int)
    case repaintLock(locked: Bool, manual: Bool)
    case surfaceAlpha(percent: Int?, durationMilliseconds: Int, waitsForCompletion: Bool)
    case balloonSurface(Int)
    case bind(category: String, part: String, enabled: Bool?, notifiesEvents: Bool)
    case lineBreak
    case wait(milliseconds: Int)
    case waitUntil(milliseconds: Int?)
    case waitForClick(clearOnResume: Bool)
    case timeCritical
    case choice(label: String, id: String, arguments: [String])
    case choiceStart(id: String, arguments: [String])
    case choiceEnd
    case choiceTimeout(SakuraScriptChoiceTimeout)
    case balloonTimeout(SakuraScriptChoiceTimeout)
    case balloonWait(SakuraScriptBalloonWait)
    case autoscroll(Bool)
    case anchorStart(id: String, arguments: [String])
    case anchorEnd
    case marker
    case environmentVariable(String)
    case font(name: String, arguments: [String])
    case quickSection(Bool?)
    case synchronizeScopes([Int]?)
    case open(String)
    case sound(SakuraScriptSoundCommand)
    case embeddedEvent(id: String, arguments: [String])
    case raisedEvent(id: String, arguments: [String])
    case notifyEvent(id: String, arguments: [String])
    case otherEvent(target: String, id: String, arguments: [String], reflectsResponse: Bool)
    case timerEvent(milliseconds: Int, repeats: Bool, reflectsResponse: Bool, id: String, arguments: [String])
    case contentAction(SakuraScriptContentAction)
    case inputBox(id: String, timeoutMilliseconds: Int?, initialValue: String)
    case httpGet(url: String, eventID: String)
    case weatherGet(eventID: String)
    case clear
    case clearAll
    case end
    case unknown(String)
}

public enum SakuraScriptChoiceTimeout: Sendable, Equatable {
    case defaultValue
    case disabled
    case milliseconds(Int)
}

public enum SakuraScriptBalloonWait: Sendable, Equatable {
    case defaultValue
    case multiplier(Double)
    case milliseconds(Int)
}

public enum SakuraScriptContentAction: Sendable, Equatable {
    case randomGhost
    case nextGhost
    case changeGhost(String)
    case callGhost(String)
    case changeShell(String)
    case changeBalloon(String)
    case updateGhost
    case updateBalloon
    case headline(String)
}

public enum SakuraScriptSoundCommand: Sendable, Equatable {
    case play(file: String, loop: Bool, options: [String])
    case load(file: String, options: [String])
    case option(file: String?, options: [String])
    case wait
    case pause
    case resume
    case stop
}

public enum SakuraScriptToken: Sendable, Equatable {
    case text(String)
    case scope(Int)
    case surface(Int)
    case namedSurface(String)
    case balloonSurface(Int)
    case lineBreak
    case wait(milliseconds: Int)
    case waitForClick(clearOnResume: Bool)
    case choice(label: String, id: String, arguments: [String])
    case choiceStart(id: String, arguments: [String])
    case choiceEnd
    case anchorStart(id: String, arguments: [String])
    case anchorEnd
    case marker
    case environmentVariable(String)
    case font(name: String, arguments: [String])
    case quickSection(Bool?)
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
    case end
    case unknown(String)
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

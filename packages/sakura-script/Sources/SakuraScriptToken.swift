public enum SakuraScriptToken: Sendable, Equatable {
    case text(String)
    case scope(Int)
    case surface(Int)
    case namedSurface(String)
    case lineBreak
    case wait(milliseconds: Int)
    case waitForClick(clearOnResume: Bool)
    case choice(label: String, id: String, arguments: [String])
    case anchorStart(id: String, arguments: [String])
    case anchorEnd
    case embeddedEvent(id: String, arguments: [String])
    case inputBox(id: String, timeoutMilliseconds: Int?, initialValue: String)
    case httpGet(url: String, eventID: String)
    case weatherGet(eventID: String)
    case clear
    case end
    case unknown(String)
}

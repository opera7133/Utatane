import Foundation

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
    case balloonRepaintLock(locked: Bool, manual: Bool)
    case balloonMoveLock(Bool)
    case surfaceAlpha(percent: Int?, durationMilliseconds: Int, waitsForCompletion: Bool)
    case surfaceScaling(
        horizontalPercent: Int,
        verticalPercent: Int,
        durationMilliseconds: Int,
        waitsForCompletion: Bool
    )
    case desktopAlignment(SakuraScriptDesktopAlignment)
    case resetWindowPositions
    case resetBalloonPositions
    case balloonSurface(Int)
    case bind(category: String, part: String, enabled: Bool?, notifiesEvents: Bool)
    case lineBreak(scale: Double?)
    case automaticLineBreak
    case partialClear(unit: SakuraScriptClearUnit, count: Int, start: Int?)
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
    case balloonOffset(x: SakuraScriptBalloonCoordinate, y: SakuraScriptBalloonCoordinate)
    case balloonAlignment(SakuraScriptBalloonAlignment)
    case balloonMarker(String)
    case balloonNumber(file: String, current: String, maximum: String)
    case serikoTalk(Bool)
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
    case http(SakuraScriptHTTPRequest)
    case networkDiagnostic(SakuraScriptNetworkDiagnostic)
    case webSocket(SakuraScriptWebSocketCommand)
    case weatherGet(eventID: String)
    case clear
    case clearAll
    case end
    case unknown(String)
}

public enum SakuraScriptWebSocketCommand: Sendable, Equatable {
    case connect(url: String, eventID: String, headers: [String], protocolName: String?)
    case sendText(url: String, value: String)
    case sendBinary(url: String, value: Data)
    case close(url: String, code: Int)
    case cancel(url: String)
}

public enum SakuraScriptNetworkDiagnostic: Sendable, Equatable {
    case ping(host: String, eventID: String, count: Int, size: Int, timeoutMilliseconds: Int, ttl: Int?)
    case nslookup(host: String, eventID: String)
}

public struct SakuraScriptHTTPRequest: Sendable, Equatable {
    public let method: String
    public let url: String
    public let eventID: String?
    public let waitsForCompletion: Bool
    public let parameters: [String]
    public let headers: [String]
    public let timeoutSeconds: Double?
    public let output: SakuraScriptHTTPOutput

    public init(
        method: String,
        url: String,
        eventID: String?,
        waitsForCompletion: Bool,
        parameters: [String] = [],
        headers: [String] = [],
        timeoutSeconds: Double? = nil,
        output: SakuraScriptHTTPOutput = .file(nil)
    ) {
        self.method = method
        self.url = url
        self.eventID = eventID
        self.waitsForCompletion = waitsForCompletion
        self.parameters = parameters
        self.headers = headers
        self.timeoutSeconds = timeoutSeconds
        self.output = output
    }
}

public enum SakuraScriptHTTPOutput: Sendable, Equatable {
    case file(String?)
    case memory(characterEncoding: String?)
}

public struct SakuraScriptBalloonCoordinate: Sendable, Equatable {
    public let value: Int
    public let isRelative: Bool

    public init(value: Int, isRelative: Bool) {
        self.value = value
        self.isRelative = isRelative
    }
}

public enum SakuraScriptBalloonAlignment: String, Sendable, Equatable {
    case left
    case center
    case top
    case right
    case bottom
    case none
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

public enum SakuraScriptDesktopAlignment: String, Sendable, Equatable {
    case top
    case bottom
    case left
    case right
    case free
    case defaultValue = "default"
}

public enum SakuraScriptClearUnit: String, Sendable, Equatable {
    case character = "char"
    case line
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

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
    case property(String)
    case getProperties(eventID: String, properties: [String])
    case setProperty(property: String, value: String)
    case font(name: String, arguments: [String])
    case quickSection(Bool?)
    case synchronizeScopes([Int]?)
    case onlineMode(Bool)
    case noUserBreakMode(Bool)
    case interactionMode(SakuraScriptInteractionMode, enabled: Bool)
    case collisionMode(enabled: Bool, showsNames: Bool)
    case syncObjectWait(name: String, timeoutMilliseconds: Int?)
    case syncObjectSet(String)
    case syncObjectReset(String)
    case open(String)
    case sound(SakuraScriptSoundCommand)
    case contentAction(SakuraScriptContentAction)
    case embeddedEvent(id: String, arguments: [String])
    case raisedEvent(id: String, arguments: [String])
    case notifyEvent(id: String, arguments: [String])
    case otherEvent(target: String, id: String, arguments: [String], reflectsResponse: Bool)
    case timerEvent(milliseconds: Int, repeats: Bool, reflectsResponse: Bool, id: String, arguments: [String])
    case moveSurface(x: Int?, y: Int?, time: Int, isAsync: Bool, options: [String])
    case setPosition(x: Int, y: Int, scope: Int)
    case resetPosition
    case separateCharacters
    case approachCharacters
    case setZOrder([String])
    case resetZOrder
    case setStickyWindows([Int])
    case resetStickyWindows
    case inlineImage(path: String, isOpaque: Bool, options: [String])
    case otherGhostTalk(target: String, script: String)
    case otherSurfaceChange(target: String, scope: Int, surfaceID: Int)
    case stayOnTop(Bool)
    case closeInputBox(id: String)
    case otherTimerEvent(target: String, milliseconds: Int, repeats: Bool, reflectsResponse: Bool, id: String, arguments: [String])
    case archive(SakuraScriptArchiveCommand)
    case cancelHTTP(url: String?)
    case inputBox(id: String, timeoutMilliseconds: Int?, initialValue: String)
    case systemDialog(SakuraScriptSystemDialogCommand)
    case closeSystemDialog(id: String)
    case communicateBox(initialValue: String)
    case teachBox(initialValue: String)
    case http(SakuraScriptHTTPRequest)
    case networkDiagnostic(SakuraScriptNetworkDiagnostic)
    case webSocket(SakuraScriptWebSocketCommand)
    case weatherGet(eventID: String)
    case clear
    case clearAll
    case end
    case unknown(String)
}

public struct SakuraScriptSystemDialogCommand: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case open
        case save
        case folder
        case color
    }

    public let kind: Kind
    public let id: String
    public let title: String?
    public let directory: String?
    public let filter: String?
    public let fileExtension: String?
    public let name: String?
    public let color: String?

    public init(
        kind: Kind, id: String, title: String? = nil, directory: String? = nil,
        filter: String? = nil, fileExtension: String? = nil, name: String? = nil,
        color: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.directory = directory
        self.filter = filter
        self.fileExtension = fileExtension
        self.name = name
        self.color = color
    }
}

public enum SakuraScriptInteractionMode: Sendable, Equatable {
    case passive
    case induction
}

public enum SakuraScriptInstallSource: Sendable, Equatable {
    case path(String)
    case url(String, type: String?)
}

public enum SakuraScriptArchiveCommand: Sendable, Equatable {
    case extract(archivePath: String, destinationPath: String, eventID: String?, password: String?)
    case compress(archivePath: String, sourceDirectoryPath: String, eventID: String?, password: String?)
    case createNar(narPath: String, sourceDirectoryPath: String, eventID: String?)
    case dumpSurface(path: String?, eventID: String?)
    case createUpdateData(directoryPath: String?, eventID: String?)
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
    public let isFeed: Bool

    public init(
        method: String,
        url: String,
        eventID: String?,
        waitsForCompletion: Bool,
        parameters: [String] = [],
        headers: [String] = [],
        timeoutSeconds: Double? = nil,
        output: SakuraScriptHTTPOutput = .file(nil),
        isFeed: Bool = false
    ) {
        self.method = method
        self.url = url
        self.eventID = eventID
        self.waitsForCompletion = waitsForCompletion
        self.parameters = parameters
        self.headers = headers
        self.timeoutSeconds = timeoutSeconds
        self.output = output
        self.isFeed = isFeed
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
    case closeGhost
    case install(SakuraScriptInstallSource)
    case reloadGhost
    case reloadShell
    case reloadBalloon
    case openConfigurationDialog
    case openReadme
    case openHelp
    case openFile(String)
    case openFolder(String)
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

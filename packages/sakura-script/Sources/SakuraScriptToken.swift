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
    case addAnimation(SakuraScriptAnimationAddition)
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
    case cursorMove(x: SakuraScriptBalloonCoordinate?, y: SakuraScriptBalloonCoordinate?)
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
    case trayBalloon(SakuraScriptTrayBalloon)
    case otherGhostTalkMode(SakuraScriptOtherGhostTalkMode)
    case otherSurfaceChangeNotifications(Bool)
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
    case voiceMode(SakuraScriptVoiceMode)
    case synchronizeScopes([Int]?)
    case onlineMode(Bool)
    case noUserBreakMode(Bool)
    case interactionMode(SakuraScriptInteractionMode, enabled: Bool)
    case selectRectangle(enabled: Bool)
    case collisionMode(enabled: Bool, showsNames: Bool)
    case syncObjectWait(name: String, timeoutMilliseconds: Int?)
    case syncObjectSet(String)
    case syncObjectReset(String)
    case open(String)
    case sound(SakuraScriptSoundCommand)
    case contentAction(SakuraScriptContentAction)
    case componentLifecycle(component: SakuraScriptComponent, loads: Bool)
    case shioriDebugMode(Bool)
    case embeddedEvent(id: String, arguments: [String])
    case raisedEvent(id: String, arguments: [String])
    case notifyEvent(id: String, arguments: [String])
    case otherEvent(target: String, id: String, arguments: [String], reflectsResponse: Bool)
    case pluginEvent(target: String, id: String, arguments: [String], reflectsResponse: Bool)
    case timerEvent(milliseconds: Int, repeats: Bool, reflectsResponse: Bool, id: String, arguments: [String])
    case pluginTimerEvent(target: String, milliseconds: Int, repeats: Bool, reflectsResponse: Bool, id: String, arguments: [String])
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
    case positionedImage(path: String, x: Int, y: Int, isOpaque: Bool, options: [String])
    case otherGhostTalk(target: String, script: String)
    case otherSurfaceChange(target: String, scope: Int, surfaceID: Int)
    case stayOnTop(Bool)
    case closeInputBox(id: String)
    case otherTimerEvent(target: String, milliseconds: Int, repeats: Bool, reflectsResponse: Bool, id: String, arguments: [String])
    case archive(SakuraScriptArchiveCommand)
    case cancelHTTP(url: String?)
    case inputBox(SakuraScriptInputCommand)
    case systemDialog(SakuraScriptSystemDialogCommand)
    case closeSystemDialog(id: String)
    case communicateBox(initialValue: String)
    case teachBox(initialValue: String)
    case http(SakuraScriptHTTPRequest)
    case schedule(SakuraScriptScheduleCommand)
    case fileWatch(SakuraScriptFileWatchCommand)
    case networkDiagnostic(SakuraScriptNetworkDiagnostic)
    case emptyRecycleBin
    case checkMail(account: String?)
    case webSocket(SakuraScriptWebSocketCommand)
    case weatherGet(eventID: String)
    case sntpStart
    case sntpCorrect
    case clear
    case clearAll
    case end
    case unknown(String)
}

public struct SakuraScriptAnimationFrame: Sendable, Equatable {
    public let surfaceID: Int
    public let x: Int
    public let y: Int
    public let durationMilliseconds: Int

    public init(surfaceID: Int, x: Int = 0, y: Int = 0, durationMilliseconds: Int = 0) {
        self.surfaceID = surfaceID
        self.x = x
        self.y = y
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum SakuraScriptAnimationAddition: Sendable, Equatable {
    case surfaces(method: String, frames: [SakuraScriptAnimationFrame], repeats: Bool)
    case move(x: Int, y: Int)
    case text(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        text: String,
        durationMilliseconds: Int,
        color: (red: Int, green: Int, blue: Int),
        fontSize: Int?,
        fontName: String?
    )

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.surfaces(lm, lf, lr), .surfaces(rm, rf, rr)):
            lm == rm && lf == rf && lr == rr
        case let (.move(lx, ly), .move(rx, ry)):
            lx == rx && ly == ry
        case let (.text(lx, ly, lw, lh, lt, ld, lc, ls, ln), .text(rx, ry, rw, rh, rt, rd, rc, rs, rn)):
            lx == rx && ly == ry && lw == rw && lh == rh && lt == rt && ld == rd
                && lc.red == rc.red && lc.green == rc.green && lc.blue == rc.blue
                && ls == rs && ln == rn
        default:
            false
        }
    }
}

public struct SakuraScriptInputCommand: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case text
        case password
        case date
        case slider(minimum: Int, maximum: Int)
        case time
        case ipAddress
    }

    public let kind: Kind
    public let id: String
    public let timeoutMilliseconds: Int?
    public let initialValue: String
    public let maximumLength: Int?
    public let references: [String]
    public let options: [String]
    public let balloonID: Int?

    public init(
        kind: Kind,
        id: String,
        timeoutMilliseconds: Int?,
        initialValue: String,
        maximumLength: Int? = nil,
        references: [String] = [],
        options: [String] = [],
        balloonID: Int? = nil
    ) {
        self.kind = kind
        self.id = id
        self.timeoutMilliseconds = timeoutMilliseconds
        self.initialValue = initialValue
        self.maximumLength = maximumLength
        self.references = references
        self.options = options
        self.balloonID = balloonID
    }

    public var keepsOpenAfterSubmit: Bool {
        kind == .text && options.contains { $0.caseInsensitiveCompare("noclose") == .orderedSame }
    }

    public var keepsValueAfterSubmit: Bool {
        keepsOpenAfterSubmit && options.contains { $0.caseInsensitiveCompare("noclear") == .orderedSame }
    }

    public var supplementalValue: String {
        guard case let .slider(minimum, maximum) = kind else { return "" }
        return "\(minimum),\(maximum)"
    }

    public var inputTypeName: String {
        switch kind {
        case .text: "inputbox"
        case .password: "passwordinput"
        case .date: "dateinput"
        case .slider: "sliderinput"
        case .time: "timeinput"
        case .ipAddress: "ipinput"
        }
    }
}

public enum SakuraScriptComponent: Sendable, Equatable {
    case shiori
    case makoto
}

public enum SakuraScriptOtherGhostTalkMode: Sendable, Equatable {
    case disabled
    case before
    case after
}

public struct SakuraScriptTrayBalloon: Sendable, Equatable {
    public let title: String
    public let text: String
    public let icon: String
    public let timeoutSeconds: Int

    public init(title: String, text: String, icon: String, timeoutSeconds: Int) {
        self.title = title
        self.text = text
        self.icon = icon
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum SakuraScriptVoiceMode: Sendable, Equatable {
    case defaultValue
    case disabled
    case alternate(String)
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

public struct SakuraScriptDumpSurfaceCommand: Sendable, Equatable {
    public let directoryPath: String?
    public let scope: Int
    public let surfaceList: String?
    public let prefix: String
    public let eventID: String?
    public let cropsFromZero: Bool

    public init(
        directoryPath: String? = nil,
        scope: Int = 0,
        surfaceList: String? = nil,
        prefix: String = "surface",
        eventID: String? = nil,
        cropsFromZero: Bool = false
    ) {
        self.directoryPath = directoryPath
        self.scope = scope
        self.surfaceList = surfaceList
        self.prefix = prefix.isEmpty ? "surface" : prefix
        self.eventID = eventID
        self.cropsFromZero = cropsFromZero
    }
}

public enum SakuraScriptArchiveCommand: Sendable, Equatable {
    case extract(archivePath: String, destinationPath: String, eventID: String?, password: String?)
    case compress(archivePath: String, sourceDirectoryPath: String, eventID: String?, password: String?)
    case createNar(narPath: String?, sourceDirectoryPath: String?, eventID: String?)
    case dumpSurface(SakuraScriptDumpSurfaceCommand)
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
    case ping(
        host: String,
        eventID: String,
        count: Int,
        size: Int,
        timeoutMilliseconds: Int,
        ttl: Int?,
        dontFragment: Bool,
        data: String?
    )
    case nslookup(host: String, eventID: String)
}

public enum SakuraScriptScheduleCommand: Sendable, Equatable {
    case add(options: [String: String])
    case delete(uid: String, eventID: String?)
    case get(options: [String: String])
}

public enum SakuraScriptFileWatchCommand: Sendable, Equatable {
    case start(path: String, eventID: String?, debounceMilliseconds: Int)
    case cancel(path: String)
}

public struct SakuraScriptHTTPRequest: Sendable, Equatable {
    public let method: String
    public let url: String
    public let eventID: String?
    public let waitsForCompletion: Bool
    public let parameters: [String]
    public let options: [String]
    public let headers: [String]
    public let timeoutSeconds: Double?
    public let output: SakuraScriptHTTPOutput
    public let isFeed: Bool
    public let isCalendar: Bool
    public let notifiesProgress: Bool
    public let streamingMode: String?

    public init(
        method: String,
        url: String,
        eventID: String?,
        waitsForCompletion: Bool,
        parameters: [String] = [],
        options: [String] = [],
        headers: [String] = [],
        timeoutSeconds: Double? = nil,
        output: SakuraScriptHTTPOutput = .file(nil),
        isFeed: Bool = false,
        isCalendar: Bool = false,
        notifiesProgress: Bool = false,
        streamingMode: String? = nil
    ) {
        self.method = method
        self.url = url
        self.eventID = eventID
        self.waitsForCompletion = waitsForCompletion
        self.parameters = parameters
        self.options = options
        self.headers = headers
        self.timeoutSeconds = timeoutSeconds
        self.output = output
        self.isFeed = isFeed
        self.isCalendar = isCalendar
        self.notifiesProgress = notifiesProgress
        self.streamingMode = streamingMode
    }
}

public enum SakuraScriptHTTPOutput: Sendable, Equatable {
    case file(String?)
    case memory(characterEncoding: String?)
}

public struct SakuraScriptBalloonCoordinate: Sendable, Equatable {
    public enum Unit: Sendable, Equatable {
        case pixel
        case em
        case lineHeight
        case percent
    }

    public let value: Double
    public let isRelative: Bool
    public let unit: Unit

    public init(value: Int, isRelative: Bool) {
        self.value = Double(value)
        self.isRelative = isRelative
        unit = .pixel
    }

    public init(value: Double, isRelative: Bool, unit: Unit) {
        self.value = value
        self.isRelative = isRelative
        self.unit = unit
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
    case changeGhostWithEvent(String)
    case callGhost(String)
    case callGhostWithEvent(String)
    case changeShell(String)
    case changeShellWithEvent(String)
    case changeBalloon(String)
    case changeCalendarSkin(String)
    case updateGhost
    case updateBalloon
    case updatePlatform
    case updateTargets([String])
    case updateOther([String])
    case vanishByMyself(replacement: String?, asksConfirmation: Bool)
    case headline(String)
    case closeGhost
    case install(SakuraScriptInstallSource)
    case reloadGhost
    case reloadShell
    case reloadBalloon
    case reloadShiori
    case reloadMakoto
    case reloadHeadlines
    case reloadPlugins
    case reloadCalendarSkins
    case reloadAIGraph
    case openContentExplorer(String)
    case openDressupExplorer
    case openPictureViewer(String?)
    case openArchiveViewer(String?)
    case openAIGraph
    case setTaskTrayIcon(file: String, tooltip: String?, durationMilliseconds: Int?, runCount: Int?)
    case openDeveloperTool(String)
    case openConfigurationDialog(String?)
    case minimizeWindows
    case saveWallpaper
    case restoreWallpaper
    case setWallpaper(SakuraScriptWallpaperCommand)
    case openReadme
    case openHelp
    case openTerms
    case openFile(String)
    case openFolder(String)
}

public struct SakuraScriptWallpaperCommand: Sendable, Equatable {
    public let file: String?
    public let position: String
    public let color: String?

    public init(file: String?, position: String = "center", color: String? = nil) {
        self.file = file
        self.position = position
        self.color = color
    }
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

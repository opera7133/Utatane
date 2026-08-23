import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript

/// Incremental Wine-free FIRST personality support for the original known DLL.
/// Unsupported events intentionally return nil while their native behavior is reconstructed.
public actor NativeFirstPersonalityEngine: PersonalityEngine {
    private enum ActivityState {
        case normal
        case drowsy
        case sleeping
        case bathing
    }

    private let session: FirstNativeSession
    private let stateStore: FirstNativeStateStore
    private var sakuraBustClickCount = 0
    private var activityState = ActivityState.normal
    private var secondsSinceTalk = 0
    private var randomTalkSeconds = 0
    private var sleepingPokesRemaining = 0
    private var bathingSecondsRemaining = 0
    private var didBatheThisSession = false
    private var energy: Int

    public init(masterDirectoryURL: URL) throws {
        let loadedSession = try FirstNativeSession(masterDirectoryURL: masterDirectoryURL)
        let loadedStateStore = FirstNativeStateStore(masterDirectoryURL: masterDirectoryURL)
        let persistentState = loadedStateStore.load()
        session = loadedSession
        stateStore = loadedStateStore
        energy = persistentState?.energy ?? loadedSession.energy
        didBatheThisSession = persistentState?.lastBathDate.map(Calendar.current.isDateInToday) ?? false
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        FirstNativeSession.supports(masterDirectoryURL: masterDirectoryURL)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        if case let .ghostChanging(name) = event {
            persistState()
            return try normalized(session.ghostChangingScript(
                name: name,
                isSleeping: activityState == .sleeping,
                isBathing: activityState == .bathing,
                fallbackChoice: Int.random(in: 0 ..< 2)
            ))
        }
        if case let .choice(id, _) = event,
           let script = try session.firstMenuChoiceScript(id: id, energy: energy)
        {
            return normalized(script)
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnSecondChange") == .orderedSame
        {
            return try handleSecondChange(canTalk: references[3] != "0")
        }
        if let mouse = doubleClick(from: event) {
            if mouse.scope == 0 {
                switch activityState {
                case .drowsy:
                    activityState = .normal
                    secondsSinceTalk = 0
                    return try normalized(session.wakeFromDrowsyScript())
                case .sleeping:
                    sleepingPokesRemaining -= 1
                    if sleepingPokesRemaining <= 0 {
                        activityState = .normal
                        secondsSinceTalk = 0
                        energy = min(360, energy + 3)
                        persistState()
                        return try normalized(session.wakeFromSleepScript(choice: Int.random(in: 0 ..< 4)))
                    }
                    return try normalized(session.sleepingPokeScript(choice: Int.random(in: 0 ..< 6)))
                case .bathing:
                    return try normalized(session.sakuraBathingDoubleClickScript())
                case .normal:
                    break
                }
            } else if mouse.scope == 1 {
                switch activityState {
                case .sleeping:
                    return try normalized(session.keroSleepingDoubleClickMenuScript())
                case .bathing:
                    return try normalized(session.keroBathingDoubleClickMenuScript())
                case .normal, .drowsy:
                    break
                }
            }
        }
        if let mouse = mouseClick(from: event),
           mouse.scope == 0,
           mouse.region?.caseInsensitiveCompare("bust") == .orderedSame
        {
            sakuraBustClickCount += 1
            return try normalized(session.sakuraBustClickScript(clickCount: sakuraBustClickCount))
        }
        if case let .mouse(mouse) = event, mouse.kind == .doubleClick {
            sakuraBustClickCount = 0
        }

        let request: (id: String, references: [Int: String])? = switch event {
        case .boot:
            ("OnBoot", [:])
        case .randomTalk:
            ("OnAITalk", [:])
        case .close:
            ("OnClose", [:])
        case let .mouse(mouse) where mouse.kind == .doubleClick:
            ("OnMouseDoubleClick", [3: String(mouse.scope), 4: mouse.region].compactMapValues { $0 })
        case let .choice(id, arguments):
            if id.hasPrefix("On") {
                (id, Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                    ($0.offset, $0.element)
                }))
            } else {
                ("OnChoiceSelect", Dictionary(uniqueKeysWithValues: ([id] + arguments).enumerated().map {
                    ($0.offset, $0.element)
                }))
            }
        case let .shiori(id, references):
            (id, references)
        default:
            nil
        }
        guard let request,
              let rawScript = try session.script(forEventID: request.id, references: request.references),
              !rawScript.isEmpty
        else {
            return nil
        }
        if request.id.caseInsensitiveCompare("OnAITalk") == .orderedSame {
            secondsSinceTalk = 0
            randomTalkSeconds = 0
            activityState = .normal
        }
        return normalized(rawScript)
    }

    private func handleSecondChange(canTalk: Bool) throws -> SakuraScript? {
        guard canTalk else { return nil }
        secondsSinceTalk += 1
        randomTalkSeconds += 1
        if activityState == .bathing {
            bathingSecondsRemaining -= 1
            guard bathingSecondsRemaining <= 0 else { return nil }
            activityState = .normal
            secondsSinceTalk = 0
            energy = min(360, energy + 50)
            persistState(lastBathDate: Date())
            return try normalized(session.returnFromBathScript(choice: Int.random(in: 0 ..< 2)))
        }
        let interval = idleInterval(forEnergy: energy)
        switch activityState {
        case .normal where secondsSinceTalk >= interval:
            activityState = .drowsy
            return try normalized(session.drowsyTransitionScript(choice: Int.random(in: 0 ..< 4)))
        case .drowsy where secondsSinceTalk >= interval + 30:
            activityState = .sleeping
            sleepingPokesRemaining = Int.random(in: 2 ... 3)
            return try normalized(session.sleepTransitionScript(choice: Int.random(in: 0 ..< 3)))
        default:
            break
        }
        let hour = Calendar.current.component(.hour, from: Date())
        let isBathTime = hour >= 21 || hour <= 5
        if !didBatheThisSession,
           activityState != .sleeping,
           secondsSinceTalk >= 1350,
           isBathTime
        {
            activityState = .bathing
            didBatheThisSession = true
            bathingSecondsRemaining = Int.random(in: 10 ..< 20) * 60
            return try normalized(session.bathTransitionScript())
        }
        guard activityState == .normal,
              randomTalkSeconds >= session.masterTalkIntervalSeconds
        else { return nil }
        randomTalkSeconds = 0
        secondsSinceTalk = 0
        return try normalized(session.randomTalkScript(choice: Int.random(in: 0 ..< 34)))
    }

    private func idleInterval(forEnergy energy: Int) -> Int {
        switch energy {
        case ...30: 30
        case ...120: 900
        case ...240: 1800
        default: 3600
        }
    }

    private func persistState(lastBathDate: Date? = nil) {
        let previousBathDate = stateStore.load()?.lastBathDate
        try? stateStore.save(FirstNativePersistentState(
            energy: energy,
            lastBathDate: lastBathDate ?? previousBathDate
        ))
    }

    private func normalized(_ rawScript: String) -> SakuraScript {
        SakuraScript(rawValue: LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(in: rawScript))
    }

    private func mouseClick(from event: GhostEvent) -> (scope: Int, region: String?)? {
        switch event {
        case let .mouseClick(scope, region):
            (scope, region)
        case let .mouse(mouse) where mouse.kind == .click:
            (mouse.scope, mouse.region)
        default:
            nil
        }
    }

    private func doubleClick(from event: GhostEvent) -> (scope: Int, region: String?)? {
        guard case let .mouse(mouse) = event, mouse.kind == .doubleClick else { return nil }
        return (mouse.scope, mouse.region)
    }
}

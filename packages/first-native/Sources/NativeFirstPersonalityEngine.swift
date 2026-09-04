import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript

/// Incremental Wine-free FIRST personality support for the original known DLL.
/// Unsupported events intentionally return nil while their native behavior is reconstructed.
public actor NativeFirstPersonalityEngine: PersonalityEngine {
    enum ActivityState {
        case normal
        case drowsy
        case sleeping
        case bathing
    }

    enum WindowRestoreAction: Equatable {
        case sleeping(shortAbsence: Bool)
        case drowsy
        case bathing
        case normalShortAbsence
        case sleepTransition
        case randomTalk
    }

    enum CloseAction: Equatable {
        case normal(elapsedSeconds: TimeInterval)
        case sleeping
        case bathing
        case noResponse
    }

    private let session: FirstNativeSession
    private let stateStore: FirstNativeStateStore
    private let now: @Sendable () -> Date
    private let materializedAt: Date
    private var sakuraBustClickCount = 0
    private var activityState = ActivityState.normal
    private var secondsSinceTalk = 0
    private var randomTalkSeconds = 0
    private var sleepingPokesRemaining = 0
    private var bathingSecondsRemaining = 0
    private var isMinimized = false
    private var minimizedAt: Date?
    private var lastBathDate: Date?
    private var lastUpdateDate: Date?
    private var energy: Int
    private var quizCategory: Int?
    private var quizQuestion: FirstQuizQuestion?
    private var typingLevel: Int?
    private var typingAttempt = 0
    private var typingCorrectCount = 0
    private var typingTotalMilliseconds = 0
    private var typingQuestion: FirstTypingQuestion?
    private var typingQuestionStartedAt: Date?
    private var typingRecords: [FirstTypingRecord?]

    public init(
        masterDirectoryURL: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        stateRootURL: URL? = nil
    ) throws {
        let loadedSession = try FirstNativeSession(masterDirectoryURL: masterDirectoryURL)
        let loadedStateStore = FirstNativeStateStore(
            masterDirectoryURL: masterDirectoryURL,
            stateRootURL: stateRootURL
        )
        let persistentState = loadedStateStore.load()
        session = loadedSession
        stateStore = loadedStateStore
        self.now = now
        materializedAt = now()
        energy = persistentState?.energy ?? loadedSession.energy
        lastBathDate = persistentState?.lastBathDate
        lastUpdateDate = persistentState?.lastUpdateDate
        typingRecords = Self.normalizedTypingRecords(persistentState?.typingRecords)
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        FirstNativeSession.supports(masterDirectoryURL: masterDirectoryURL)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        if case .close = event {
            persistState()
            switch Self.closeAction(
                state: activityState,
                elapsedSeconds: max(0, now().timeIntervalSince(materializedAt))
            ) {
            case let .normal(elapsedSeconds):
                return try normalized(session.onCloseScript(
                    elapsedSeconds: elapsedSeconds,
                    choice: Int.random(in: 0 ..< 2)
                ))
            case .sleeping:
                return try normalized(session.sleepingCloseScript())
            case .bathing:
                return try normalized(session.bathingCloseScript())
            case .noResponse:
                return nil
            }
        }
        if case let .ghostChanging(name) = event {
            persistState()
            return try normalized(session.ghostChangingScript(
                name: name,
                isSleeping: activityState == .sleeping,
                isBathing: activityState == .bathing,
                fallbackChoice: Int.random(in: 0 ..< 2)
            ))
        }
        if case let .choice(id, arguments) = event,
           id.caseInsensitiveCompare("OnQuizStart") == .orderedSame,
           let category = arguments.first.flatMap(Int.init),
           0 ..< 6 ~= category
        {
            quizCategory = category
            quizQuestion = nil
            return try normalized(session.quizStartScript(category: category))
        }
        if case let .choice(id, arguments) = event,
           id.caseInsensitiveCompare("OnQuizEnter") == .orderedSame
        {
            quizCategory = nil
            quizQuestion = nil
            return try normalized(session.quizEnterScript(reference: arguments.first))
        }
        if case let .choice(id, _) = event,
           id.caseInsensitiveCompare("OnQuizLeave") == .orderedSame
        {
            quizCategory = nil
            quizQuestion = nil
            return try normalized(session.quizLeaveScript())
        }
        if case let .choice(id, arguments) = event,
           id.caseInsensitiveCompare("OnTypinggameStart") == .orderedSame,
           let level = arguments.first.flatMap(Int.init),
           0 ..< 3 ~= level
        {
            resetTypingGame(level: level)
            return try normalized(session.typingGameStartScript(level: level))
        }
        if case let .choice(id, arguments) = event,
           id.caseInsensitiveCompare("OnTypinggameEnter") == .orderedSame
        {
            resetTypingGame()
            return try normalized(session.typingGameEnterScript(
                reference: arguments.first,
                records: typingRecords
            ))
        }
        if case let .choice(id, _) = event,
           id.caseInsensitiveCompare("OnTypinggameTutorial") == .orderedSame
        {
            return try normalized(session.typingGameTutorialScript())
        }
        if case let .choice(id, _) = event,
           id.caseInsensitiveCompare("OnTypinggameLeave") == .orderedSame
        {
            resetTypingGame()
            return try normalized(session.typingGameLeaveScript())
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
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnMinuteChange") == .orderedSame
        {
            handleMinuteChange()
            return nil
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnWindowStateMinimize") == .orderedSame
        {
            isMinimized = true
            minimizedAt = now()
            return nil
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnWindowStateRestore") == .orderedSame
        {
            isMinimized = false
            let absence = minimizedAt.map { max(0, now().timeIntervalSince($0)) } ?? 0
            minimizedAt = nil
            sakuraBustClickCount = 0
            switch Self.windowRestoreAction(
                state: activityState,
                minimizedSeconds: absence,
                energy: energy,
                secondsSinceTalk: secondsSinceTalk
            ) {
            case let .sleeping(shortAbsence):
                return try normalized(session.windowRestoreSleepingScript(shortAbsence: shortAbsence))
            case .drowsy:
                return try normalized(session.windowRestoreDrowsyScript())
            case .bathing:
                return try normalized(session.windowRestoreBathingScript())
            case .normalShortAbsence:
                return try normalized(session.windowRestoreNormalShortAbsenceScript())
            case .sleepTransition:
                activityState = .sleeping
                sleepingPokesRemaining = Int.random(in: 2 ... 3)
                return try normalized(session.windowRestoreSleepTransitionScript())
            case .randomTalk:
                secondsSinceTalk = 0
                randomTalkSeconds = 0
                return try normalized(session.randomTalkScript(choice: Int.random(in: 0 ..< 34)))
            }
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnSurfaceRestore") == .orderedSame
        {
            switch activityState {
            case .sleeping:
                return try normalized(session.sleepingSurfaceRestoreScript())
            case .bathing:
                return try normalized(session.bathingSurfaceRestoreScript())
            case .drowsy:
                return nil
            case .normal:
                return try normalized(session.normalSurfaceRestoreScript())
            }
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnSNTPBegin") == .orderedSame
        {
            return try normalized(session.sntpBeginScript(
                server: references[0] ?? "",
                persistedLastUpdateDate: lastUpdateDate,
                at: now()
            ))
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnUpdateComplete") == .orderedSame
        {
            let script = try session.updateCompleteScript(result: references[0])
            lastUpdateDate = now()
            persistState()
            return normalized(script)
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnQuizStart") == .orderedSame,
           let category = references[0].flatMap(Int.init),
           0 ..< 6 ~= category
        {
            quizCategory = category
            quizQuestion = nil
            return try normalized(session.quizStartScript(category: category))
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnQuizEnter") == .orderedSame
        {
            quizCategory = nil
            quizQuestion = nil
            return try normalized(session.quizEnterScript(reference: references[0]))
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnQuizNext") == .orderedSame,
           let category = quizCategory
        {
            let question = try session.quizQuestion(category: category)
            quizQuestion = question
            return normalized(question.script)
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnQuizInput") == .orderedSame,
           let question = quizQuestion
        {
            quizQuestion = nil
            return try normalized(session.quizInputScript(
                answer: references[0] ?? "",
                question: question,
                feedbackChoice: Int.random(in: 0 ..< 2)
            ))
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnUserInputCancel") == .orderedSame,
           references[0]?.caseInsensitiveCompare("OnQuizInput") == .orderedSame,
           let question = quizQuestion
        {
            quizQuestion = nil
            return try normalized(session.quizInputScript(
                answer: "",
                question: question,
                feedbackChoice: 0
            ))
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnQuizLeave") == .orderedSame
        {
            quizCategory = nil
            quizQuestion = nil
            return try normalized(session.quizLeaveScript())
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnTypinggameEnter") == .orderedSame
        {
            resetTypingGame()
            return try normalized(session.typingGameEnterScript(
                reference: references[0],
                records: typingRecords
            ))
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnTypinggameStart") == .orderedSame,
           let level = references[0].flatMap(Int.init),
           0 ..< 3 ~= level
        {
            resetTypingGame(level: level)
            return try normalized(session.typingGameStartScript(level: level))
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnTypinggameNext") == .orderedSame,
           let level = typingLevel,
           typingAttempt < 10
        {
            let question = try session.typingGameQuestion(
                level: level,
                attempt: typingAttempt,
                totalMilliseconds: typingTotalMilliseconds
            )
            typingQuestion = question
            typingQuestionStartedAt = now()
            return normalized(question.script)
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnTypinggameInput") == .orderedSame,
           let question = typingQuestion
        {
            return try handleTypingGameInput(answer: references[0] ?? "", question: question)
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnUserInputCancel") == .orderedSame,
           references[0]?.caseInsensitiveCompare("OnTypinggameInput") == .orderedSame,
           let question = typingQuestion
        {
            return try handleTypingGameInput(answer: "", question: question)
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnTypinggameTutorial") == .orderedSame
        {
            return try normalized(session.typingGameTutorialScript())
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnTypinggameLeave") == .orderedSame
        {
            resetTypingGame()
            return try normalized(session.typingGameLeaveScript())
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnGoogle") == .orderedSame
        {
            return try normalized(session.googleSearchScript(
                query: references[0] ?? "",
                choice: Int.random(in: 0 ..< 2)
            ))
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnHeadlinesenseFailure") == .orderedSame
        {
            guard let script = try session.headlineFailureScript(
                reason: references[0],
                isBathing: activityState == .bathing
            ) else { return nil }
            return normalized(script)
        }
        if case let .shiori(id, _) = event,
           id.caseInsensitiveCompare("OnHeadlinesenseComplete") == .orderedSame
        {
            return try normalized(session.headlineCompleteScript(isBathing: activityState == .bathing))
        }
        if case let .shiori(id, references) = event,
           id.caseInsensitiveCompare("OnHeadlinesenseBegin") == .orderedSame
        {
            return try normalized(session.headlineBeginScript(
                name: references[0] ?? "",
                isBathing: activityState == .bathing
            ))
        }
        if case let .shiori(id, _) = event {
            if id.caseInsensitiveCompare("On_debug_houchi1200") == .orderedSame {
                secondsSinceTalk += 1200
            } else if id.caseInsensitiveCompare("On_debug_furo") == .orderedSame {
                activityState = .bathing
                bathingSecondsRemaining = Int.random(in: 10 ..< 20) * 60
                return try normalized(session.bathTransitionScript())
            } else if id.caseInsensitiveCompare("On_debug_nemuku") == .orderedSame {
                energy = 0
                persistState()
            } else if id.caseInsensitiveCompare("On_debug_nemukunai") == .orderedSame {
                energy = 360
                persistState()
            }
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
            lastBathDate = now()
            persistState()
            return try normalized(session.returnFromBathScript(choice: Int.random(in: 0 ..< 2)))
        }
        let interval = Self.idleInterval(forEnergy: energy)
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
        let currentDate = now()
        let hour = Calendar.current.component(.hour, from: currentDate)
        let isBathTime = hour >= 21 || hour <= 5
        if canBathe(at: currentDate),
           activityState != .sleeping,
           secondsSinceTalk >= 1350,
           isBathTime
        {
            activityState = .bathing
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

    private func handleMinuteChange() {
        energy = Self.energyAfterMinute(
            energy,
            state: activityState,
            isMinimized: isMinimized
        )
        if activityState == .sleeping {
            sleepingPokesRemaining = Self.sleepingPokesAfterMinute(sleepingPokesRemaining)
        }
        persistState()
    }

    private func canBathe(at date: Date) -> Bool {
        Self.canBathe(lastBathDate: lastBathDate, at: date)
    }

    static func energyAfterMinute(
        _ energy: Int,
        state: ActivityState,
        isMinimized: Bool = false
    ) -> Int {
        switch state {
        case .normal, .drowsy:
            isMinimized ? energy : max(0, energy - 1)
        case .sleeping:
            min(360, energy + 3)
        case .bathing:
            energy
        }
    }

    static func sleepingPokesAfterMinute(_ current: Int) -> Int {
        min(4, current + 1)
    }

    static func windowRestoreAction(
        state: ActivityState,
        minimizedSeconds: TimeInterval,
        energy: Int,
        secondsSinceTalk: Int
    ) -> WindowRestoreAction {
        switch state {
        case .sleeping:
            .sleeping(shortAbsence: minimizedSeconds < 120)
        case .drowsy:
            .drowsy
        case .bathing:
            .bathing
        case .normal where minimizedSeconds < 120:
            .normalShortAbsence
        case .normal:
            idleInterval(forEnergy: energy) <= secondsSinceTalk ? .sleepTransition : .randomTalk
        }
    }

    static func closeAction(state: ActivityState, elapsedSeconds: TimeInterval) -> CloseAction {
        switch state {
        case .normal:
            .normal(elapsedSeconds: elapsedSeconds)
        case .sleeping:
            .sleeping
        case .bathing:
            .bathing
        case .drowsy:
            .noResponse
        }
    }

    static func canBathe(lastBathDate: Date?, at date: Date) -> Bool {
        guard let lastBathDate else { return true }
        return date.timeIntervalSince(lastBathDate) >= 12 * 60 * 60
    }

    private static func idleInterval(forEnergy energy: Int) -> Int {
        switch energy {
        case ...30: 30
        case ...120: 900
        case ...240: 1800
        default: 3600
        }
    }

    private func persistState() {
        try? stateStore.save(FirstNativePersistentState(
            energy: energy,
            lastBathDate: lastBathDate,
            lastUpdateDate: lastUpdateDate,
            typingRecords: typingRecords
        ))
    }

    private func normalized(_ rawScript: String) -> SakuraScript {
        SakuraScript(rawValue: Self.normalizeFIRSTScript(rawScript))
    }

    private func resetTypingGame(level: Int? = nil) {
        typingLevel = level
        typingAttempt = 0
        typingCorrectCount = 0
        typingTotalMilliseconds = 0
        typingQuestion = nil
        typingQuestionStartedAt = nil
    }

    private func handleTypingGameInput(
        answer: String,
        question: FirstTypingQuestion
    ) throws -> SakuraScript {
        let isCorrect = answer.caseInsensitiveCompare(question.expectedAnswer) == .orderedSame
        if isCorrect {
            let elapsed = typingQuestionStartedAt.map { max(0, now().timeIntervalSince($0)) } ?? 0
            typingTotalMilliseconds += min(15000, Int(elapsed * 1000))
            typingCorrectCount += 1
        } else {
            typingTotalMilliseconds += 15000
        }
        typingAttempt += 1
        typingQuestion = nil
        typingQuestionStartedAt = nil
        let script = try session.typingGameInputScript(
            answer: answer,
            question: question,
            correctCount: typingCorrectCount,
            totalMilliseconds: typingTotalMilliseconds,
            feedbackChoice: Int.random(in: 0 ..< 2)
        )
        if typingAttempt == 10 {
            updateTypingRecord(level: question.level)
            typingLevel = nil
        }
        return normalized(script)
    }

    private func updateTypingRecord(level: Int) {
        guard typingRecords.indices.contains(level) else { return }
        let candidate = FirstTypingRecord(
            correctCount: typingCorrectCount,
            totalMilliseconds: typingTotalMilliseconds
        )
        if !Self.shouldReplaceTypingRecord(typingRecords[level], with: candidate) {
            return
        }
        typingRecords[level] = candidate
        persistState()
    }

    private static func normalizedTypingRecords(_ records: [FirstTypingRecord?]?) -> [FirstTypingRecord?] {
        Array((records ?? []).prefix(3)) + Array(repeating: nil, count: max(0, 3 - (records?.count ?? 0)))
    }

    static func shouldReplaceTypingRecord(
        _ previous: FirstTypingRecord?,
        with candidate: FirstTypingRecord
    ) -> Bool {
        guard let previous else { return true }
        return candidate.correctCount > previous.correctCount ||
            (candidate.correctCount == previous.correctCount &&
                candidate.totalMilliseconds < previous.totalMilliseconds)
    }

    static func normalizeFIRSTScript(_ rawScript: String) -> String {
        let withoutStallingInductionMode = rawScript
            .replacingOccurrences(of: "\\![enter,inductionmode]", with: "")
            .replacingOccurrences(of: "\\![leave,inductionmode]", with: "")
        return LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(
            in: withoutStallingInductionMode
        )
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

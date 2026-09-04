import Foundation

public enum FirstNativeSessionError: LocalizedError, Equatable, Sendable {
    case missingDLL(URL)

    public var errorDescription: String? {
        switch self {
        case let .missingDLL(url):
            "FIRSTのDLLが見つからない: \(url.path)"
        }
    }
}

struct FirstQuizQuestion: Equatable, Sendable {
    let category: Int
    let script: String
    let acceptedAnswers: [String]
}

struct FirstTypingQuestion: Equatable, Sendable {
    let level: Int
    let attempt: Int
    let script: String
    let expectedAnswer: String
}

/// A Wine-free, read-only session over files supplied by the user.
///
/// Event coverage is deliberately incremental. Unsupported events return nil so
/// callers can keep using the existing compatibility host until native parity is
/// sufficient to switch the application over.
public struct FirstNativeSession: Sendable {
    private let analyzer: FirstDLLAnalyzer
    private let records: [FirstAITXTRecord]
    private let strings: [UInt32: String]
    private let masterDirectoryURL: URL
    private let materializedAt: Date
    private let lastUpdateDate: Date?
    public let masterTalkIntervalSeconds: Int
    public let energy: Int

    public init(masterDirectoryURL: URL) throws {
        let dll = masterDirectoryURL.appending(path: "first.dll")
        guard FileManager.default.fileExists(atPath: dll.path) else {
            throw FirstNativeSessionError.missingDLL(dll)
        }
        analyzer = try FirstDLLAnalyzer(contentsOf: dll)
        _ = try analyzer.fragments(for: .onBoot)
        records = try analyzer.decodedAITXTRecords()
        strings = try analyzer.knownStringsByVirtualAddress()
        self.masterDirectoryURL = masterDirectoryURL
        materializedAt = Date()
        let variables = Self.readVariables(
            at: masterDirectoryURL.appending(path: "var/first.txt")
        )
        lastUpdateDate = Self.date(fromCommaSeparatedComponents: variables["lastupdatedate"])
        masterTalkIntervalSeconds = max(1, Int(variables["mastertalkinterval"] ?? "") ?? 180)
        energy = min(360, max(0, Int(variables["energy"] ?? "") ?? 360))
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        (try? FirstNativeSession(masterDirectoryURL: masterDirectoryURL)) != nil
    }

    private static func readVariables(at url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return Dictionary(contents.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            return (fields[0].lowercased(), String(fields[1]))
        }, uniquingKeysWith: { _, latest in latest })
    }

    public func script(forEventID eventID: String, references: [Int: String] = [:]) throws -> String? {
        switch eventID.lowercased() {
        case "onboot":
            try onBootScript(
                hour: Calendar.current.component(.hour, from: Date()),
                topLevelChoice: Int.random(in: 0 ..< 8),
                midnightChoice: Int.random(in: 0 ..< 13),
                day: Calendar.current.component(.day, from: Date()),
                scheduleKindChoice: Int.random(in: 0 ..< 3),
                scheduleTemplateChoice: Int.random(in: 0 ..< 4),
                generatedScheduleChoices: [
                    Int.random(in: 0 ..< 7),
                    Int.random(in: 0 ..< 6),
                    Int.random(in: 0 ..< 7),
                    Int.random(in: 0 ..< 4),
                    Int.random(in: 0 ..< 5),
                    Int.random(in: 10 ..< 20)
                ]
            )
        case "onfirstboot":
            try firstBootScript()
        case "onaitalk":
            try randomTalkScript(choice: Int.random(in: Self.randomTalkAddresses.indices))
        case "onmousedoubleclick":
            switch references[3] {
            case "0":
                try sakuraDoubleClickMenuScript(
                    region: references[4],
                    faceReactionChoice: Int.random(in: 0 ..< 2)
                )
            case "1":
                try keroDoubleClickScript(choice: Int.random(in: 0 ..< 7))
            default:
                nil
            }
        case "onsurfacerestore":
            try normalSurfaceRestoreScript()
        case "onchoiceselect":
            choiceScript(id: references[0])
        case "on_update":
            try knownString(at: 0x0048_3858)
        case "onchoicetimeout":
            try choiceTimeoutScript(choice: Int.random(in: 0 ..< 2))
        case "onclose":
            try onCloseScript(
                elapsedSeconds: Date().timeIntervalSince(materializedAt),
                choice: Int.random(in: 0 ..< 2)
            )
        case "onsstpbreak":
            try knownScript(at: 0x0048_628C)
        case "onballoonchange":
            try balloonChangeScript(name: references[0] ?? "")
        case "onshellchanging":
            try shellChangingScript(name: references[0] ?? "")
        case "onghostchanged":
            try ghostChangedScript(
                name: references[0],
                previousScript: references[1],
                hildrChoice: Int.random(in: 0 ..< 3)
            )
        case "onvanishselected":
            try knownScript(at: 0x0047_D3EC)
        case "onvanishselecting":
            try knownScript(at: 0x0047_D44C)
        case "onvanished":
            try knownScript(at: 0x0047_D474)
        case "onupdatedatacreating":
            try knownScript(at: 0x0047_D4FC)
        case "onupdatedatacreated":
            try knownScript(at: 0x0047_D540)
        case "oninstallfailure":
            try installFailureScript(reason: references[0])
        case "oninstallrefuse":
            try installRefuseScript(
                name: references[0] ?? "",
                consequenceChoice: Int.random(in: 0 ..< 2)
            )
        case "onanchorselect":
            try anchorSelectScript(
                id: references[0],
                itaruChoice: Int.random(in: 0 ..< 2)
            )
        case "onsstpblacklisting":
            try knownScript(at: 0x0047_D8D8)
        case "onupdatebegin":
            try knownScript(at: 0x0047_DBE0)
        case "onupdate.ondownloadbegin":
            try updateDownloadBeginScript(
                path: references[0] ?? "",
                choice: Int.random(in: 0 ..< 6)
            )
        case "onupdate.onmd5comparebegin":
            try updateMD5CompareBeginScript(path: references[0] ?? "")
        case "onupdate.onmd5comparecomplete":
            try updateMD5CompareResultScript(
                localMD5: references[2] ?? "",
                remoteMD5: references[1] ?? "",
                matches: true
            )
        case "onupdate.onmd5comparefailure":
            try updateMD5CompareResultScript(
                localMD5: references[2] ?? "",
                remoteMD5: references[1] ?? "",
                matches: false
            )
        case "onupdatecomplete":
            try updateCompleteScript(result: references[0])
        case "onupdatefailure":
            try updateFailureScript(reason: references[0], requiredVersion: references[1])
        case "onnetworkheavy":
            try knownScript(at: 0x0047_DED0)
        case "onsntpfailure":
            try knownScript(at: 0x0047_E0B8)
        case "onsntpbegin":
            try sntpBeginScript(
                server: references[0] ?? "",
                daysSinceLastUpdate: daysSinceLastUpdate(at: Date())
            )
        case "onsntpcompare":
            try sntpCompareScript(
                serverComponents: references[1],
                localComponents: references[2],
                offsetSeconds: references[3]
            )
        case "onbifffailure":
            try biffFailureScript(reason: references[0], detail: references[2])
        case "onbiffbegin":
            try biffBeginScript(detail: references[2], choice: Int.random(in: 0 ..< 2))
        case "onbiffcomplete":
            try biffCompleteScript(messageCount: references[0])
        case "onquiztutorial":
            try quizTutorialScript()
        case "onquizenter":
            try quizEnterScript(reference: references[0])
        case "onquizleave":
            try quizLeaveScript()
        case "ongoogle":
            try googleSearchScript(query: references[0] ?? "", choice: Int.random(in: 0 ..< 2))
        case "ontypinggameenter":
            try typingGameEnterScript(reference: references[0])
        case "ontypinggametutorial":
            try typingGameTutorialScript()
        case "ontypinggameleave":
            try typingGameLeaveScript()
        case "on_biff":
            try knownString(at: 0x0048_3874)
        case "oninstallbegin":
            try knownScript(at: 0x0047_E380)
        case "oninstallcomplete":
            try installCompleteScript(type: references[0], name: references[1] ?? "")
        case "on_refreshmemory":
            try refreshMemoryScript()
        case "on_refreshmemoryexecute":
            try refreshMemoryCompleteScript()
        case "on_ip":
            try knownScript(at: 0x0047_EEF4)
        case "on_ip_got":
            try ipResultScript(ipAddress: loadedIPAddress())
        case "on_debug_reloadsurface":
            try knownString(at: 0x0048_46C0)
        case "on_debug":
            try debugMenuScript()
        case "on_debug_houchi1200":
            try knownScript(at: 0x0048_46F8)
        case "on_debug_nemuku":
            try knownScript(at: 0x0048_4750)
        case "on_debug_nemukunai":
            try knownScript(at: 0x0048_4820)
        case "onurldropping":
            try urlDroppingScript(choice: Int.random(in: 0 ..< 2))
        case "onwallpaperchange":
            try knownScript(at: 0x0048_64B0)
        case "on_exitwindows":
            try exitWindowsPromptScript()
        case "on_rebootwindows":
            try rebootWindowsPromptScript()
        case "on_portal":
            try portalMenuScript()
        case "on_portalselected":
            try portalSelectedScript(id: references[0])
        case "on_recommend":
            try recommendMenuScript()
        case "on_recommendselected":
            try recommendSelectedScript(id: references[0])
        default:
            nil
        }
    }

    public func balloonChangeScript(name: String) throws -> String {
        try knownString(at: 0x0048_4F70) + name + knownString(at: 0x0048_4F80)
    }

    public func shellChangingScript(name: String) throws -> String {
        let primaryName = try knownString(at: 0x0048_7108)
        if name == primaryName {
            return try knownScript(at: 0x0048_711C)
        }
        let relatedNames = try [0x0048_7140, 0x0048_7158, 0x0048_7170].map(knownString(at:))
        return try knownScript(at: relatedNames.contains(name) ? 0x0048_7184 : 0x0048_71A8)
    }

    func quizStartScript(category: Int) throws -> String {
        guard 0 ..< 6 ~= category else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(category)
        }
        return try knownScript(at: 0x0047_C0A8)
    }

    func quizEnterScript(reference: String?) throws -> String {
        let returning = try reference?.caseInsensitiveCompare(knownString(at: 0x0047_C760)) == .orderedSame
        var script = try knownString(at: returning ? 0x0047_C770 : 0x0047_C7A8) +
            knownString(at: 0x0047_C840) + knownString(at: 0x0047_C868)
        for category in 0 ..< 6 {
            script += try knownString(at: 0x0047_C87C) + String(category + 1) +
                knownString(at: 0x0047_C890) + String(category) +
                knownString(at: 0x0047_C8A8) + knownString(at: 0x0047_AE7C)
        }
        return try script + knownString(at: 0x0047_C868) + knownString(at: 0x0047_C8C8)
    }

    /// Reconstructs FIRST's six built-in quiz questions. Each answer is stored
    /// in the DLL as reversed hexadecimal CP932 bytes.
    func quizQuestion(category: Int) throws -> FirstQuizQuestion {
        guard 0 ..< 6 ~= category else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(category)
        }
        let layouts: [(answers: [UInt32], scripts: [UInt32])] = [
            ([0x0047_C124], [0x0047_C148]),
            ([0x0047_C190], [0x0047_C1DC]),
            ([0x0047_C2BC], [0x0047_C2E8]),
            ([0x0047_C32C], [0x0047_C364, 0x0047_C438]),
            ([0x0047_C4A8], [0x0047_C4BC]),
            ([0x0047_C500, 0x0047_C550, 0x0047_C5A0], [0x0047_C5E8, 0x0047_C664])
        ]
        let layout = layouts[category]
        let answers = try layout.answers.map { try decodedQuizAnswer(at: $0) }
        let question = try layout.scripts.map(knownString(at:)).joined()
        // Category 3 assigns a self-contained question fragment; the other
        // branches append to the shared numbered prefix.
        let body = try category == 3 ? question :
            knownString(at: 0x0047_C0FC) + String(category + 1) +
            knownString(at: 0x0047_C10C) + question
        let inputBoxPrefix = try knownString(at: 0x0047_C6E0)
            .replacingOccurrences(of: "\\![raise,OnOpenquizInputBox]", with: "")
        let script = try body + inputBoxPrefix + "30000" + knownString(at: 0x0047_C724)
        return FirstQuizQuestion(category: category, script: script, acceptedAnswers: answers)
    }

    func quizInputScript(answer: String, question: FirstQuizQuestion, feedbackChoice: Int) throws -> String {
        let isCorrect = question.acceptedAnswers.contains {
            $0.caseInsensitiveCompare(answer) == .orderedSame
        }
        if isCorrect {
            guard 0 ..< 2 ~= feedbackChoice else {
                throw FirstDLLAnalysisError.invalidAITXTChoice(feedbackChoice)
            }
            return try knownString(at: feedbackChoice == 0 ? 0x0047_BE7C : 0x0047_BE9C) +
                knownString(at: 0x0047_BEC0) + knownString(at: 0x0047_BEDC) +
                String(question.category + 1) + knownString(at: 0x0047_BF14) +
                knownString(at: 0x0047_C068)
        }
        let response: String = if answer.isEmpty {
            try knownString(at: 0x0047_BF58)
        } else if try answer.caseInsensitiveCompare(knownString(at: 0x0047_BF94)) == .orderedSame {
            try knownString(at: 0x0047_BFA4)
        } else if answer.lengthOfBytes(using: .shiftJIS) < 8 {
            try knownString(at: 0x0047_BFE0) + answer + knownString(at: 0x0047_BFC8)
        } else {
            try knownString(at: 0x0047_BFFC)
        }
        return try response + knownString(at: 0x0047_C020) +
            knownString(at: 0x0047_C03C) + knownString(at: 0x0047_C068)
    }

    func quizTutorialScript() throws -> String {
        try [0x0047_C904, 0x0047_C964, 0x0047_C99C, 0x0047_C9F8, 0x0047_CA10]
            .map(knownString(at:)).joined()
    }

    func quizLeaveScript() throws -> String {
        try knownScript(at: 0x0047_CA4C)
    }

    func typingGameEnterScript(
        reference: String?,
        records: [FirstTypingRecord?] = []
    ) throws -> String {
        let returning = try reference?.caseInsensitiveCompare(knownString(at: 0x0047_C760)) == .orderedSame
        var script = try knownString(at: 0x0047_CF94) +
            knownString(at: returning ? 0x0047_CFA4 : 0x0047_CFD4) +
            knownString(at: 0x0047_D06C) + knownString(at: 0x0047_C868)
        for level in 0 ..< 3 {
            script += try knownString(at: 0x0047_D09C) + String(level) +
                knownString(at: 0x0047_D0B4) + String(level) +
                knownString(at: 0x0047_C8A8)
            if records.indices.contains(level), let record = records[level] {
                script += try knownString(at: 0x0047_D0EC) +
                    String(format: "%2d", record.correctCount) + knownString(at: 0x0047_D100) +
                    String(record.totalMilliseconds) + knownString(at: 0x0047_D110)
            } else {
                script += try knownString(at: 0x0047_D0D0)
            }
        }
        return try script + knownString(at: 0x0047_C868) + knownString(at: 0x0047_D124)
    }

    func typingGameStartScript(level: Int) throws -> String {
        guard 0 ..< 3 ~= level else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(level)
        }
        return try knownScript(at: 0x0047_CE5C)
    }

    func typingGameQuestion(level: Int, attempt: Int, totalMilliseconds: Int) throws -> FirstTypingQuestion {
        guard 0 ..< 3 ~= level, 0 ..< 10 ~= attempt else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(level * 10 + attempt)
        }
        let expected = try knownString(at: Self.typingPhraseAddresses[level * 10 + attempt])
        let input = try knownString(at: 0x0047_CF38)
            .replacingOccurrences(of: "\\![raise,OnOpenTypingbox]", with: "")
        let script = try knownString(at: 0x0047_CEC0) + String(level) +
            knownString(at: 0x0047_CEDC) + String(attempt) +
            knownString(at: 0x0047_CEEC) + String(totalMilliseconds) +
            knownString(at: 0x0047_CF00) + knownString(at: 0x0047_CF14) + expected + input +
            "\\![open,inputbox,OnTypinggameInput,15000]"
        return FirstTypingQuestion(level: level, attempt: attempt, script: script, expectedAnswer: expected)
    }

    func typingGameInputScript(
        answer: String,
        question: FirstTypingQuestion,
        correctCount: Int,
        totalMilliseconds: Int,
        feedbackChoice: Int
    ) throws -> String {
        guard 0 ..< 2 ~= feedbackChoice else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(feedbackChoice)
        }
        let correct = answer.caseInsensitiveCompare(question.expectedAnswer) == .orderedSame
        var script = try knownString(at: correct
            ? (feedbackChoice == 0 ? 0x0047_BE7C : 0x0047_BE9C)
            : (feedbackChoice == 0 ? 0x0047_CABC : 0x0047_CAE0))
        if question.attempt < 9 {
            return try script + knownString(at: 0x0047_CE1C)
        }
        script += try knownString(at: 0x0047_CB14) + knownString(at: 0x0047_CB64) +
            String(correctCount) + knownString(at: 0x0047_CB9C) +
            String(totalMilliseconds) + knownString(at: 0x0047_CBC8) +
            String(totalMilliseconds / 10) + knownString(at: 0x0047_CC00)
        let resultAddress: UInt32 = switch correctCount {
        case 0: 0x0047_CCA4
        case 1 ... 3: 0x0047_CCC8
        case 4 ... 6: 0x0047_CCF8
        case 7 ... 8: 0x0047_CD30
        default: 0x0047_CD78
        }
        return try script + knownString(at: resultAddress) +
            knownString(at: 0x0047_CDC4) + knownString(at: 0x0047_CDD0)
    }

    func typingGameTutorialScript() throws -> String {
        try [0x0047_D16C, 0x0047_D1E8, 0x0047_D21C, 0x0047_D26C, 0x0047_D2DC, 0x0047_D308]
            .map(knownString(at:)).joined()
    }

    func typingGameLeaveScript() throws -> String {
        try knownScript(at: 0x0047_CA4C)
    }

    func googleSearchScript(query: String, choice: Int) throws -> String {
        guard 0 ..< 2 ~= choice else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        guard !query.isEmpty else {
            return try knownScript(at: 0x0047_EB20)
        }

        let reaction: String
        if try query.localizedCaseInsensitiveContains(knownString(at: 0x0047_EB3C)) {
            reaction = try knownString(at: 0x0047_EB4C)
        } else {
            let prefix = try knownString(at: choice == 0 ? 0x0047_EBAC : 0x0047_EBF0)
            reaction = try prefix + query + knownString(at: 0x0047_EB9C)
        }
        return try reaction + knownString(at: 0x0047_EC20) +
            percentEncodedQuery(query) + knownString(at: 0x0047_EC5C)
    }

    private func percentEncodedQuery(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private func decodedQuizAnswer(at address: UInt32) throws -> String {
        let reversedHex = try String(knownString(at: address).reversed())
        guard reversedHex.count.isMultiple(of: 2) else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(reversedHex.count / 2)
        var index = reversedHex.startIndex
        while index < reversedHex.endIndex {
            let next = reversedHex.index(index, offsetBy: 2)
            guard let byte = UInt8(reversedHex[index ..< next], radix: 16) else {
                throw FirstDLLAnalysisError.unsupportedFIRSTVersion
            }
            bytes.append(byte)
            index = next
        }
        guard let answer = String(data: Data(bytes), encoding: .shiftJIS) else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        return answer
    }

    /// Replays FIRST's fixed first-run introduction. The original handler
    /// appends these nine DLL-owned fragments in order without branching.
    public func firstBootScript() throws -> String {
        try [
            0x0048_66FC, 0x0048_67E4, 0x0048_6838,
            0x0048_6864, 0x0048_68F8, 0x0048_6988,
            0x0048_69FC, 0x0048_6A68, 0x0048_6B50
        ].map(knownString(at:)).joined()
    }

    public func ghostChangingScript(
        name: String?,
        isSleeping: Bool,
        isBathing: Bool,
        fallbackChoice: Int
    ) throws -> String {
        let script: String
        if isSleeping {
            script = try knownScript(at: 0x0047_0B7C)
        } else if isBathing {
            script = try knownScript(at: 0x0047_0BC4)
        } else if let name {
            let pairs: [(UInt32, UInt32)] = [
                (0x0047_0C10, 0x0047_0C20), (0x0047_0C4C, 0x0047_0C5C),
                (0x0047_0C80, 0x0047_0C90), (0x0047_0CB8, 0x0047_0CC8),
                (0x0047_0CF0, 0x0047_0D04), (0x0047_0D2C, 0x0047_0D3C),
                (0x0047_0D78, 0x0047_0D88), (0x0047_0DAC, 0x0047_0DBC),
                (0x0047_0DDC, 0x0047_0DF4)
            ]
            if let pair = try pairs.first(where: { try knownString(at: $0.0) == name }) {
                script = try knownScript(at: pair.1)
            } else {
                script = try ghostChangingFallbackScript(choice: fallbackChoice)
            }
        } else {
            script = try ghostChangingFallbackScript(choice: fallbackChoice)
        }
        return try script + knownString(at: 0x0048_6BF4)
    }

    /// Replays the statically identified name branches of FIRST's
    /// `OnGhostChanged` handler. Its unknown-name fallback also depends on a
    /// timestamp table maintained by Materia, so unsupported names remain nil.
    public func ghostChangedScript(
        name: String?,
        previousScript: String?,
        hildrChoice: Int
    ) throws -> String? {
        if previousScript?.contains("黒") == true {
            return try knownScript(at: 0x0048_70C4)
        }
        let address: UInt32? = switch name {
        case "陽子": 0x0048_6C2C
        case "愛理": 0x0048_6C58
        case "あると": 0x0048_6CB4
        case "花ちゃん": 0x0048_6D1C
        case "毒子": 0x0048_6D80
        case "美耳": 0x0048_6DF4
        case "さくら": 0x0048_6E50
        case "サンバーレイン": 0x0048_6E88
        case "ヒルデ": switch hildrChoice {
            case 0: 0x0048_6F2C
            case 1: 0x0048_6F60
            case 2: 0x0048_6FA8
            default: throw FirstDLLAnalysisError.invalidAITXTChoice(hildrChoice)
            }
        default: nil
        }
        guard let address else { return nil }
        return try knownScript(at: address)
    }

    public func installFailureScript(reason: String?) throws -> String {
        let address: UInt32 = switch reason?.lowercased() {
        case "unlha32": 0x0048_65C8
        case "unzip32": 0x0048_6638
        default: 0x0048_6698
        }
        return try knownScript(at: address)
    }

    public func installRefuseScript(name: String, consequenceChoice: Int) throws -> String {
        let consequenceAddress: UInt32 = switch consequenceChoice {
        case 0: 0x0048_654C
        case 1: 0x0048_656C
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(consequenceChoice)
        }
        return try knownString(at: 0x0048_64E4) + name +
            knownString(at: 0x0048_6508) + name +
            knownString(at: 0x0048_6538) + knownString(at: consequenceAddress)
    }

    /// Replays FIRST's anchor-name branches. Unlike ordinary choice handling,
    /// the original handler also returns a fixed response for unknown IDs.
    public func anchorSelectScript(id: String?, itaruChoice: Int) throws -> String {
        let address: UInt32 = switch id {
        case "いたる": switch itaruChoice {
            case 0: 0x0047_FAA8
            case 1: 0x0048_7348
            default: throw FirstDLLAnalysisError.invalidAITXTChoice(itaruChoice)
            }
        case "木野さん": 0x0048_73FC
        case "ガッツ石松": 0x0048_7448
        case "AIBO": 0x0048_74AC
        case "VAIO": 0x0048_7510
        case "あかほり": 0x0047_FAA8
        case "ラグナロク": 0x0048_75B4
        case "海原雄山": 0x0048_75F4
        default: 0x0048_769C
        }
        return try knownScript(at: address)
    }

    public func headlineFailureScript(reason: String?, isBathing: Bool) throws -> String? {
        if isBathing {
            return try knownScript(at: 0x0047_D71C)
        }
        let address: UInt32? = switch reason?.lowercased() {
        case "can't download": 0x0047_D760
        case "can't analyze": 0x0047_D7B4
        default: nil
        }
        guard let address else { return nil }
        return try knownScript(at: address)
    }

    public func headlineCompleteScript(isBathing: Bool) throws -> String {
        try knownScript(at: isBathing ? 0x0047_D824 : 0x0047_D840)
    }

    public func headlineBeginScript(name: String, isBathing: Bool) throws -> String {
        try knownString(at: isBathing ? 0x0047_D87C : 0x0047_D8AC) + name +
            knownString(at: 0x0047_D88C)
    }

    public func updateCompleteScript(result: String?) throws -> String {
        try knownScript(at: result?.lowercased() == "none" ? 0x0047_DC2C : 0x0047_DC64)
    }

    public func updateFailureScript(reason: String?, requiredVersion: String?) throws -> String? {
        switch reason?.lowercased() {
        case "too slow":
            try knownScript(at: 0x0047_DD2C)
        case "md5 miss":
            try knownScript(at: 0x0047_DD6C)
        case "timeout":
            try knownScript(at: 0x0047_DDA0)
        case "too old":
            try knownString(at: 0x0047_DDDC) + knownString(at: 0x0047_DE34) +
                (requiredVersion ?? "") + knownString(at: 0x0047_DE58)
        default:
            nil
        }
    }

    public func updateDownloadBeginScript(
        path: String,
        choice: Int,
        aitxtChoice: Int? = nil
    ) throws -> String {
        let suffix = try knownString(at: 0x0047_D99C)
        if choice == 4 {
            let candidates = records.filter {
                $0.directives.contains("\\k") && $0.phrase != "る" && $0.phrase != "い"
            }
            guard !candidates.isEmpty else {
                throw FirstDLLAnalysisError.invalidAITXTChoice(aitxtChoice ?? -1)
            }
            let index = aitxtChoice ?? Int.random(in: candidates.indices)
            guard candidates.indices.contains(index) else {
                throw FirstDLLAnalysisError.invalidAITXTChoice(index)
            }
            return try knownString(at: 0x0047_D8AC) + candidates[index].phrase +
                knownString(at: 0x0047_DA54) + path + suffix
        }
        let prefixAddress: UInt32 = switch choice {
        case 0: 0x0047_D96C
        case 1: 0x0047_D9B4
        case 2: 0x0047_D9D8
        case 3: 0x0047_DA18
        case 5: 0x0047_DA70
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownString(at: prefixAddress) + path + suffix
    }

    public func updateMD5CompareBeginScript(path: String) throws -> String {
        try knownString(at: 0x0047_DAD4) + path + knownString(at: 0x0047_DAE8)
    }

    public func updateMD5CompareResultScript(
        localMD5: String,
        remoteMD5: String,
        matches: Bool
    ) throws -> String {
        try knownString(at: matches ? 0x0047_DB6C : 0x0047_DBAC) +
            knownString(at: 0x0047_DB5C) + localMD5 + knownString(at: 0x0047_DB44) +
            knownString(at: 0x0047_AE7C) + remoteMD5 + knownString(at: 0x0047_DB2C)
    }

    public func sntpCompareScript(
        serverComponents: String?,
        localComponents: String?,
        offsetSeconds: String?
    ) throws -> String? {
        guard let server = dateComponents(serverComponents),
              let local = dateComponents(localComponents),
              let offset = offsetSeconds.flatMap(Int.init)
        else { return nil }

        var script = try formattedSNTPDate(prefix: 0x0047_DF7C, components: local, secondsSuffix: 0x0047_DFD0)
        script += try formattedSNTPDate(prefix: 0x0047_DFE4, components: server, secondsSuffix: 0x0047_DFFC)
        script += try knownScript(at: offset == 0 ? 0x0047_E010 : 0x0047_E050)
        return script
    }

    public func sntpBeginScript(server: String, daysSinceLastUpdate: Int) throws -> String {
        if daysSinceLastUpdate == 0 {
            return try knownString(at: 0x0047_D8AC) + server + knownString(at: 0x0047_DEF8)
        }
        return try knownString(at: 0x0047_D8AC) + String(daysSinceLastUpdate) + knownString(at: 0x0047_DF0C)
    }

    public func sntpBeginScript(
        server: String,
        persistedLastUpdateDate: Date?,
        at date: Date
    ) throws -> String {
        try sntpBeginScript(
            server: server,
            daysSinceLastUpdate: Self.daysBetween(
                persistedLastUpdateDate ?? lastUpdateDate,
                and: date
            )
        )
    }

    private func daysSinceLastUpdate(at date: Date) -> Int {
        Self.daysBetween(lastUpdateDate, and: date)
    }

    private static func daysBetween(_ lastUpdateDate: Date?, and date: Date) -> Int {
        guard let lastUpdateDate else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: lastUpdateDate)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func date(fromCommaSeparatedComponents value: String?) -> Date? {
        guard let values = value?.split(separator: ",").compactMap({ Int($0) }), values.count >= 3 else {
            return nil
        }
        return Calendar.current.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }

    private func dateComponents(_ value: String?) -> [String]? {
        guard let value else { return nil }
        let components = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return components.count >= 6 ? Array(components.prefix(6)) : nil
    }

    private func formattedSNTPDate(
        prefix: UInt32,
        components: [String],
        secondsSuffix: UInt32
    ) throws -> String {
        let labels: [UInt32] = [
            0x0047_DF94, 0x0047_DFA0, 0x0047_DFAC,
            0x0047_DFB8, 0x0047_DFC4, secondsSuffix
        ]
        var result = try knownString(at: prefix)
        for (component, label) in zip(components, labels) {
            result += try component + knownString(at: label)
        }
        return result
    }

    public func biffFailureScript(reason: String?, detail: String?) throws -> String? {
        switch reason?.lowercased() {
        case "timeout":
            try quotedBIFFDetail(detail) + knownString(at: 0x0047_E11C)
        case "defect":
            try knownScript(at: 0x0047_E14C)
        case "kick":
            try quotedBIFFDetail(detail) + knownString(at: 0x0047_E17C)
        default:
            nil
        }
    }

    public func biffBeginScript(detail: String?, choice: Int) throws -> String {
        let address: UInt32 = switch choice {
        case 0: 0x0047_E328
        case 1: 0x0047_E348
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try quotedBIFFDetail(detail) + knownString(at: address)
    }

    /// FIRST has a self-contained response when the mailbox is empty. The
    /// non-empty branch formats Materia's parsed POP header list and remains
    /// unsupported until that structured input is available to the engine.
    public func biffCompleteScript(messageCount: String?) throws -> String? {
        guard Int(messageCount ?? "") == 0 else { return nil }
        return try knownScript(at: 0x0047_E288)
    }

    public func installCompleteScript(type: String?, name: String) throws -> String {
        switch type?.lowercased() {
        case "ghost":
            let fields = name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            if fields.count == 2 {
                return try knownString(at: 0x0047_E3DC) + fields[0] + knownString(at: 0x0047_E400) +
                    knownString(at: 0x0047_E410) + fields[1] + knownString(at: 0x0047_E41C) +
                    knownString(at: 0x0047_E42C)
            }
            return try knownString(at: 0x0047_E3DC) + name + knownString(at: 0x0047_E44C)
        case "shell":
            return try knownString(at: 0x0047_E480) + name + knownString(at: 0x0047_E44C)
        case "balloon":
            return try knownString(at: 0x0047_E4B4) + name + knownString(at: 0x0047_E4D8)
        case "plugin":
            return try knownString(at: 0x0047_E510) + name + knownString(at: 0x0047_E4D8)
        default:
            return try knownString(at: 0x0047_E538) + name + knownString(at: 0x0047_E4D8)
        }
    }

    private func quotedBIFFDetail(_ detail: String?) throws -> String {
        try knownString(at: 0x0047_DAD4) + (detail ?? "") + knownString(at: 0x0047_E10C)
    }

    public func refreshMemoryScript() throws -> String {
        try [0x0047_EC94, 0x0047_ECEC, 0x0047_ED1C, 0x0047_ED64]
            .map(knownString(at:)).joined()
    }

    public func refreshMemoryCompleteScript() throws -> String {
        try [0x0047_EDC4, 0x0047_EE14, 0x0047_EE48, 0x0047_EE88, 0x0047_EEB8]
            .map(knownString(at:)).joined()
    }

    public func ipResultScript(ipAddress: String?) throws -> String {
        guard let ipAddress, !ipAddress.isEmpty else {
            return try knownScript(at: 0x0047_F064)
        }
        return try knownString(at: 0x0047_EF94) + ipAddress + knownString(at: 0x0047_EFB8) +
            knownString(at: 0x0047_EFC8) + knownString(at: 0x0047_EFE4) +
            knownString(at: 0x0047_F010) + knownString(at: 0x0047_F040)
    }

    private func loadedIPAddress() -> String? {
        let url = masterDirectoryURL.appending(path: "var/ip.php")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return contents.components(separatedBy: .newlines).first
    }

    public func urlDroppingScript(choice: Int) throws -> String {
        let address: UInt32 = switch choice {
        case 0: 0x0047_D384
        case 1: 0x0047_D3AC
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownScript(at: address)
    }

    public func exitWindowsPromptScript() throws -> String {
        try [0x0048_48F0, 0x0048_4918, 0x0048_4948].map(knownString(at:)).joined()
    }

    public func rebootWindowsPromptScript() throws -> String {
        try [0x0048_49A8, 0x0048_49D4, 0x0048_4948].map(knownString(at:)).joined()
    }

    public func portalMenuScript() throws -> String {
        try [
            0x0048_4A38, 0x0047_AE7C, 0x0048_4A64, 0x0048_4AA0,
            0x0047_AE7C, 0x0048_4ADC, 0x0048_4B1C, 0x0048_4B4C,
            0x0047_C868, 0x0048_4B8C, 0x0047_C868, 0x0047_FC04
        ].map(knownString(at:)).joined()
    }

    public func portalSelectedScript(id: String?) throws -> String? {
        let address: UInt32? = switch id?.lowercased() {
        case "sakuranavi": 0x0048_4BF4
        case "moonphase": 0x0048_4C58
        case "activesonar": 0x0048_4CA4
        case "nnn": 0x0048_4CE8
        case "saimoe": 0x0048_4D30
        case "ngc": 0x0048_4D78
        default: nil
        }
        guard let address else { return nil }
        return try knownString(at: address)
    }

    public func debugMenuScript() throws -> String {
        try [
            0x0048_4560, 0x0048_4588, 0x0048_45C8, 0x0048_45F0,
            0x0048_4628, 0x0048_4660, 0x0047_C868, 0x0047_FC04
        ].map(knownString(at:)).joined()
    }

    public func recommendMenuScript() throws -> String {
        try [
            0x0048_4DB4, 0x0047_AE7C, 0x0048_4DE0, 0x0048_4E20,
            0x0047_C868, 0x0048_4E64, 0x0047_C868, 0x0047_FC04
        ].map(knownString(at:)).joined()
    }

    public func recommendSelectedScript(id: String?) throws -> String? {
        let address: UInt32? = switch id?.lowercased() {
        case "airi": 0x0048_4EB8
        case "333": 0x0048_4EEC
        case "sakura": 0x0048_4F24
        default: nil
        }
        guard let address else { return nil }
        return try knownString(at: address)
    }

    public func windowRestoreSleepingScript(shortAbsence: Bool) throws -> String {
        try knownScript(at: shortAbsence ? 0x0048_7268 : 0x0048_7238)
    }

    public func windowRestoreDrowsyScript() throws -> String {
        try knownScript(at: 0x0048_7294)
    }

    public func windowRestoreBathingScript() throws -> String {
        try knownScript(at: 0x0048_72B4)
    }

    public func windowRestoreNormalShortAbsenceScript() throws -> String {
        try knownScript(at: 0x0048_7068)
    }

    public func windowRestoreSleepTransitionScript() throws -> String {
        try knownString(at: 0x0047_AA0C) + knownScript(at: 0x0048_72E8)
    }

    private func ghostChangingFallbackScript(choice: Int) throws -> String {
        let address: UInt32 = switch choice {
        case 0: 0x0047_0E18
        case 1: 0x0047_0E48
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownScript(at: address)
    }

    /// Bridges menu commands whose host-side effects have direct SakuraScript
    /// equivalents. Unsupported Materia-only explorer commands stay nil.
    public func choiceScript(id: String?) -> String? {
        switch id?.lowercased() {
        case "stayontop":
            "\\![set,windowstate,stayontop]\\e"
        case "!stayontop":
            "\\![set,windowstate,!stayontop]\\e"
        case "terminate":
            "\\-\\e"
        case "cancel", "cancel_notalk":
            "\\e"
        default:
            nil
        }
    }

    public func firstMenuChoiceScript(id: String, energy: Int) throws -> String? {
        switch id.lowercased() {
        case "sleepylevel":
            let address: UInt32 = switch energy {
            case ...30: 0x0047_F198
            case ...120: 0x0047_F160
            default: 0x0047_F12C
            }
            return try knownScript(at: address)
        case "game":
            return try [
                0x0047_CF94, 0x0047_FB08, 0x0047_AE7C,
                0x0047_FB30, 0x0047_FBAC, 0x0047_FBD8,
                0x0047_C868, 0x0047_FC04
            ].map(knownString(at:)).joined()
        case "commandbymouse":
            return try [
                0x0047_FDC0, 0x0047_AE7C, 0x0047_FDE0, 0x0047_FE00,
                0x0047_FE24, 0x0047_FE48, 0x0047_FE68, 0x0047_C868,
                0x0047_FE8C, 0x0047_FEAC, 0x0047_C868, 0x0047_FF0C,
                0x0047_FF34, 0x0047_C868, 0x0047_FF58, 0x0047_C868,
                0x0047_FF84, 0x0047_FFB4, 0x0047_C868, 0x0047_FFEC,
                0x0048_0020, 0x0048_0068, 0x0048_00A8, 0x0048_00E8,
                0x0047_C868, 0x0047_FC04
            ].map(knownString(at:)).joined()
        default:
            return nil
        }
    }

    /// FIRST has two normal-state remarks when a choice menu times out.
    public func choiceTimeoutScript(choice: Int) throws -> String {
        let address: UInt32 = switch choice {
        case 0: 0x0047_D44C
        case 1: 0x0048_62E4
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownScript(at: address)
    }

    /// Replays FIRST's normal-state close branch.
    public func onCloseScript(elapsedSeconds: TimeInterval, choice: Int) throws -> String {
        if elapsedSeconds < 120 {
            return try knownScript(at: 0x0048_6220)
        }
        let address: UInt32 = switch choice {
        case 0: 0x0048_617C
        case 1: 0x0048_61A4
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownScript(at: address)
    }

    public func sleepingCloseScript() throws -> String {
        try knownScript(at: 0x0048_60AC)
    }

    public func bathingCloseScript() throws -> String {
        try knownScript(at: 0x0048_612C)
    }

    public func sleepingSurfaceRestoreScript() throws -> String {
        try knownScript(at: 0x0048_6464)
    }

    public func bathingSurfaceRestoreScript() throws -> String {
        try knownScript(at: 0x0048_647C)
    }

    public func normalSurfaceRestoreScript() throws -> String {
        try knownScript(at: 0x0048_644C)
    }

    /// Replays FIRST's 34-way native talk selector using strings read from the
    /// user-supplied DLL. The explicit choice keeps reverse-engineering tests
    /// deterministic without snapshotting the copyrighted dialogue.
    public func randomTalkScript(choice: Int, aitxtChoices: [Int]? = nil) throws -> String {
        guard Self.randomTalkAddresses.indices.contains(choice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        let script = try knownScript(at: Self.randomTalkAddresses[choice])
        return try expandAITXTMacros(in: script, choices: aitxtChoices ?? [])
    }

    /// Replays the normal seven-way reaction used when scope 1 is double-clicked.
    /// Scope 0 is intentionally withheld until FIRST's sleep/menu state machine is modeled.
    public func keroDoubleClickScript(choice: Int) throws -> String {
        switch choice {
        case 0:
            try knownScript(at: 0x0048_43B0)
        case 1:
            try knownString(at: 0x0048_43F8) + knownString(at: 0x0047_B038) + knownString(at: 0x0048_4410)
        case 2:
            try knownScript(at: 0x0048_4428)
        case 3:
            try knownScript(at: 0x0048_4448)
        case 4:
            try knownScript(at: 0x0048_44A4)
        case 5:
            try knownScript(at: 0x0048_44E0)
        case 6:
            try knownScript(at: 0x0048_44F4)
        default:
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
    }

    /// Replays FIRST's escalating scope 0 Bust click responses. The third and
    /// subsequent response intentionally includes FIRST's own close command.
    public func sakuraBustClickScript(clickCount: Int) throws -> String {
        switch clickCount {
        case 1:
            try knownScript(at: 0x0048_38B0)
        case 2:
            try knownScript(at: 0x0048_38C8)
        case 3...:
            try [
                0x0048_3920, 0x0048_3960, 0x0048_39A8,
                0x0048_3A14, 0x0048_3AD4
            ].map(knownString(at:)).joined()
        default:
            throw FirstDLLAnalysisError.invalidAITXTChoice(clickCount)
        }
    }

    public func drowsyTransitionScript(choice: Int) throws -> String {
        let addresses: [UInt32] = [0x0047_A984, 0x0047_A99C, 0x0047_A9C0, 0x0047_A9E4]
        guard addresses.indices.contains(choice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownScript(at: addresses[choice])
    }

    public func sleepTransitionScript(choice: Int) throws -> String {
        let addresses: [UInt32] = [0x0047_AA2C, 0x0047_AA84, 0x0047_AB0C]
        guard addresses.indices.contains(choice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownString(at: 0x0047_AA0C) + knownScript(at: addresses[choice])
    }

    public func sleepingPokeScript(choice: Int) throws -> String {
        let addresses: [UInt32] = [
            0x0048_3C5C, 0x0048_3C78, 0x0048_3C94,
            0x0048_3CB0, 0x0048_3CCC, 0x0048_3CE8
        ]
        guard addresses.indices.contains(choice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownScript(at: addresses[choice])
    }

    public func wakeFromSleepScript(choice: Int) throws -> String {
        guard (0 ..< 4).contains(choice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        var script = try knownString(at: 0x0048_3B48)
        if choice < 3 {
            script += try knownString(at: 0x0048_3B94)
        } else {
            script += try knownString(at: 0x0048_3BD4) + knownString(at: 0x0048_3BF4)
        }
        return try script + knownString(at: 0x0047_AC8C)
    }

    public func wakeFromDrowsyScript() throws -> String {
        try knownScript(at: 0x0048_3D04)
    }

    public func sakuraBathingDoubleClickScript() throws -> String {
        try knownScript(at: 0x0048_3D50)
    }

    public func keroSleepingDoubleClickMenuScript() throws -> String {
        try [0x0048_4304, 0x0048_432C, 0x0048_4074, 0x0047_C868, 0x0048_42C0]
            .map(knownString(at:)).joined()
    }

    public func keroBathingDoubleClickMenuScript() throws -> String {
        try [0x0048_4364, 0x0048_438C, 0x0048_4074, 0x0047_C868, 0x0048_42C0]
            .map(knownString(at:)).joined()
    }

    public func bathTransitionScript() throws -> String {
        try knownString(at: 0x0047_AA0C) + knownScript(at: 0x0047_AB94)
    }

    public func returnFromBathScript(choice: Int) throws -> String {
        let address: UInt32 = switch choice {
        case 0: 0x0047_ACAC
        case 1: 0x0047_AD44
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownString(at: 0x0047_AC8C) + knownScript(at: address)
    }

    /// Builds FIRST's normal-state scope 0 menu. Transient sleep and bathing
    /// branches are intentionally kept separate until their state transitions
    /// can be reconstructed rather than guessed.
    public func sakuraDoubleClickMenuScript(region: String?, faceReactionChoice: Int) throws -> String {
        var script = try knownString(at: 0x0047_CF94)
        if region?.caseInsensitiveCompare("face") == .orderedSame {
            let reactionAddress: UInt32 = switch faceReactionChoice {
            case 0: 0x0048_3E3C
            case 1: 0x0048_3E5C
            default: throw FirstDLLAnalysisError.invalidAITXTChoice(faceReactionChoice)
            }
            script += try knownString(at: reactionAddress)
        }
        for address in Self.normalMenuAddresses {
            script += try knownString(at: address)
        }
        return script
    }

    /// Executes the currently understood portion of FIRST's initial OnBoot switch.
    /// Unsupported branches use FIRST's self-contained fallback branch.
    public func onBootScript(
        hour: Int,
        topLevelChoice: Int,
        midnightChoice: Int? = nil,
        aitxtChoices: [Int]? = nil,
        day: Int? = nil,
        scheduleKindChoice: Int? = nil,
        scheduleTemplateChoice: Int? = nil,
        generatedScheduleChoices: [Int]? = nil
    ) throws -> String {
        if topLevelChoice == 0 {
            if let address = Self.fixedTimeGreetingAddress(for: hour) {
                return try knownScript(at: address)
            }
            if (0 ... 6).contains(hour),
               let midnightChoice
            {
                if let address = Self.fixedMidnightGreetingAddress(for: midnightChoice) {
                    return try knownScript(at: address)
                }
                if (2 ... 5).contains(midnightChoice) {
                    return try composedMidnightGreeting(choice: midnightChoice, aitxtChoices: aitxtChoices)
                }
            }
        }
        if topLevelChoice == 1 || topLevelChoice == 2,
           let day,
           let scheduleKindChoice,
           let scheduleTemplateChoice
        {
            if scheduleKindChoice == 0 {
                return try fixedScheduleScript(
                    day: day,
                    templateChoice: scheduleTemplateChoice,
                    aitxtChoice: aitxtChoices?.first
                )
            }
            if (1 ... 2).contains(scheduleKindChoice), let generatedScheduleChoices {
                return try generatedScheduleScript(
                    day: day,
                    choices: generatedScheduleChoices,
                    aitxtChoices: aitxtChoices
                )
            }
        }
        return try knownScript(at: 0x0048_5EEC)
    }

    public func aitxtRecords() throws -> [FirstAITXTRecord] {
        records
    }

    private static func fixedTimeGreetingAddress(for hour: Int) -> UInt32? {
        switch hour {
        case 7 ... 10:
            0x0048_5514
        case 11 ... 15:
            0x0048_5610
        case 16 ... 19:
            0x0048_5558
        case 20 ... 23:
            0x0048_55CC
        default:
            // FIRST has a separate 13-way switch for 00:00-06:59.
            nil
        }
    }

    private static func fixedMidnightGreetingAddress(for choice: Int) -> UInt32? {
        switch choice {
        case 0:
            0x0048_520C
        case 1:
            0x0048_5268
        case 6:
            0x0048_5380
        case 7, 8:
            0x0048_53B8
        case 9:
            0x0048_5404
        case 10:
            0x0048_543C
        case 11:
            0x0048_5460
        case 12:
            0x0048_54DC
        default:
            // Choices 2-5 splice formatted date values into several fragments.
            nil
        }
    }

    private func composedMidnightGreeting(choice: Int, aitxtChoices: [Int]?) throws -> String {
        let prefix = try knownString(at: 0x0048_52AC)
        let first = try aitxtPhrase(directive: "\\ms", choice: aitxtChoices?.first)
        if choice == 5 {
            return try prefix + first + knownString(at: 0x0048_535C)
        }
        let join = try knownString(at: 0x0048_52D0)
        let second = try aitxtPhrase(directive: "\\ms", choice: aitxtChoices?.dropFirst().first)
        let suffixAddress: UInt32 = switch choice {
        case 2: 0x0048_52DC
        case 3: 0x0048_5304
        case 4: 0x0048_5328
        default: throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try prefix + first + join + second + knownString(at: suffixAddress)
    }

    private func aitxtPhrase(directive: String, choice: Int?) throws -> String {
        let candidates = records.filter { $0.directives.contains(directive) }
        guard !candidates.isEmpty else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice ?? -1)
        }
        let index = choice ?? Int.random(in: candidates.indices)
        guard candidates.indices.contains(index) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(index)
        }
        return candidates[index].phrase
    }

    private func fixedScheduleScript(day: Int, templateChoice: Int, aitxtChoice: Int?) throws -> String {
        guard (1 ... 31).contains(day), Self.scheduleTemplateAddresses.indices.contains(templateChoice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(templateChoice)
        }
        let name = try honorificName(aitxtPhrase(directive: "\\ms", choice: aitxtChoice))
        var script = try knownString(at: 0x0048_5654)
        script += name
        script += try knownString(at: 0x0048_5684)
        script += try knownString(at: 0x0048_56A4)
        script += String(day)
        script += try knownString(at: 0x0048_56BC)
        for address in Self.scheduleTemplateAddresses[templateChoice] {
            script += try knownString(at: address)
        }
        return script
    }

    private func generatedScheduleScript(day: Int, choices: [Int], aitxtChoices: [Int]?) throws -> String {
        guard choices.count >= 5 else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choices.count)
        }
        var script = try scheduleIntroduction(day: day, aitxtChoice: aitxtChoices?.first)
        script += try selectedString(from: Self.earlyScheduleAddresses, choice: choices[0])
        script += try selectedString(from: Self.morningScheduleAddresses, choice: choices[1])
        script += try selectedString(from: Self.noonScheduleAddresses, choice: choices[2])
        if choices[3] == 1 {
            let losses = choices.count > 5 ? choices[5] : Int.random(in: 10 ..< 20)
            guard (10 ..< 20).contains(losses) else {
                throw FirstDLLAnalysisError.invalidAITXTChoice(losses)
            }
            script += try knownString(at: 0x0048_5D70) + String(losses) + knownString(at: 0x0048_5D8C)
        } else {
            script += try selectedString(from: Self.eveningScheduleAddresses, choice: choices[3])
        }
        script += try selectedString(from: Self.nightScheduleAddresses, choice: choices[4])
        return try expandAITXTMacros(in: script, choices: Array(aitxtChoices?.dropFirst() ?? []))
    }

    private func scheduleIntroduction(day: Int, aitxtChoice: Int?) throws -> String {
        guard (1 ... 31).contains(day) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(day)
        }
        let name = try honorificName(aitxtPhrase(directive: "\\ms", choice: aitxtChoice))
        return try knownString(at: 0x0048_5654) + name +
            knownString(at: 0x0048_5684) + knownString(at: 0x0048_56A4) +
            String(day) + knownString(at: 0x0048_56BC)
    }

    private func selectedString(from addresses: [UInt32], choice: Int) throws -> String {
        guard addresses.indices.contains(choice) else {
            throw FirstDLLAnalysisError.invalidAITXTChoice(choice)
        }
        return try knownString(at: addresses[choice])
    }

    private func expandAITXTMacros(in source: String, choices: [Int]) throws -> String {
        var result = source
        var choiceIndex = 0
        for (macro, directive) in [("%ms", "\\ms"), ("%mz", "\\mz")] {
            while let range = result.range(of: macro) {
                let choice = choiceIndex < choices.count ? choices[choiceIndex] : nil
                try result.replaceSubrange(range, with: aitxtPhrase(directive: directive, choice: choice))
                choiceIndex += 1
            }
        }
        return result
    }

    private func honorificName(_ value: String) -> String {
        value.hasSuffix("さん") || value.hasSuffix("ちゃん") ? value : value + "さん"
    }

    private func knownString(at address: UInt32) throws -> String {
        guard let value = strings[address] else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        return value
    }

    private func knownScript(at address: UInt32) throws -> String {
        let value = try knownString(at: address)
        guard FirstEmbeddedString(fileOffset: 0, value: value).containsSakuraScript else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        return value
    }

    private static let typingPhraseAddresses: [UInt32] = [
        0x004A_B3A4, 0x004A_B3B8, 0x004A_B3D8, 0x004A_B400, 0x004A_B438,
        0x004A_B46C, 0x004A_B4A4, 0x004A_B4DC, 0x004A_B51C, 0x004A_B540,
        0x004A_B5C8, 0x004A_B5DC, 0x004A_B5F8, 0x004A_B620, 0x004A_B658,
        0x004A_B68C, 0x004A_B6A8, 0x004A_B6E0, 0x004A_B720, 0x004A_B764,
        0x004A_B7E8, 0x004A_B7FC, 0x004A_B81C, 0x004A_B83C, 0x004A_B858,
        0x004A_B880, 0x004A_B8B0, 0x004A_B8E4, 0x004A_B924, 0x004A_B968
    ]

    private static let scheduleTemplateAddresses: [[UInt32]] = [
        [0x0048_56E4, 0x0048_570C, 0x0048_5738, 0x0048_5764, 0x0048_5784],
        [0x0048_57B8, 0x0048_57DC, 0x0048_5800, 0x0048_582C, 0x0048_5858],
        [0x0048_5874, 0x0048_589C, 0x0048_58B8, 0x0048_58D4, 0x0048_58FC],
        [0x0048_5920, 0x0048_589C, 0x0048_58B8, 0x0048_594C, 0x0048_5978]
    ]

    private static let earlyScheduleAddresses: [UInt32] = [
        0x0048_59A0, 0x0048_59C8, 0x0048_59E8, 0x0048_5A28, 0x0048_5A68, 0x0048_5A9C, 0x0048_5ABC
    ]
    private static let morningScheduleAddresses: [UInt32] = [
        0x0048_5ADC, 0x0048_5AFC, 0x0048_5B1C, 0x0048_5B5C, 0x0048_5B8C, 0x0048_5BC0
    ]
    private static let noonScheduleAddresses: [UInt32] = [
        0x0048_5BE4, 0x0048_5C24, 0x0048_5C58, 0x0048_5C7C, 0x0048_5C98, 0x0048_5CE8, 0x0048_5D0C
    ]
    private static let eveningScheduleAddresses: [UInt32] = [
        0x0048_5D30, 0x0048_5D70, 0x0048_5DA0, 0x0048_5DC0
    ]
    private static let nightScheduleAddresses: [UInt32] = [
        0x0048_5DE4, 0x0048_5E5C, 0x0048_5E80, 0x0048_5EB4, 0x0048_5ECC
    ]

    /// Addresses selected by FIRST's function at 0x00470EF4. Only addresses are
    /// retained here; all dialogue remains in the user's own first.dll.
    private static let randomTalkAddresses: [UInt32] = [
        0x0047_1230, 0x0047_127C, 0x0047_12D0, 0x0047_130C,
        0x0047_1348, 0x0047_138C, 0x0047_13D8, 0x0047_1420,
        0x0047_146C, 0x0047_14C0, 0x0047_1554, 0x0047_15AC,
        0x0047_146C, 0x0047_15EC, 0x0047_164C, 0x0047_16BC,
        0x0047_1704, 0x0047_1740, 0x0047_178C, 0x0047_17F8,
        0x0047_182C, 0x0047_1868, 0x0047_18A0, 0x0047_1904,
        0x0047_195C, 0x0047_1994, 0x0047_19E8, 0x0047_1A34,
        0x0047_1A78, 0x0047_1AC0, 0x0047_1B04, 0x0047_1B44,
        0x0047_1B8C, 0x0047_1BC8
    ]

    /// FIRST's default menu fragments with the non-new game/news/update paths.
    private static let normalMenuAddresses: [UInt32] = [
        0x0048_3E7C, 0x0048_3ED0, 0x0047_C868, 0x0048_3F24,
        0x0048_3F48, 0x0048_3F8C, 0x0048_3FB8, 0x0048_3FE0,
        0x0047_C868, 0x0048_4044, 0x0048_4074, 0x0048_40A4,
        0x0048_40D4, 0x0048_4108, 0x0048_414C, 0x0048_4178,
        0x0047_C868, 0x0048_41A8, 0x0048_4218, 0x0047_C868,
        0x0048_426C, 0x0048_4298, 0x0047_C868, 0x0048_42C0
    ]
}

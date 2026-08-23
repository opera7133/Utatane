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

/// A Wine-free, read-only session over files supplied by the user.
///
/// Event coverage is deliberately incremental. Unsupported events return nil so
/// callers can keep using the existing compatibility host until native parity is
/// sufficient to switch the application over.
public struct FirstNativeSession: Sendable {
    private let analyzer: FirstDLLAnalyzer
    private let records: [FirstAITXTRecord]
    private let strings: [UInt32: String]
    private let materializedAt: Date
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
        materializedAt = Date()
        let variables = Self.readVariables(
            at: masterDirectoryURL.appending(path: "var/first.txt")
        )
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
            try knownScript(at: 0x0048_644C)
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

    /// Replays FIRST's normal-state close branch. Sleep/bathing close branches
    /// require state that the native session does not model yet.
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

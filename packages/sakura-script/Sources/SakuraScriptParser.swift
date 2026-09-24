import Foundation

public struct SakuraScriptParser: Sendable {
    public init() {}

    public func parse(_ script: SakuraScript) -> [SakuraScriptToken] {
        parse(script.rawValue)
    }

    public func parse(_ source: String) -> [SakuraScriptToken] {
        var locations: [SakuraScriptSourceLocation]?
        return parse(source, locations: &locations)
    }

    /// Retains character positions in the source, including tags and escapes.
    public func parseLocated(_ source: String) -> [SakuraScriptLocatedToken] {
        var locations: [SakuraScriptSourceLocation]? = []
        let tokens = parse(source, locations: &locations)
        return zip(tokens, locations ?? []).map { SakuraScriptLocatedToken(token: $0, location: $1) }
    }

    private func parse(_ source: String, locations: inout [SakuraScriptSourceLocation]?) -> [SakuraScriptToken] {
        let characters = Array(source)
        var index = 0
        var text = ""
        var textStart = 0
        var textEnds: [Int] = []
        var tokens: [SakuraScriptToken] = []

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(text))
            locations?.append(.init(range: textStart ..< index, textCharacterEnds: textEnds))
            text = ""
            textEnds.removeAll(keepingCapacity: true)
        }

        while index < characters.count {
            if characters[index] == "%" {
                let propertyPrefix = Array("property")
                let propertyEnd = index + 1 + propertyPrefix.count
                if propertyEnd < characters.count,
                   Array(characters[(index + 1) ..< propertyEnd]).map({ $0.lowercased() }) == propertyPrefix.map({ $0.lowercased() })
                {
                    var argumentIndex = propertyEnd
                    if let property = bracketArgument(in: characters, index: &argumentIndex) {
                        flushText()
                        tokens.append(.property(property))
                        locations?.append(.init(range: index ..< argumentIndex))
                        index = argumentIndex
                        continue
                    }
                }
                let names = [
                    "screenheight", "screenwidth", "lastobjectname", "lastghostname",
                    "selfname2", "wronghour", "username", "selfname", "keroname",
                    "minute", "second", "month", "hour", "day", "exh", "et", "dms",
                    "ms", "mz", "ml", "mc", "mh", "mt", "me", "mp", "m?", "*"
                ]
                if let name = names.first(where: { name in
                    let end = index + name.count + 1
                    guard end <= characters.count else { return false }
                    return String(characters[(index + 1) ..< end]).lowercased() == name
                }) {
                    flushText()
                    tokens.append(name == "*" ? .marker : .environmentVariable(name))
                    locations?.append(.init(range: index ..< (index + name.count + 1)))
                    index += name.count + 1
                    continue
                }
            }
            guard characters[index] == "\\" else {
                if text.isEmpty {
                    textStart = index
                }
                text.append(characters[index])
                index += 1
                if locations != nil {
                    textEnds.append(index)
                }
                continue
            }

            guard index + 1 < characters.count else {
                if text.isEmpty {
                    textStart = index
                }
                text.append("\\")
                index += 1
                if locations != nil {
                    textEnds.append(index)
                }
                break
            }

            if characters[index + 1] == "\\" {
                if text.isEmpty {
                    textStart = index
                }
                text.append("\\")
                index += 2
                if locations != nil {
                    textEnds.append(index)
                }
                continue
            }

            flushText()
            let sourceStart = index
            let tokenStart = tokens.count
            var literalTextEnds: [Int]?
            defer {
                for _ in tokenStart ..< tokens.count {
                    locations?.append(.init(range: sourceStart ..< index, textCharacterEnds: literalTextEnds))
                }
            }
            index += 1
            let command = characters[index]
            index += 1

            switch command {
            case "%":
                tokens.append(.text("%"))
            case "-":
                tokens.append(.contentAction(.closeGhost))
            case "a":
                tokens.append(.raisedEvent(id: "OnAITalk", arguments: []))
            case "v":
                tokens.append(.stayOnTop(true))
            case "+":
                tokens.append(.contentAction(.randomGhost))
            case "0", "h":
                tokens.append(.scope(0))
            case "1", "u":
                tokens.append(.scope(1))
            case "p":
                if let value = numericArgument(in: characters, index: &index) {
                    tokens.append(.scope(value))
                } else {
                    tokens.append(.unknown("\\p"))
                }
            case "s":
                if let argument = bracketArgument(in: characters, index: &index) {
                    if let value = Int(argument) {
                        tokens.append(.surface(value))
                    } else if !argument.isEmpty {
                        tokens.append(.namedSurface(argument))
                    } else {
                        tokens.append(.unknown("\\s[]"))
                    }
                } else if index < characters.count, let value = characters[index].wholeNumberValue {
                    index += 1
                    tokens.append(.surface(value))
                } else {
                    tokens.append(.unknown("\\s"))
                }
            case "i":
                if let argument = bracketArgument(in: characters, index: &index) {
                    let arguments = splitArguments(argument)
                    if let identifier = arguments.first, !identifier.isEmpty {
                        tokens.append(.animation(
                            identifier: identifier,
                            waitsForCompletion: arguments.dropFirst().contains {
                                $0.lowercased() == "wait"
                            }
                        ))
                    } else {
                        tokens.append(.unknown("\\i[\(argument)]"))
                    }
                } else {
                    tokens.append(.unknown("\\i"))
                }
            case "b":
                if let value = numericArgument(in: characters, index: &index) {
                    tokens.append(.balloonSurface(value))
                } else {
                    tokens.append(.unknown("\\b"))
                }
            case "n":
                let argument = bracketArgument(in: characters, index: &index)?.lowercased()
                let scale: Double? = if argument == "half" {
                    0.5
                } else if let argument {
                    Double(argument.hasSuffix("%") ? String(argument.dropLast()) : argument).map { $0 / 100 }
                } else {
                    nil
                }
                tokens.append(.lineBreak(scale: scale))
            case "w":
                if index < characters.count,
                   let value = characters[index].wholeNumberValue,
                   (1 ... 9).contains(value)
                {
                    index += 1
                    tokens.append(.wait(milliseconds: value * 50))
                } else {
                    tokens.append(.unknown("\\w"))
                }
            case "x":
                let argument = bracketArgument(in: characters, index: &index)
                tokens.append(.waitForClick(clearOnResume: argument?.lowercased() != "noclear"))
            case "t":
                tokens.append(.timeCritical)
            case "4":
                tokens.append(.separateCharacters)
            case "5":
                tokens.append(.approachCharacters)
            case "6":
                tokens.append(.sntpCorrect)
            case "7":
                tokens.append(.sntpStart)
            case "q":
                // Older SakuraScript assigns a display slot directly after
                // \q, as in \q0[id][label]. The slot does not change the
                // dispatched choice ID.
                while index < characters.count, characters[index].isNumber {
                    index += 1
                }
                let hasStar = index < characters.count && characters[index] == "*"
                if hasStar {
                    index += 1
                }
                if let firstArg = bracketArgument(in: characters, index: &index) {
                    if index < characters.count, characters[index] == "[", let secondArg = bracketArgument(in: characters, index: &index) {
                        if hasStar {
                            tokens.append(.marker)
                        }
                        tokens.append(.choice(label: secondArg, id: firstArg, arguments: []))
                        tokens.append(.lineBreak(scale: nil))
                    } else {
                        let arguments = splitArguments(firstArg)
                        if arguments.count >= 2 {
                            if hasStar {
                                tokens.append(.marker)
                            }
                            tokens.append(.choice(
                                label: arguments[0],
                                id: arguments[1],
                                arguments: Array(arguments.dropFirst(2))
                            ))
                        } else {
                            tokens.append(.unknown("\\q\(hasStar ? "*" : "")[\(firstArg)]"))
                        }
                    }
                } else {
                    tokens.append(.unknown("\\q\(hasStar ? "*" : "")"))
                }
            case "j":
                if let argument = bracketArgument(in: characters, index: &index), !argument.isEmpty {
                    tokens.append(.open(argument))
                } else {
                    tokens.append(.unknown("\\j"))
                }
            case "8":
                if let argument = bracketArgument(in: characters, index: &index), !argument.isEmpty {
                    tokens.append(.sound(.play(file: argument, loop: false, options: [])))
                } else {
                    tokens.append(.unknown("\\8"))
                }
            case "*":
                tokens.append(.choiceTimeout(.disabled))
            case "f":
                if let argument = bracketArgument(in: characters, index: &index) {
                    let arguments = splitArguments(argument)
                    if let name = arguments.first, !name.isEmpty {
                        tokens.append(.font(
                            name: name.lowercased(),
                            arguments: Array(arguments.dropFirst())
                        ))
                    } else {
                        tokens.append(.unknown("\\f[(argument)]"))
                    }
                } else {
                    tokens.append(.unknown("\\f"))
                }
            case "_":
                if index + 1 < characters.count,
                   characters[index] == "_",
                   characters[index + 1] == "q"
                {
                    index += 2
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let arguments = splitArguments(argument)
                        if let id = arguments.first, !id.isEmpty {
                            tokens.append(.choiceStart(
                                id: id,
                                arguments: Array(arguments.dropFirst())
                            ))
                        } else {
                            tokens.append(.unknown("\\__q[(argument)]"))
                        }
                    } else {
                        tokens.append(.choiceEnd)
                    }
                } else if index + 1 < characters.count,
                          characters[index] == "_",
                          characters[index + 1] == "v"
                {
                    index += 2
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let arguments = splitArguments(argument)
                        if arguments.count == 1, arguments[0].lowercased() == "disable" {
                            tokens.append(.voiceMode(.disabled))
                        } else if arguments.count == 2,
                                  arguments[0].lowercased() == "alternate"
                        {
                            tokens.append(.voiceMode(.alternate(arguments[1])))
                        } else {
                            tokens.append(.unknown("\\__v[\(argument)]"))
                        }
                    } else {
                        tokens.append(.voiceMode(.defaultValue))
                    }
                } else if index + 1 < characters.count,
                          characters[index] == "_",
                          characters[index + 1] == "w"
                {
                    index += 2
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let arguments = splitArguments(argument)
                        if arguments.count == 2,
                           arguments[0].lowercased() == "animation",
                           !arguments[1].isEmpty
                        {
                            tokens.append(.waitForAnimation(arguments[1]))
                        } else if argument.lowercased() == "clear" {
                            tokens.append(.waitUntil(milliseconds: nil))
                        } else if let milliseconds = Int(argument) {
                            tokens.append(.waitUntil(milliseconds: max(0, milliseconds)))
                        } else {
                            tokens.append(.unknown("\\__w[\(argument)]"))
                        }
                    } else {
                        tokens.append(.unknown("\\__w"))
                    }
                } else if index < characters.count, characters[index] == "q" {
                    index += 1
                    tokens.append(.quickSection(nil))
                } else if index < characters.count, characters[index] == "l" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let arguments = splitArguments(argument)
                        if arguments.count == 1,
                           let x = Self.balloonCoordinate(arguments[0])
                        {
                            // Older ghosts use \_l[x] as a shorthand that keeps the
                            // current vertical cursor position.
                            tokens.append(.cursorMove(x: x, y: nil))
                        } else if arguments.count == 2 {
                            let x = arguments[0].isEmpty ? nil : Self.balloonCoordinate(arguments[0])
                            let y = arguments[1].isEmpty ? nil : Self.balloonCoordinate(arguments[1])
                            if arguments[0].isEmpty || x != nil, arguments[1].isEmpty || y != nil {
                                tokens.append(.cursorMove(x: x, y: y))
                            } else {
                                tokens.append(.unknown("\\_l[\(argument)]"))
                            }
                        } else {
                            tokens.append(.unknown("\\_l[\(argument)]"))
                        }
                    } else {
                        tokens.append(.unknown("\\_l"))
                    }
                } else if index < characters.count, characters[index] == "s" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let scopes = splitArguments(argument).compactMap(Int.init)
                        if !scopes.isEmpty, scopes.count == splitArguments(argument).count {
                            tokens.append(.synchronizeScopes(scopes))
                        } else {
                            tokens.append(.unknown("\\_s[\(argument)]"))
                        }
                    } else {
                        tokens.append(.synchronizeScopes(nil))
                    }
                } else if index < characters.count,
                          ["!", "?"].contains(characters[index])
                {
                    let delimiter = characters[index]
                    index += 1
                    let literalStart = index
                    let literal = readLiteralSection(
                        endingWith: delimiter,
                        in: characters,
                        index: &index
                    )
                    if !literal.isEmpty {
                        if locations != nil {
                            literalTextEnds = Array((literalStart + 1) ... (literalStart + literal.count))
                        }
                        tokens.append(.text(literal))
                    }
                } else if index < characters.count, characters[index] == "u" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index),
                       let text = encodedCharacter(argument, maximum: 0xFFFF, excludesSurrogates: true)
                    {
                        tokens.append(.text(text))
                    } else {
                        tokens.append(.unknown("\\_u"))
                    }
                } else if index < characters.count, characters[index] == "m" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index),
                       let text = encodedCharacter(argument, maximum: 0x7F)
                    {
                        tokens.append(.text(text))
                    } else {
                        tokens.append(.unknown("\\_m"))
                    }
                } else if index < characters.count, characters[index] == "+" {
                    index += 1
                    tokens.append(.contentAction(.nextGhost))
                } else if index < characters.count, characters[index] == "n" {
                    index += 1
                    tokens.append(.automaticLineBreak)
                } else if index < characters.count, characters[index] == "w" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index),
                       let milliseconds = Int(argument)
                    {
                        tokens.append(.wait(milliseconds: max(0, milliseconds)))
                    } else {
                        tokens.append(.unknown("\\_w"))
                    }
                } else if index < characters.count, characters[index] == "v" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index), !argument.isEmpty {
                        tokens.append(.sound(.play(file: argument, loop: false, options: [])))
                    } else {
                        tokens.append(.unknown("\\_v"))
                    }
                } else if index < characters.count, characters[index] == "V" {
                    index += 1
                    tokens.append(.sound(.wait))
                } else if index < characters.count, characters[index] == "b" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let arguments = splitArguments(argument)
                        if arguments.count >= 2, arguments[1].lowercased() == "inline" {
                            let isOpaque = arguments.count >= 3 && arguments[2].lowercased() == "opaque"
                            let options = Array(arguments.dropFirst(2))
                            tokens.append(.inlineImage(path: arguments[0], isOpaque: isOpaque, options: options))
                        } else if arguments.count >= 3,
                                  let x = Int(arguments[1]),
                                  let y = Int(arguments[2])
                        {
                            let options = Array(arguments.dropFirst(3))
                            let isOpaque = options.contains { option in
                                let normalized = option.lowercased()
                                return normalized == "opaque" || normalized == "--option=opaque"
                            }
                            tokens.append(.positionedImage(
                                path: arguments[0],
                                x: x,
                                y: y,
                                isOpaque: isOpaque,
                                options: options
                            ))
                        } else {
                            tokens.append(.unknown("\\_b[\(argument)]"))
                        }
                    } else {
                        tokens.append(.unknown("\\_b"))
                    }
                } else if index < characters.count, characters[index] == "a" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index) {
                        let arguments = splitArguments(argument)
                        if let id = arguments.first {
                            tokens.append(.anchorStart(
                                id: id,
                                arguments: Array(arguments.dropFirst())
                            ))
                        } else {
                            tokens.append(.unknown("\\_a[]"))
                        }
                    } else {
                        tokens.append(.anchorEnd)
                    }
                } else {
                    tokens.append(.unknown(readUnknown(command: command, in: characters, index: &index)))
                }
            case "c":
                if let argument = bracketArgument(in: characters, index: &index) {
                    let arguments = splitArguments(argument)
                    if arguments.count >= 2,
                       let unit = SakuraScriptClearUnit(rawValue: arguments[0].lowercased()),
                       let count = Int(arguments[1])
                    {
                        tokens.append(.partialClear(
                            unit: unit,
                            count: max(0, count),
                            start: arguments.count >= 3 ? Int(arguments[2]) : nil
                        ))
                    } else {
                        tokens.append(.unknown("\\c[\(argument)]"))
                    }
                } else {
                    tokens.append(.clear)
                }
            case "C":
                tokens.append(.clearAll)
            case "&":
                if let identifier = bracketArgument(in: characters, index: &index),
                   let text = entityReferences[identifier.lowercased()]
                {
                    tokens.append(.text(text))
                } else {
                    tokens.append(.unknown("\\&"))
                }
            case "!":
                if let argument = bracketArgument(in: characters, index: &index) {
                    let arguments = splitArguments(argument)
                    if argument == "*" {
                        tokens.append(.marker)
                    } else if arguments.count == 1,
                              arguments[0].lowercased() == "executesntp"
                    {
                        tokens.append(.sntpStart)
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "quicksection"
                    {
                        tokens.append(.quickSection(
                            ["true", "1"].contains(arguments[1].lowercased())
                        ))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "syncobject",
                              arguments.count >= 3, !arguments[2].isEmpty
                    {
                        tokens.append(.syncObjectSet(arguments[2]))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "reset",
                              arguments[1].lowercased() == "syncobject",
                              arguments.count >= 3, !arguments[2].isEmpty
                    {
                        tokens.append(.syncObjectReset(arguments[2]))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "wait",
                              arguments[1].lowercased() == "syncobject",
                              !arguments[2].isEmpty
                    {
                        let timeout = arguments.dropFirst(3).compactMap { option -> Int? in
                            let value = option.lowercased()
                            if value.hasPrefix("--timeout=") {
                                return Int(value.dropFirst("--timeout=".count))
                            }
                            return Int(value)
                        }.first
                        tokens.append(.syncObjectWait(
                            name: arguments[2],
                            timeoutMilliseconds: timeout.flatMap { $0 > 0 ? $0 : nil }
                        ))
                    } else if arguments.count >= 2,
                              ["enter", "leave"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "onlinemode"
                    {
                        tokens.append(.onlineMode(arguments[0].lowercased() == "enter"))
                    } else if arguments.count >= 2,
                              ["enter", "leave"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "nouserbreakmode"
                    {
                        tokens.append(.noUserBreakMode(arguments[0].lowercased() == "enter"))
                    } else if arguments.count >= 2,
                              ["enter", "leave"].contains(arguments[0].lowercased()),
                              ["passivemode", "inductionmode"].contains(arguments[1].lowercased())
                    {
                        tokens.append(.interactionMode(
                            arguments[1].lowercased() == "passivemode" ? .passive : .induction,
                            enabled: arguments[0].lowercased() == "enter"
                        ))
                    } else if arguments.count >= 2,
                              ["enter", "leave"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "selectrect"
                    {
                        tokens.append(.selectRectangle(enabled: arguments[0].lowercased() == "enter"))
                    } else if arguments.count >= 2,
                              ["enter", "leave"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "collisionmode"
                    {
                        tokens.append(.collisionMode(
                            enabled: arguments[0].lowercased() == "enter",
                            showsNames: arguments.count < 3 || arguments[2].lowercased() != "rect"
                        ))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "choicetimeout"
                    {
                        if arguments.count < 3 || arguments[2].isEmpty {
                            tokens.append(.choiceTimeout(.defaultValue))
                        } else if let milliseconds = Int(arguments[2]) {
                            tokens.append(milliseconds <= 0
                                ? .choiceTimeout(.disabled)
                                : .choiceTimeout(.milliseconds(milliseconds)))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "balloontimeout"
                    {
                        if arguments.count < 3 || arguments[2].isEmpty {
                            tokens.append(.balloonTimeout(.defaultValue))
                        } else if let milliseconds = Int(arguments[2]) {
                            tokens.append(milliseconds <= 0
                                ? .balloonTimeout(.disabled)
                                : .balloonTimeout(.milliseconds(milliseconds)))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "balloonwait"
                    {
                        let value = arguments.count >= 3 ? arguments[2].lowercased() : ""
                        if value.isEmpty || value == "1" {
                            tokens.append(.balloonWait(.defaultValue))
                        } else if value.hasSuffix("ms"),
                                  let milliseconds = Int(value.dropLast(2)),
                                  (0 ... 10000).contains(milliseconds)
                        {
                            tokens.append(.balloonWait(.milliseconds(milliseconds)))
                        } else if value.hasSuffix("%"),
                                  let percent = Double(value.dropLast()),
                                  (0 ... 10000).contains(percent)
                        {
                            tokens.append(.balloonWait(.multiplier(percent / 100)))
                        } else if let multiplier = Double(value),
                                  (0 ... 100).contains(multiplier)
                        {
                            tokens.append(.balloonWait(.multiplier(multiplier)))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "balloonoffset",
                              arguments.count >= 4,
                              let x = Self.balloonCoordinate(arguments[2]),
                              let y = Self.balloonCoordinate(arguments[3]),
                              x.unit == .pixel,
                              y.unit == .pixel
                    {
                        tokens.append(.balloonOffset(x: x, y: y))
                    } else if arguments.count >= 3,
                              ["raiseplugin", "notifyplugin"].contains(arguments[0].lowercased())
                    {
                        tokens.append(.pluginEvent(
                            target: arguments[1],
                            id: arguments[2],
                            arguments: Array(arguments.dropFirst(3)),
                            reflectsResponse: arguments[0].lowercased() == "raiseplugin"
                        ))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "balloonalign"
                    {
                        tokens.append(.balloonAlignment(
                            SakuraScriptBalloonAlignment(rawValue: arguments[2].lowercased()) ?? .none
                        ))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "balloonmarker"
                    {
                        tokens.append(.balloonMarker(arguments.count >= 3 ? arguments[2] : ""))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "balloonnum"
                    {
                        tokens.append(.balloonNumber(
                            file: arguments.count >= 3 ? arguments[2] : "",
                            current: arguments.count >= 4 ? arguments[3] : "",
                            maximum: arguments.count >= 5 ? arguments[4] : ""
                        ))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "tasktrayicon",
                              arguments.count >= 3
                    {
                        let options = Array(arguments.dropFirst(3))
                        let tooltip = options.first.flatMap { $0.hasPrefix("--") || $0.isEmpty ? nil : $0 }
                        tokens.append(.contentAction(.setTaskTrayIcon(
                            file: arguments[2],
                            tooltip: tooltip,
                            durationMilliseconds: Self.optionValue("duration", in: options).flatMap(Int.init),
                            runCount: Self.optionValue("runcount", in: options).flatMap(Int.init)
                        )))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "trayballoon"
                    {
                        let options = Array(arguments.dropFirst(2))
                        let text = options.compactMap { Self.optionValue("text", in: [$0]) }
                            .joined(separator: "\n")
                        if !text.isEmpty {
                            tokens.append(.trayBalloon(.init(
                                title: Self.optionValue("title", in: options) ?? "",
                                text: text,
                                icon: Self.optionValue("icon", in: options) ?? "none",
                                timeoutSeconds: min(30, max(10,
                                                            Self.optionValue("timeout", in: options).flatMap(Int.init) ?? 10))
                            )))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "otherghosttalk"
                    {
                        let mode: SakuraScriptOtherGhostTalkMode? = switch arguments[2].lowercased() {
                        case "false": .disabled
                        case "before": .before
                        case "true", "after": .after
                        default: nil
                        }
                        if let mode {
                            tokens.append(.otherGhostTalkMode(mode))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "othersurfacechange",
                              ["true", "false"].contains(arguments[2].lowercased())
                    {
                        tokens.append(.otherSurfaceChangeNotifications(arguments[2].lowercased() == "true"))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "serikotalk",
                              ["true", "false"].contains(arguments[2].lowercased())
                    {
                        tokens.append(.serikoTalk(arguments[2].lowercased() == "true"))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "autoscroll",
                              ["disable", "enable"].contains(arguments[2].lowercased())
                    {
                        tokens.append(.autoscroll(arguments[2].lowercased() == "enable"))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "alpha",
                              let percent = Int(arguments[2])
                    {
                        let options = Array(arguments.dropFirst(3))
                        let namedDuration = options.first { $0.lowercased().hasPrefix("--time=") }
                            .flatMap { Int($0.dropFirst("--time=".count)) }
                        let positionalDuration = options.first.flatMap(Int.init)
                        tokens.append(.surfaceAlpha(
                            percent: percent < 0 ? nil : min(percent, 100),
                            durationMilliseconds: max(0, namedDuration ?? positionalDuration ?? 0),
                            waitsForCompletion: options.contains { $0.lowercased() == "--wait" }
                        ))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "scaling",
                              let horizontalPercent = Int(arguments[2])
                    {
                        let hasSeparateAxes = arguments.count >= 4 && Int(arguments[3]) != nil
                        let verticalPercent = hasSeparateAxes ? Int(arguments[3])! : horizontalPercent
                        let options = Array(arguments.dropFirst(hasSeparateAxes ? 4 : 3))
                        let namedDuration = options.first { $0.lowercased().hasPrefix("--time=") }
                            .flatMap { Int($0.dropFirst("--time=".count)) }
                        let positionalDuration = options.first.flatMap(Int.init)
                        tokens.append(.surfaceScaling(
                            horizontalPercent: horizontalPercent,
                            verticalPercent: verticalPercent,
                            durationMilliseconds: max(0, namedDuration ?? positionalDuration ?? 0),
                            waitsForCompletion: options.contains { $0.lowercased() == "--wait" }
                        ))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              ["alignmentondesktop", "alignmenttodesktop"]
                              .contains(arguments[1].lowercased()),
                              let alignment = SakuraScriptDesktopAlignment(
                                  rawValue: arguments[2].lowercased()
                              )
                    {
                        tokens.append(.desktopAlignment(alignment))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "zorder"
                    {
                        tokens.append(.setZOrder(Array(arguments.dropFirst(2))))
                    } else if arguments.count >= 5,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "position",
                              let x = Int(arguments[2]),
                              let y = Int(arguments[3]),
                              let scope = Int(arguments[4])
                    {
                        tokens.append(.setPosition(x: x, y: y, scope: scope))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "reset",
                              arguments[1].lowercased() == "position"
                    {
                        tokens.append(.resetPosition)
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "reset",
                              arguments[1].lowercased() == "zorder"
                    {
                        tokens.append(.resetZOrder)
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "sticky-window"
                    {
                        let scopes = arguments.dropFirst(2).compactMap(Int.init)
                        tokens.append(.setStickyWindows(scopes))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "reset",
                              arguments[1].lowercased() == "sticky-window"
                    {
                        tokens.append(.resetStickyWindows)
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "browser"
                    {
                        tokens.append(.open(arguments[2]))
                    } else if arguments.count == 2,
                              arguments[0].lowercased() == "open",
                              ["developer", "surfacetest", "shiorirequest", "errorlog"]
                              .contains(arguments[1].lowercased())
                    {
                        tokens.append(.contentAction(.openDeveloperTool(arguments[1].lowercased())))
                    } else if arguments.count == 2,
                              arguments[0].lowercased() == "open",
                              [
                                  "ghostexplorer",
                                  "shellexplorer",
                                  "balloonexplorer",
                                  "headlinesensorexplorer",
                                  "pluginexplorer"
                              ].contains(arguments[1].lowercased())
                    {
                        tokens.append(.contentAction(.openContentExplorer(arguments[1].lowercased())))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "dressupexplorer"
                    {
                        tokens.append(.contentAction(.openDressupExplorer))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              ["pictureviewer", "archiveviewer"].contains(arguments[1].lowercased())
                    {
                        let path = arguments.count >= 3 && !arguments[2].isEmpty ? arguments[2] : nil
                        tokens.append(.contentAction(
                            arguments[1].lowercased() == "pictureviewer"
                                ? .openPictureViewer(path)
                                : .openArchiveViewer(path)
                        ))
                    } else if arguments.count == 2,
                              arguments[0].lowercased() == "open",
                              ["backlogviewer", "calendar", "messenger"].contains(arguments[1].lowercased())
                    {
                        tokens.append(.open(arguments[1]))
                    } else if arguments.count == 2,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "aigraph"
                    {
                        tokens.append(.contentAction(.openAIGraph))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "sound"
                    {
                        let operation = arguments[1].lowercased()
                        switch operation {
                        case "play", "loop":
                            if arguments.count >= 3 {
                                tokens.append(.sound(.play(
                                    file: arguments[2],
                                    loop: operation == "loop",
                                    options: Array(arguments.dropFirst(3))
                                )))
                            } else {
                                tokens.append(.unknown("\\![\(argument)]"))
                            }
                        case "load":
                            if arguments.count >= 3 {
                                tokens.append(.sound(.load(
                                    file: arguments[2],
                                    options: Array(arguments.dropFirst(3))
                                )))
                            } else {
                                tokens.append(.unknown("\\![\(argument)]"))
                            }
                        case "option":
                            tokens.append(.sound(.option(
                                file: arguments.count >= 3 && !arguments[2].isEmpty ? arguments[2] : nil,
                                options: arguments.count >= 4 ? Array(arguments.dropFirst(3)) : []
                            )))
                        case "wait": tokens.append(.sound(.wait))
                        case "pause": tokens.append(.sound(.pause))
                        case "resume": tokens.append(.sound(.resume))
                        case "stop": tokens.append(.sound(.stop))
                        default: tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "anim",
                              ["clear", "stop"].contains(arguments[1].lowercased()),
                              !arguments[2].isEmpty
                    {
                        tokens.append(.stopAnimation(arguments[2]))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "anim",
                              ["pause", "resume"].contains(arguments[1].lowercased()),
                              !arguments[2].isEmpty
                    {
                        tokens.append(arguments[1].lowercased() == "pause"
                            ? .pauseAnimation(arguments[2])
                            : .resumeAnimation(arguments[2]))
                    } else if arguments.count >= 5,
                              arguments[0].lowercased() == "anim",
                              arguments[1].lowercased() == "offset",
                              !arguments[2].isEmpty,
                              let x = Int(arguments[3]),
                              let y = Int(arguments[4])
                    {
                        tokens.append(.offsetAnimation(identifier: arguments[2], x: x, y: y))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "anim",
                              arguments[1].lowercased() == "add"
                    {
                        let kind = arguments[2].lowercased()
                        if kind == "move", arguments.count >= 5,
                           let x = Int(arguments[3]), let y = Int(arguments[4])
                        {
                            tokens.append(.addAnimation(.move(x: x, y: y)))
                        } else if kind == "text", arguments.count >= 8,
                                  let x = Int(arguments[3]), let y = Int(arguments[4]),
                                  let width = Int(arguments[5]), let height = Int(arguments[6])
                        {
                            tokens.append(.addAnimation(.text(
                                x: x,
                                y: y,
                                width: width,
                                height: height,
                                text: arguments[7],
                                durationMilliseconds: arguments.count >= 9 ? max(0, Int(arguments[8]) ?? 0) : 0,
                                color: (
                                    red: arguments.count >= 10 ? Int(arguments[9]) ?? 0 : 0,
                                    green: arguments.count >= 11 ? Int(arguments[10]) ?? 0 : 0,
                                    blue: arguments.count >= 12 ? Int(arguments[11]) ?? 0 : 0
                                ),
                                fontSize: arguments.count >= 13 ? Int(arguments[12]) : nil,
                                fontName: arguments.count >= 14 && !arguments[13].isEmpty ? arguments[13] : nil
                            )))
                        } else if ["overlay", "overlayfast", "base"].contains(kind),
                                  let firstID = Int(arguments[3])
                        {
                            let values = Array(arguments.dropFirst(4))
                            let timing = values.last?.lowercased()
                            let repeats = timing == "always"
                            let numericValues = ["runonce", "always"].contains(timing ?? "")
                                ? Array(values.dropLast()) : values
                            var frames: [SakuraScriptAnimationFrame] = []
                            if numericValues.isEmpty {
                                frames = [.init(surfaceID: firstID)]
                            } else if numericValues.count >= 2,
                                      let firstX = Int(numericValues[0]),
                                      let firstY = Int(numericValues[1])
                            {
                                let firstDuration = numericValues.count >= 3 ? Int(numericValues[2]) ?? 0 : 0
                                frames.append(.init(
                                    surfaceID: firstID,
                                    x: firstX,
                                    y: firstY,
                                    durationMilliseconds: max(0, firstDuration)
                                ))
                                var frameIndex = 3
                                while frameIndex + 3 < numericValues.count,
                                      let surfaceID = Int(numericValues[frameIndex]),
                                      let x = Int(numericValues[frameIndex + 1]),
                                      let y = Int(numericValues[frameIndex + 2]),
                                      let duration = Int(numericValues[frameIndex + 3])
                                {
                                    frames.append(.init(
                                        surfaceID: surfaceID,
                                        x: x,
                                        y: y,
                                        durationMilliseconds: max(0, duration)
                                    ))
                                    frameIndex += 4
                                }
                            }
                            if !frames.isEmpty {
                                tokens.append(.addAnimation(.surfaces(
                                    method: kind,
                                    frames: frames,
                                    repeats: repeats
                                )))
                            } else {
                                tokens.append(.unknown("\\![\(argument)]"))
                            }
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 2,
                              ["lock", "unlock"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "repaint"
                    {
                        tokens.append(.repaintLock(
                            locked: arguments[0].lowercased() == "lock",
                            manual: arguments.dropFirst(2).contains { $0.lowercased() == "manual" }
                        ))
                    } else if arguments.count >= 2,
                              ["lock", "unlock"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "balloonrepaint"
                    {
                        tokens.append(.balloonRepaintLock(
                            locked: arguments[0].lowercased() == "lock",
                            manual: arguments.dropFirst(2).contains { $0.lowercased() == "manual" }
                        ))
                    } else if arguments.count >= 2,
                              ["lock", "unlock"].contains(arguments[0].lowercased()),
                              arguments[1].lowercased() == "balloonmove"
                    {
                        tokens.append(.balloonMoveLock(arguments[0].lowercased() == "lock"))
                    } else if arguments.count >= 3,
                              ["bind", "bind-noevent"].contains(arguments[0].lowercased())
                    {
                        let value = arguments.count >= 4 ? arguments[3] : ""
                        tokens.append(.bind(
                            category: arguments[1],
                            part: arguments[2],
                            enabled: value == "1" ? true : value == "0" ? false : nil,
                            notifiesEvents: arguments[0].lowercased() == "bind"
                        ))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "property"
                    {
                        tokens.append(.setProperty(property: arguments[2], value: arguments.dropFirst(3).joined(separator: ",")))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "get",
                              arguments[1].lowercased() == "property"
                    {
                        tokens.append(.getProperties(eventID: arguments[2], properties: Array(arguments.dropFirst(3))))
                    } else if arguments.count >= 2, arguments[0].lowercased() == "embed" {
                        tokens.append(.embeddedEvent(
                            id: arguments[1],
                            arguments: Array(arguments.dropFirst(2))
                        ))
                    } else if arguments.count >= 2, arguments[0].lowercased() == "raise" {
                        tokens.append(.raisedEvent(
                            id: arguments[1],
                            arguments: Array(arguments.dropFirst(2))
                        ))
                    } else if arguments.count >= 2, arguments[0].lowercased() == "notify" {
                        tokens.append(.notifyEvent(
                            id: arguments[1],
                            arguments: Array(arguments.dropFirst(2))
                        ))
                    } else if arguments.count >= 3,
                              ["raiseother", "notifyother"].contains(arguments[0].lowercased())
                    {
                        tokens.append(.otherEvent(
                            target: arguments[1],
                            id: arguments[2],
                            arguments: Array(arguments.dropFirst(3)),
                            reflectsResponse: arguments[0].lowercased() == "raiseother"
                        ))
                    } else if arguments.count >= 4,
                              ["timerraise", "timernotify"].contains(arguments[0].lowercased()),
                              let milliseconds = Int(arguments[1]),
                              let once = Int(arguments[2])
                    {
                        tokens.append(.timerEvent(
                            milliseconds: max(0, milliseconds),
                            repeats: once == 0,
                            reflectsResponse: arguments[0].lowercased() == "timerraise",
                            id: arguments[3],
                            arguments: Array(arguments.dropFirst(4))
                        ))
                    } else if arguments.count >= 5,
                              ["timerraiseplugin", "timernotifyplugin"].contains(arguments[0].lowercased()),
                              let milliseconds = Int(arguments[1]),
                              let once = Int(arguments[2])
                    {
                        tokens.append(.pluginTimerEvent(
                            target: arguments[3],
                            milliseconds: max(0, milliseconds),
                            repeats: once == 0,
                            reflectsResponse: arguments[0].lowercased() == "timerraiseplugin",
                            id: arguments[4],
                            arguments: Array(arguments.dropFirst(5))
                        ))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "windowstate"
                    {
                        if arguments[2].lowercased() == "stayontop" {
                            tokens.append(.stayOnTop(true))
                        } else if arguments[2].lowercased() == "!stayontop" {
                            tokens.append(.stayOnTop(false))
                        } else if arguments[2].lowercased() == "minimize" {
                            tokens.append(.contentAction(.minimizeWindows))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "save",
                              arguments[1].lowercased() == "wallpaper"
                    {
                        tokens.append(.contentAction(.saveWallpaper))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "restore",
                              arguments[1].lowercased() == "wallpaper"
                    {
                        tokens.append(.contentAction(.restoreWallpaper))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "wallpaper"
                    {
                        let operands = Array(arguments.dropFirst(2))
                        let positional = operands.filter { !$0.hasPrefix("--") }
                        let file = Self.optionValue("file", in: operands)
                            ?? positional.first.flatMap { $0.isEmpty ? nil : $0 }
                        let position = Self.optionValue("position", in: operands)
                            ?? positional.dropFirst().first
                            ?? "center"
                        tokens.append(.contentAction(.setWallpaper(.init(
                            file: file,
                            position: position.lowercased(),
                            color: Self.optionValue("color", in: operands)
                        ))))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "cancel",
                              ["http", "http-get", "ical"].contains(arguments[1].lowercased())
                    {
                        tokens.append(.cancelHTTP(url: arguments.count >= 3 && !arguments[2].isEmpty ? arguments[2] : nil))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "close",
                              arguments[1].lowercased() == "inputbox"
                    {
                        tokens.append(.closeInputBox(id: arguments[2]))
                    } else if arguments.count >= 5,
                              ["timerraiseother", "timernotifyother"].contains(arguments[0].lowercased()),
                              let milliseconds = Int(arguments[1]),
                              let once = Int(arguments[2])
                    {
                        tokens.append(.otherTimerEvent(
                            target: arguments[3],
                            milliseconds: max(0, milliseconds),
                            repeats: once == 0,
                            reflectsResponse: arguments[0].lowercased() == "timerraiseother",
                            id: arguments[4],
                            arguments: Array(arguments.dropFirst(5))
                        ))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "timerraiseother",
                              let milliseconds = Int(arguments[1]),
                              let once = Int(arguments[2])
                    {
                        tokens.append(.otherTimerEvent(
                            target: arguments[3],
                            milliseconds: max(0, milliseconds),
                            repeats: once == 0,
                            reflectsResponse: true,
                            id: "",
                            arguments: []
                        ))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "timernotifyother",
                              let milliseconds = Int(arguments[1]),
                              let once = Int(arguments[2])
                    {
                        tokens.append(.otherTimerEvent(
                            target: arguments[3],
                            milliseconds: max(0, milliseconds),
                            repeats: once == 0,
                            reflectsResponse: false,
                            id: "",
                            arguments: []
                        ))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "change"
                    {
                        switch arguments[1].lowercased() {
                        case "ghost":
                            tokens.append(.contentAction(arguments.dropFirst(3).contains {
                                $0.caseInsensitiveCompare("--option=raise-event") == .orderedSame
                            } ? .changeGhostWithEvent(arguments[2]) : .changeGhost(arguments[2])))
                        case "shell":
                            tokens.append(.contentAction(arguments.dropFirst(3).contains {
                                $0.caseInsensitiveCompare("--option=raise-event") == .orderedSame
                            } ? .changeShellWithEvent(arguments[2]) : .changeShell(arguments[2])))
                        case "balloon": tokens.append(.contentAction(.changeBalloon(arguments[2])))
                        case "calendarskin": tokens.append(.contentAction(.changeCalendarSkin(arguments[2])))
                        default: tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "call",
                              arguments[1].lowercased() == "ghost"
                    {
                        tokens.append(.contentAction(arguments.dropFirst(3).contains {
                            $0.caseInsensitiveCompare("--option=raise-event") == .orderedSame
                        } ? .callGhostWithEvent(arguments[2]) : .callGhost(arguments[2])))
                    } else if arguments[0].lowercased() == "updatebymyself" {
                        tokens.append(.contentAction(.updateGhost))
                    } else if arguments[0].lowercased() == "updateother" {
                        tokens.append(.contentAction(.updateOther(Array(arguments.dropFirst()))))
                    } else if arguments[0].lowercased() == "vanishbymyself" {
                        let values = Array(arguments.dropFirst())
                        let replacement = values.first { !$0.lowercased().hasPrefix("--option=") }
                        let asksConfirmation = values.contains {
                            $0.caseInsensitiveCompare("--option=query") == .orderedSame
                        }
                        tokens.append(.contentAction(.vanishByMyself(
                            replacement: replacement,
                            asksConfirmation: asksConfirmation
                        )))
                    } else if arguments.count >= 2, arguments[0].lowercased() == "update" {
                        let target = arguments[1].lowercased()
                        switch target {
                        case "ghost": tokens.append(.contentAction(.updateGhost))
                        case "balloon": tokens.append(.contentAction(.updateBalloon))
                        case "platform": tokens.append(.contentAction(.updatePlatform))
                        case "all": tokens.append(.contentAction(.updateGhost))
                        default:
                            let targets = target.split(separator: "+").map(String.init)
                            if !targets.isEmpty,
                               targets.allSatisfy({ ["ghost", "shell", "balloon"].contains($0) })
                            {
                                tokens.append(.contentAction(.updateTargets(targets)))
                            } else {
                                tokens.append(.unknown("\\![\(argument)]"))
                            }
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "headline"
                    {
                        tokens.append(.contentAction(.headline(arguments[2])))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "install"
                    {
                        if arguments[2].lowercased() == "path" {
                            tokens.append(.contentAction(.install(.path(arguments[3]))))
                        } else if arguments[2].lowercased() == "url" {
                            tokens.append(.contentAction(.install(.url(
                                arguments[3],
                                type: arguments.count >= 5 ? arguments[4] : nil
                            ))))
                        } else {
                            tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "execute",
                              ["extractarchive", "compressarchive"].contains(arguments[1].lowercased())
                    {
                        let options = Array(arguments.dropFirst(4))
                        let eventID = Self.optionValue("event", in: options)
                        let password = Self.optionValue("password", in: options)
                        if arguments[1].lowercased() == "extractarchive" {
                            tokens.append(.archive(.extract(
                                archivePath: arguments[2],
                                destinationPath: arguments[3],
                                eventID: eventID,
                                password: password
                            )))
                        } else {
                            tokens.append(.archive(.compress(
                                archivePath: arguments[2],
                                sourceDirectoryPath: arguments[3],
                                eventID: eventID,
                                password: password
                            )))
                        }
                    } else if arguments.count >= 3, arguments[0].lowercased() == "otherghosttalk" {
                        let script = arguments.dropFirst(2).joined(separator: ",")
                        tokens.append(.otherGhostTalk(target: arguments[1], script: script))
                    } else if arguments.count >= 4, arguments[0].lowercased() == "othersurfacechange" {
                        tokens.append(.otherSurfaceChange(
                            target: arguments[1],
                            scope: Int(arguments[2]) ?? 0,
                            surfaceID: Int(arguments[3]) ?? 0
                        ))
                    } else if arguments.count == 1,
                              arguments[0].lowercased() == "reloadsurface"
                    {
                        tokens.append(.contentAction(.reloadShell))
                    } else if arguments.count >= 2, arguments[0].lowercased() == "reload" {
                        switch arguments[1].lowercased() {
                        case "ghost": tokens.append(.contentAction(.reloadGhost))
                        case "surface", "shell": tokens.append(.contentAction(.reloadShell))
                        case "balloon": tokens.append(.contentAction(.reloadBalloon))
                        case "shiori": tokens.append(.contentAction(.reloadShiori))
                        case "makoto": tokens.append(.contentAction(.reloadMakoto))
                        case "aigraph": tokens.append(.contentAction(.reloadAIGraph))
                        case "descript":
                            let targetList = arguments.dropFirst(2).joined(separator: " ")
                                .lowercased()
                                .replacingOccurrences(of: "calendar skin", with: "calendar.skin")
                                .replacingOccurrences(of: "calendar plugin", with: "calendar.plugin")
                            let targets = targetList
                                .split(whereSeparator: { $0.isWhitespace })
                                .map(String.init)
                            let effectiveTargets = targets.isEmpty
                                ? ["ghost", "shell", "balloon", "headline", "plugin", "calendar.skin"]
                                : targets
                            var actions: [SakuraScriptContentAction] = []
                            if effectiveTargets.contains("ghost") {
                                actions.append(.reloadGhost)
                            } else {
                                if effectiveTargets.contains("shell") {
                                    actions.append(.reloadShell)
                                }
                                if effectiveTargets.contains("balloon") {
                                    actions.append(.reloadBalloon)
                                }
                            }
                            if effectiveTargets.contains("headline") {
                                actions.append(.reloadHeadlines)
                            }
                            if effectiveTargets.contains("plugin") {
                                actions.append(.reloadPlugins)
                            }
                            if effectiveTargets.contains("calendar.skin") {
                                actions.append(.reloadCalendarSkins)
                            }
                            if actions.isEmpty {
                                tokens.append(.unknown("\\![\(argument)]"))
                            } else {
                                tokens.append(contentsOf: actions.map(SakuraScriptToken.contentAction))
                            }
                        default: tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count == 2,
                              ["load", "unload"].contains(arguments[0].lowercased()),
                              ["shiori", "makoto"].contains(arguments[1].lowercased())
                    {
                        tokens.append(.componentLifecycle(
                            component: arguments[1].lowercased() == "shiori" ? .shiori : .makoto,
                            loads: arguments[0].lowercased() == "load"
                        ))
                    } else if arguments.count == 3,
                              arguments[0].lowercased() == "set",
                              arguments[1].lowercased() == "shioridebugmode",
                              ["true", "false"].contains(arguments[2].lowercased())
                    {
                        tokens.append(.shioriDebugMode(arguments[2].lowercased() == "true"))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "createnar"
                    {
                        let operands = arguments.dropFirst(2).filter { !$0.hasPrefix("--") }
                        let options = arguments.dropFirst(2).filter { $0.hasPrefix("--") }
                        let eventID = Self.optionValue("event", in: options)
                        tokens.append(.archive(.createNar(
                            narPath: operands.first,
                            sourceDirectoryPath: operands.dropFirst().first,
                            eventID: eventID
                        )))
                    } else if arguments.count >= 1, ["move", "moveasync"].contains(arguments[0].lowercased()) {
                        let isAsync = arguments[0].lowercased() == "moveasync"
                        let options = Array(arguments.dropFirst())
                        let x = Self.optionValue("x", in: options).flatMap(Int.init)
                            ?? (options.count >= 1 ? Int(options[0]) : nil)
                        let y = Self.optionValue("y", in: options).flatMap(Int.init)
                            ?? (options.count >= 2 ? Int(options[1]) : nil)
                        let time = Self.optionValue("time", in: options).flatMap(Int.init)
                            ?? (options.count >= 3 ? Int(options[2]) : nil)
                            ?? 0
                        tokens.append(.moveSurface(x: x, y: y, time: max(0, time), isAsync: isAsync, options: options))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "dumpsurface"
                    {
                        let operands = Array(arguments.dropFirst(2))
                        let optionEventID = Self.optionValue("event", in: operands)
                        let positional = operands.filter { !$0.hasPrefix("--") }
                        tokens.append(.archive(.dumpSurface(.init(
                            directoryPath: positional.first,
                            scope: positional.indices.contains(1) ? Int(positional[1]) ?? 0 : 0,
                            surfaceList: positional.indices.contains(2) && !positional[2].isEmpty
                                ? positional[2] : nil,
                            prefix: positional.indices.contains(3) ? positional[3] : "surface",
                            eventID: optionEventID ?? (positional.indices.contains(4) && !positional[4].isEmpty
                                ? positional[4] : nil),
                            cropsFromZero: positional.indices.contains(5) && positional[5] == "1"
                        ))))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "createupdatedata"
                    {
                        let operands = Array(arguments.dropFirst(2))
                        let directoryPath = operands.first { !$0.hasPrefix("--") }
                        let options = operands.filter { $0.hasPrefix("--") }
                        let eventID = Self.optionValue("event", in: options)
                        tokens.append(.archive(.createUpdateData(directoryPath: directoryPath, eventID: eventID)))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "resetwindowpos"
                    {
                        tokens.append(.resetWindowPositions)
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "resetballoonpos"
                    {
                        tokens.append(.resetBalloonPositions)
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              ["configurationdialog", "settingdialog", "preference"].contains(arguments[1].lowercased())
                    {
                        tokens.append(.contentAction(.openConfigurationDialog(
                            arguments.count >= 3 && !arguments[2].isEmpty ? arguments[2] : nil
                        )))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "dialog",
                              let kind = SakuraScriptSystemDialogCommand.Kind(rawValue: arguments[2].lowercased())
                    {
                        let options = Array(arguments.dropFirst(3))
                        tokens.append(.systemDialog(.init(
                            kind: kind,
                            id: Self.optionValue("id", in: options) ?? "",
                            title: Self.optionValue("title", in: options),
                            directory: Self.optionValue("dir", in: options),
                            filter: Self.optionValue("filter", in: options),
                            fileExtension: Self.optionValue("ext", in: options),
                            name: Self.optionValue("name", in: options),
                            color: Self.optionValue("color", in: options)
                        )))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "close",
                              arguments[1].lowercased() == "dialog"
                    {
                        tokens.append(.closeSystemDialog(id: arguments[2]))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "readme"
                    {
                        tokens.append(.contentAction(.openReadme))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "help"
                    {
                        tokens.append(.contentAction(.openHelp))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "terms"
                    {
                        tokens.append(.contentAction(.openTerms))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "file"
                    {
                        tokens.append(.contentAction(.openFile(arguments[2])))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "folder"
                    {
                        tokens.append(.contentAction(.openFolder(arguments[2])))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "open",
                              ["communicatebox", "teachbox"].contains(arguments[1].lowercased())
                    {
                        let initialValue = arguments.count >= 3 ? arguments[2] : ""
                        if arguments[1].lowercased() == "communicatebox" {
                            tokens.append(.communicateBox(initialValue: initialValue))
                        } else {
                            tokens.append(.teachBox(initialValue: initialValue))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              ["inputbox", "passwordinput", "dateinput", "sliderinput", "timeinput", "ipinput"].contains(arguments[1].lowercased())
                    {
                        tokens.append(.inputBox(Self.inputCommand(arguments: arguments)))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "execute",
                              ["http-get", "http-post", "http-head", "http-put", "http-delete", "http-patch", "http-options", "rss-get", "rss-post", "ical-get", "ical-post"]
                              .contains(arguments[1].lowercased())
                    {
                        let isFeed = ["rss-get", "rss-post"].contains(arguments[1].lowercased())
                        let isCalendar = ["ical-get", "ical-post"].contains(arguments[1].lowercased())
                        let method = if isFeed || isCalendar {
                            arguments[1].lowercased().hasSuffix("-get") ? "GET" : "POST"
                        } else {
                            String(arguments[1].dropFirst("http-".count)).uppercased()
                        }
                        let options = Array(arguments.dropFirst(3))
                        let asyncID = Self.optionValue("async", in: options)
                        let syncID = Self.optionValue("sync", in: options)
                        let nofileOption = options.first(where: {
                            $0.lowercased() == "--nofile" || $0.lowercased().hasPrefix("--nofile=")
                        })
                        let headers = options.compactMap { option -> String? in
                            let lowercased = option.lowercased()
                            if lowercased.hasPrefix("--header=") {
                                return String(option.dropFirst(9))
                            }
                            let names = ["accept", "accept-language", "authorization", "cookie", "content-type"]
                            guard let name = names.first(where: { lowercased.hasPrefix("--\($0)=") }) else {
                                return lowercased == "--no-cache" ? "Cache-Control: no-cache" : nil
                            }
                            let value = String(option.dropFirst(name.count + 3))
                            let headerName = [
                                "accept": "Accept",
                                "accept-language": "Accept-Language",
                                "authorization": "Authorization",
                                "cookie": "Cookie",
                                "content-type": "Content-Type"
                            ][name] ?? name
                            return "\(headerName): \(value)"
                        }
                        tokens.append(.http(SakuraScriptHTTPRequest(
                            method: method,
                            url: arguments[2],
                            eventID: syncID ?? asyncID ?? (isCalendar ? "" : nil),
                            waitsForCompletion: syncID != nil,
                            parameters: options.compactMap { option in
                                option.lowercased().hasPrefix("--param=") ? String(option.dropFirst(8)) : nil
                            } + (options.first?.hasPrefix("--") == false ? [options[0]] : []),
                            options: isCalendar ? options : [],
                            headers: headers,
                            timeoutSeconds: Self.optionValue("timeout", in: options).flatMap(Double.init),
                            output: nofileOption.map { option in
                                let encoding = option.firstIndex(of: "=").map {
                                    String(option[option.index(after: $0)...])
                                }
                                return .memory(characterEncoding: encoding)
                            } ?? .file(Self.optionValue("file", in: options)),
                            isFeed: isFeed,
                            isCalendar: isCalendar,
                            notifiesProgress: options.contains {
                                $0.caseInsensitiveCompare("--progress-notify") == .orderedSame
                            },
                            streamingMode: options.first(where: {
                                $0.lowercased() == "--streaming"
                                    || $0.lowercased().hasPrefix("--streaming=")
                            }).map { option in
                                Self.optionValue("streaming", in: [option]) ?? "auto"
                            }
                        )))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              ["schedule-add", "schedule-delete", "schedule-get"].contains(arguments[1].lowercased())
                    {
                        let operation = arguments[1].lowercased()
                        let optionStart = operation == "schedule-delete" ? 3 : 2
                        var options: [String: String] = [:]
                        for option in arguments.dropFirst(optionStart) where option.hasPrefix("--") {
                            let fields = option.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
                            options[fields[0].lowercased()] = fields.count > 1 ? fields[1] : ""
                        }
                        if operation == "schedule-add" {
                            tokens.append(.schedule(.add(options: options)))
                        } else if operation == "schedule-delete", arguments.count >= 3 {
                            tokens.append(.schedule(.delete(uid: arguments[2], eventID: options["event"])))
                        } else if operation == "schedule-get" {
                            tokens.append(.schedule(.get(options: options)))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "filewatch"
                    {
                        let options = Array(arguments.dropFirst(3))
                        tokens.append(.fileWatch(.start(
                            path: arguments[2],
                            eventID: Self.optionValue("async", in: options),
                            debounceMilliseconds: Self.optionValue("debounce", in: options).flatMap(Int.init) ?? 500
                        )))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "cancel",
                              arguments[1].lowercased() == "filewatch"
                    {
                        tokens.append(.fileWatch(.cancel(path: arguments[2])))
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              ["ping", "nslookup"].contains(arguments[1].lowercased())
                    {
                        let options = Array(arguments.dropFirst(2))
                        let host = Self.optionValue("host", in: options) ?? ""
                        let eventID = Self.optionValue("event", in: options) ?? ""
                        if arguments[1].lowercased() == "ping" {
                            tokens.append(.networkDiagnostic(.ping(
                                host: host,
                                eventID: eventID,
                                count: Self.optionValue("count", in: options).flatMap(Int.init) ?? 3,
                                size: Self.optionValue("size", in: options).flatMap(Int.init) ?? 32,
                                timeoutMilliseconds: Self.optionValue("timeout", in: options).flatMap(Int.init) ?? 5000,
                                ttl: Self.optionValue("ttl", in: options).flatMap(Int.init),
                                dontFragment: options.contains { option in
                                    option.caseInsensitiveCompare("--df") == .orderedSame
                                        || Self.optionValue("df", in: [option])?.lowercased() == "true"
                                },
                                data: Self.optionValue("data", in: options)
                            )))
                        } else {
                            tokens.append(.networkDiagnostic(.nslookup(host: host, eventID: eventID)))
                        }
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "emptyrecyclebin"
                    {
                        tokens.append(.emptyRecycleBin)
                    } else if !arguments.isEmpty,
                              arguments[0].lowercased() == "biff"
                    {
                        tokens.append(.checkMail(account: arguments.count >= 2 ? arguments[1] : nil))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "websocket"
                    {
                        let options = Array(arguments.dropFirst(3))
                        tokens.append(.webSocket(.connect(
                            url: arguments[2],
                            eventID: Self.optionValue("event", in: options) ?? "",
                            headers: options.compactMap { option in
                                option.lowercased().hasPrefix("--header=") ? String(option.dropFirst(9)) : nil
                            },
                            protocolName: Self.optionValue("m_websocketProtocol", in: options)
                        )))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "send",
                              arguments[1].lowercased() == "websocket"
                    {
                        tokens.append(.webSocket(.sendText(
                            url: arguments[2], value: arguments.dropFirst(3).joined(separator: "\r\n")
                        )))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "send",
                              arguments[1].lowercased() == "websocket-binary"
                    {
                        tokens.append(.webSocket(.sendBinary(
                            url: arguments[2], value: Data(base64Encoded: arguments[3]) ?? Data()
                        )))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "close",
                              arguments[1].lowercased() == "websocket"
                    {
                        tokens.append(.webSocket(.close(
                            url: arguments[2], code: arguments.count >= 4 ? Int(arguments[3]) ?? 1000 : 1000
                        )))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "cancel",
                              arguments[1].lowercased() == "websocket"
                    {
                        tokens.append(.webSocket(.cancel(url: arguments[2])))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "weather-get",
                              let asyncArgument = arguments.dropFirst(2).first(where: {
                                  $0.lowercased().hasPrefix("--async=")
                              }),
                              let separator = asyncArgument.firstIndex(of: "=")
                    {
                        tokens.append(.weatherGet(
                            eventID: String(asyncArgument[asyncArgument.index(after: separator)...])
                        ))
                    } else {
                        tokens.append(.unknown("\\![\(argument)]"))
                    }
                } else {
                    tokens.append(.unknown("\\!"))
                }
            case "e", "z":
                tokens.append(.end)
                flushText()
                return tokens
            default:
                tokens.append(.unknown(readUnknown(command: command, in: characters, index: &index)))
            }
        }

        flushText()
        return tokens
    }

    private static func balloonCoordinate(_ rawValue: String) -> SakuraScriptBalloonCoordinate? {
        let isRelative = rawValue.hasPrefix("@")
        var number = isRelative ? String(rawValue.dropFirst()) : rawValue
        let unit: SakuraScriptBalloonCoordinate.Unit
        if number.lowercased().hasSuffix("em") {
            number.removeLast(2)
            unit = .em
        } else if number.lowercased().hasSuffix("lh") {
            number.removeLast(2)
            unit = .lineHeight
        } else if number.hasSuffix("%") {
            number.removeLast()
            unit = .percent
        } else {
            unit = .pixel
        }
        guard let value = Double(number), value.isFinite else { return nil }
        return SakuraScriptBalloonCoordinate(value: value, isRelative: isRelative, unit: unit)
    }

    private static func inputCommand(arguments: [String]) -> SakuraScriptInputCommand {
        let type = arguments[1].lowercased()
        let optionStart = arguments.firstIndex { $0.hasPrefix("--") } ?? arguments.endIndex
        let positional = Array(arguments[..<optionStart])
        let options = Array(arguments[optionStart...])
        let timeout = optionValue("timeout", in: options).flatMap(Int.init)
            ?? positional.dropFirst(3).first.flatMap(Int.init)
        let optionText = optionValue("text", in: options)

        let kind: SakuraScriptInputCommand.Kind
        let initialValue: String
        switch type {
        case "passwordinput":
            kind = .password
            initialValue = optionText ?? positional.dropFirst(4).first ?? ""
        case "dateinput":
            kind = .date
            initialValue = optionText ?? positional.dropFirst(4).prefix(3).joined(separator: ",")
        case "sliderinput":
            let values = (optionText ?? positional.dropFirst(4).prefix(3).joined(separator: ","))
                .split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)
            let current = values.dropFirst(0).first.flatMap(Int.init) ?? 0
            let minimum = values.dropFirst(1).first.flatMap(Int.init) ?? 0
            let maximum = values.dropFirst(2).first.flatMap(Int.init) ?? 100
            kind = .slider(minimum: min(minimum, maximum), maximum: max(minimum, maximum))
            initialValue = String(min(max(current, min(minimum, maximum)), max(minimum, maximum)))
        case "timeinput":
            kind = .time
            initialValue = optionText ?? positional.dropFirst(4).prefix(3).joined(separator: ",")
        case "ipinput":
            kind = .ipAddress
            initialValue = optionText ?? positional.dropFirst(4).prefix(4).joined(separator: ",")
        default:
            kind = .text
            initialValue = optionText ?? positional.dropFirst(4).first ?? ""
        }

        return SakuraScriptInputCommand(
            kind: kind,
            id: arguments[2],
            timeoutMilliseconds: timeout,
            initialValue: initialValue,
            maximumLength: optionValue("limit", in: options).flatMap(Int.init),
            references: optionValues("reference", in: options),
            options: options.compactMap { optionValue("option", in: [$0]) },
            balloonID: optionValue("balloon", in: options).flatMap(Int.init)
        )
    }

    private static func optionValues(_ name: String, in options: [String]) -> [String] {
        let prefix = "--\(name.lowercased())="
        return options.compactMap { option in
            guard option.lowercased().hasPrefix(prefix) else { return nil }
            return String(option.dropFirst(prefix.count))
        }
    }

    private static func optionValue(_ name: String, in options: [String]) -> String? {
        let prefix = "--\(name.lowercased())="
        return options.first { $0.lowercased().hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    private func numericArgument(in characters: [Character], index: inout Int) -> Int? {
        if let argument = bracketArgument(in: characters, index: &index) {
            return Int(argument)
        }
        guard index < characters.count, let value = characters[index].wholeNumberValue else {
            return nil
        }
        index += 1
        return value
    }

    private func bracketArgument(in characters: [Character], index: inout Int) -> String? {
        guard index < characters.count, characters[index] == "[" else { return nil }
        index += 1
        var argument = ""
        var depth = 1
        var inQuotes = false
        var isEscaped = false

        while index < characters.count {
            let character = characters[index]
            if isEscaped {
                argument.append(character)
                isEscaped = false
                index += 1
                continue
            }
            if character == "\\" {
                argument.append(character)
                isEscaped = true
                index += 1
                continue
            }
            if character == "\"" {
                inQuotes.toggle()
                argument.append(character)
                index += 1
                continue
            }
            if !inQuotes {
                if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        return argument
                    }
                }
            }
            argument.append(character)
            index += 1
        }
        return nil
    }

    private func encodedCharacter(
        _ argument: String,
        maximum: Int,
        excludesSurrogates: Bool = false
    ) -> String? {
        let value = if argument.lowercased().hasPrefix("0x") {
            Int(argument.dropFirst(2), radix: 16)
        } else {
            Int(argument)
        }
        guard let value,
              (0 ... maximum).contains(value),
              !(excludesSurrogates && (0xD800 ... 0xDFFF).contains(value)),
              let scalar = UnicodeScalar(value)
        else { return nil }
        return String(scalar)
    }

    private func readLiteralSection(
        endingWith delimiter: Character,
        in characters: [Character],
        index: inout Int
    ) -> String {
        var result = ""
        while index < characters.count {
            if index + 2 < characters.count,
               characters[index] == "\\",
               characters[index + 1] == "_",
               characters[index + 2] == delimiter
            {
                index += 3
                break
            }
            result.append(characters[index])
            index += 1
        }
        return result
    }

    private var entityReferences: [String: String] {
        [
            "amp": "&",
            "apos": "'",
            "gt": ">",
            "lt": "<",
            "nbsp": "\u{00A0}",
            "quot": "\"",
            "yen": "¥",
            "cent": "¢",
            "pound": "£",
            "euro": "€",
            "copy": "©",
            "reg": "®",
            "trade": "™",
            "deg": "°",
            "plusmn": "±",
            "sup1": "¹",
            "sup2": "²",
            "sup3": "³",
            "frac14": "¼",
            "frac12": "½",
            "frac34": "¾",
            "times": "×",
            "divide": "÷",
            "half_solidus": "/",
            "bull": "•",
            "hellip": "…",
            "prime": "′",
            "larr": "←",
            "rarr": "→",
            "uarr": "↑",
            "darr": "↓",
            "sect": "§",
            "para": "¶",
            "middot": "·",
            "micro": "µ",
            "laquo": "«",
            "raquo": "»",
            "iquest": "¿",
            "iexcl": "¡"
        ]
    }

    private func readUnknown(
        command: Character,
        in characters: [Character],
        index: inout Int
    ) -> String {
        var raw = "\\\(command)"
        if command == "_" {
            while index < characters.count, characters[index] == "_" {
                raw.append(characters[index])
                index += 1
            }
            if index < characters.count, characters[index].isLetter {
                raw.append(characters[index])
                index += 1
            }
        }
        if let argument = bracketArgument(in: characters, index: &index) {
            raw += "[\(argument)]"
        }
        return raw
    }

    private func splitArguments(_ source: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var isQuoted = false
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                arguments.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        arguments.append(current)
        return arguments
    }
}

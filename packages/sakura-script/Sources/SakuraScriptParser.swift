public struct SakuraScriptParser: Sendable {
    public init() {}

    public func parse(_ script: SakuraScript) -> [SakuraScriptToken] {
        parse(script.rawValue)
    }

    public func parse(_ source: String) -> [SakuraScriptToken] {
        let characters = Array(source)
        var index = 0
        var text = ""
        var tokens: [SakuraScriptToken] = []

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(text))
            text = ""
        }

        while index < characters.count {
            if characters[index] == "%" {
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
                    index += name.count + 1
                    continue
                }
            }
            guard characters[index] == "\\" else {
                text.append(characters[index])
                index += 1
                continue
            }

            guard index + 1 < characters.count else {
                text.append("\\")
                break
            }

            if characters[index + 1] == "\\" {
                text.append("\\")
                index += 2
                continue
            }

            flushText()
            index += 1
            let command = characters[index]
            index += 1

            switch command {
            case "%":
                tokens.append(.text("%"))
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
            case "b":
                if let value = numericArgument(in: characters, index: &index) {
                    tokens.append(.balloonSurface(value))
                } else {
                    tokens.append(.unknown("\\b"))
                }
            case "n":
                _ = bracketArgument(in: characters, index: &index)
                tokens.append(.lineBreak)
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
            case "q":
                if let argument = bracketArgument(in: characters, index: &index) {
                    let arguments = splitArguments(argument)
                    if arguments.count >= 2 {
                        tokens.append(.choice(
                            label: arguments[0],
                            id: arguments[1],
                            arguments: Array(arguments.dropFirst(2))
                        ))
                    } else {
                        tokens.append(.unknown("\\q[\(argument)]"))
                    }
                } else {
                    tokens.append(.unknown("\\q"))
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
                } else if index < characters.count, characters[index] == "q" {
                    index += 1
                    tokens.append(.quickSection(nil))
                } else if index < characters.count, characters[index] == "+" {
                    index += 1
                    tokens.append(.contentAction(.nextGhost))
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
                } else if index < characters.count, characters[index] == "?" {
                    index += 1
                    tokens.append(.unknown("\\_?"))
                } else {
                    tokens.append(.unknown(readUnknown(command: command, in: characters, index: &index)))
                }
            case "c":
                tokens.append(.clear)
            case "!":
                if let argument = bracketArgument(in: characters, index: &index) {
                    let arguments = splitArguments(argument)
                    if argument == "*" {
                        tokens.append(.marker)
                    } else if arguments.count >= 2,
                              arguments[0].lowercased() == "quicksection"
                    {
                        tokens.append(.quickSection(
                            ["true", "1"].contains(arguments[1].lowercased())
                        ))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "browser"
                    {
                        tokens.append(.open(arguments[2]))
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
                              ["bind", "bind-noevent"].contains(arguments[0].lowercased())
                    {
                        let value = arguments.count >= 4 ? arguments[3] : ""
                        tokens.append(.bind(
                            category: arguments[1],
                            part: arguments[2],
                            enabled: value == "1" ? true : value == "0" ? false : nil,
                            notifiesEvents: arguments[0].lowercased() == "bind"
                        ))
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
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "change"
                    {
                        switch arguments[1].lowercased() {
                        case "ghost": tokens.append(.contentAction(.changeGhost(arguments[2])))
                        case "shell": tokens.append(.contentAction(.changeShell(arguments[2])))
                        case "balloon": tokens.append(.contentAction(.changeBalloon(arguments[2])))
                        default: tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "call",
                              arguments[1].lowercased() == "ghost"
                    {
                        tokens.append(.contentAction(.callGhost(arguments[2])))
                    } else if arguments[0].lowercased() == "updatebymyself" {
                        tokens.append(.contentAction(.updateGhost))
                    } else if arguments.count >= 2, arguments[0].lowercased() == "update" {
                        switch arguments[1].lowercased() {
                        case "ghost": tokens.append(.contentAction(.updateGhost))
                        case "balloon": tokens.append(.contentAction(.updateBalloon))
                        default: tokens.append(.unknown("\\![\(argument)]"))
                        }
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "headline"
                    {
                        tokens.append(.contentAction(.headline(arguments[2])))
                    } else if arguments.count >= 3,
                              arguments[0].lowercased() == "open",
                              arguments[1].lowercased() == "inputbox"
                    {
                        tokens.append(.inputBox(
                            id: arguments[2],
                            timeoutMilliseconds: arguments.count >= 4 ? Int(arguments[3]) : nil,
                            initialValue: arguments.count >= 5 ? arguments[4] : ""
                        ))
                    } else if arguments.count >= 4,
                              arguments[0].lowercased() == "execute",
                              arguments[1].lowercased() == "http-get",
                              let asyncArgument = arguments.dropFirst(3).first(where: {
                                  $0.lowercased().hasPrefix("--async=")
                              }),
                              let separator = asyncArgument.firstIndex(of: "=")
                    {
                        tokens.append(.httpGet(
                            url: arguments[2],
                            eventID: String(asyncArgument[asyncArgument.index(after: separator)...])
                        ))
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
            case "e":
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
        while index < characters.count, characters[index] != "]" {
            argument.append(characters[index])
            index += 1
        }
        guard index < characters.count else { return nil }
        index += 1
        return argument
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

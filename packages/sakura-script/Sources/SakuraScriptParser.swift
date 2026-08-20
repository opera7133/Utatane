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
            case "_":
                if index < characters.count, characters[index] == "w" {
                    index += 1
                    if let argument = bracketArgument(in: characters, index: &index),
                       let milliseconds = Int(argument)
                    {
                        tokens.append(.wait(milliseconds: max(0, milliseconds)))
                    } else {
                        tokens.append(.unknown("\\_w"))
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
                    if arguments.count >= 2, arguments[0].lowercased() == "embed" {
                        tokens.append(.embeddedEvent(
                            id: arguments[1],
                            arguments: Array(arguments.dropFirst(2))
                        ))
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

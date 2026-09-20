import Foundation
import UtataneCore

enum NiseDictionaryError: LocalizedError {
    case dictionaryNotFound(URL)
    case unreadableDictionary(URL)

    var errorDescription: String? {
        switch self {
        case let .dictionaryNotFound(url): "偽栞辞書が見つからない: \(url.path)"
        case let .unreadableDictionary(url): "偽栞辞書を読み込めない: \(url.path)"
        }
    }
}

struct NiseCondition: Hashable, Sendable {
    enum Term: Hashable, Sendable {
        case contains(String)
        case comparison(lhs: String, operator: String, rhs: String)
    }

    let terms: [Term]

    init(_ source: String) {
        terms = source.components(separatedBy: "&").map { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            for operation in ["<>", ">=", "<=", ">", "<", "="] {
                if let range = value.range(of: operation) {
                    return .comparison(
                        lhs: String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                        operator: operation,
                        rhs: String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    )
                }
            }
            return .contains(value)
        }
    }
}

struct NiseConditionalScript: Sendable {
    let condition: NiseCondition
    let script: String
}

struct NiseChain: Sendable {
    let keyword: String
    let word: String
}

struct NiseDictionary: Sendable {
    var words: [String: [String]] = [:]
    var typeChains: [String: [NiseChain]] = [:]
    var events: [NiseConditionalScript] = []
    var responses: [NiseConditionalScript] = []
    var greetings: [String: [String]] = [:]
    var resources: [String: String] = [:]
    var news: [String] = []

    static func load(from directory: URL) throws -> Self {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = urls.filter {
            $0.lastPathComponent.lowercased().hasPrefix("ai") && ["txt", "dtx"].contains($0.pathExtension.lowercased())
        }
        let encrypted = candidates.filter { $0.pathExtension.caseInsensitiveCompare("dtx") == .orderedSame }
        let selected = (encrypted.isEmpty ? candidates.filter { $0.pathExtension.caseInsensitiveCompare("txt") == .orderedSame } : encrypted)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !selected.isEmpty else { throw NiseDictionaryError.dictionaryNotFound(directory) }

        var result = Self()
        for url in selected {
            guard let data = try? Data(contentsOf: url) else { throw NiseDictionaryError.unreadableDictionary(url) }
            let clearData = url.pathExtension.caseInsensitiveCompare("dtx") == .orderedSame ? decrypt(data) : data
            guard let source = decode(clearData) else { throw NiseDictionaryError.unreadableDictionary(url) }
            result.parse(source)
        }
        return result
    }

    static func decode(_ data: Data) -> String? {
        let firstLine = Data(data.prefix { $0 != 0x0A })
        let header = String(data: firstLine, encoding: .ascii)?.uppercased() ?? ""
        let preferred: String? = if header.contains("#CHARSET: UTF-8") {
            "UTF-8"
        } else if header.contains("#CHARSET: EUC-KR") {
            "EUC-KR"
        } else if header.contains("#CHARSET: EUC-JP") {
            "EUC-JP"
        } else {
            "Shift_JIS"
        }
        guard let decoded = LegacyTextDecoder.decode(data, preferredCharset: preferred) else { return nil }
        return preferred == "Shift_JIS" ? decoded.replacingOccurrences(of: "¥", with: "\\") : decoded
    }

    /// Decodes the legacy DTX byte-pair format used by encrypted 偽栞 dictionaries.
    static func decrypt(_ data: Data) -> Data {
        var key = 0x61
        var index = 0
        var output: [UInt8] = []
        output.reserveCapacity(data.count / 2)
        while index < data.count {
            if data[index] == 0x40 {
                output.append(0x0A)
                index += 1
                continue
            }
            guard index + 1 < data.count else { break }
            let first = Int(data[index + 1]) - key
            key += 9
            let second = Int(data[index]) - key
            key += 2
            if key > 0xDD {
                key = 0x61
            }
            output.append(UInt8(truncatingIfNeeded: (first & 0x03) | ((second & 0x03) << 2) | ((second & 0x0C) << 2) | ((first & 0x0C) << 4)))
            index += 2
        }
        return Data(output)
    }

    private mutating func parse(_ source: String) {
        for definition in Self.definitions(in: source) {
            let fields = Self.split(definition)
            guard fields.count >= 2 else { continue }
            let command = fields[0].trimmingCharacters(in: .whitespaces)
            let arguments = fields.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            if let key = Self.wordKey(for: command) {
                words[key, default: []].append(contentsOf: arguments.filter { !$0.isEmpty })
                if let bracket = command.firstIndex(of: "[") {
                    let base = String(command[..<bracket])
                    words[base, default: []].append(contentsOf: arguments.filter { !$0.isEmpty })
                }
                continue
            }
            switch command {
            case "\\ch" where arguments.count == 3 || arguments.count == 5:
                let firstType = arguments[0]
                let firstWord = arguments[1]
                words[firstType, default: []].append(firstWord)
                if arguments.count == 3 {
                    typeChains[firstType, default: []].append(.init(keyword: arguments[2], word: firstWord))
                } else {
                    let secondType = arguments[2]
                    let secondWord = arguments[3]
                    words[secondType, default: []].append(secondWord)
                    typeChains[firstType, default: []].append(.init(keyword: arguments[4], word: firstWord))
                    typeChains[secondType, default: []].append(.init(keyword: arguments[4], word: secondWord))
                }
            case "\\e", "\\dms":
                words[command, default: []].append(arguments.joined(separator: ","))
            case "\\nw":
                news.append(arguments.joined(separator: ","))
            case "\\ev" where arguments.count >= 2:
                events.append(.init(condition: .init(arguments[0]), script: arguments.dropFirst().joined(separator: ",")))
            case "\\re" where arguments.count >= 2:
                responses.append(.init(condition: .init(arguments[0]), script: arguments.dropFirst().joined(separator: ",")))
            case "\\hl" where arguments.count >= 2:
                greetings[arguments[0], default: []].append(arguments.dropFirst().joined(separator: ","))
            case "\\id" where arguments.count >= 2:
                let id = arguments[0]
                let value = arguments.dropFirst().joined(separator: ",")
                if ["sakura.recommendsites", "kero.recommendsites", "sakura.portalsites"].contains(id) {
                    let encoded = value.replacingOccurrences(of: " ", with: "\u{1}")
                    resources[id] = [resources[id], encoded].compactMap(\.self).joined(separator: "\u{2}")
                } else {
                    resources[id] = value
                }
            default:
                continue
            }
        }
    }

    static func definitions(in source: String) -> [String] {
        var result: [String] = []
        var current: String?
        var inBlockComment = false
        for rawLine in source.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("/*") {
                inBlockComment = true; continue
            }
            if trimmed.hasPrefix("*/") {
                inBlockComment = false; continue
            }
            if inBlockComment || trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                continue
            }
            if rawLine.first == " " || rawLine.first == "\t" {
                current? += trimmed
            } else {
                if let current {
                    result.append(current)
                }
                current = trimmed
            }
        }
        if let current {
            result.append(current)
        }
        return result
    }

    static func split(_ source: String) -> [String] {
        var result = [""]
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if character == "\\", next < source.endIndex, source[next] == "," {
                result[result.count - 1].append(",")
                index = source.index(after: next)
            } else if character == "," {
                result.append("")
                index = next
            } else {
                result[result.count - 1].append(character)
                index = next
            }
        }
        return result
    }

    private static func wordKey(for command: String) -> String? {
        guard command.hasPrefix("\\") else { return nil }
        let body = command.dropFirst()
        if body.first == "[", command.hasSuffix("]") {
            return command
        }
        let type = body.prefix { $0.isLetter || $0 == "?" }
        guard ["ms", "mz", "ml", "mc", "mh", "mt", "me", "mp", "d", "k"].contains(String(type)) else { return nil }
        let suffix = body.dropFirst(type.count)
        return suffix.isEmpty || (suffix.first == "[" && suffix.last == "]") ? command : nil
    }
}

import Foundation

public enum ShiolinkError: LocalizedError {
    case configuration(String)
    case protocolFailure(String)
    case timeout
    case closed

    public var errorDescription: String? {
        switch self {
        case let .configuration(detail): "SHIOLINK configuration: \(detail)"
        case let .protocolFailure(detail): "SHIOLINK: \(detail)"
        case .timeout: "SHIOLINK response timed out"
        case .closed: "SHIOLINK process is closed"
        }
    }
}

public struct ShiolinkConfiguration: Sendable {
    public let directory: URL
    public let executable: URL
    public let arguments: [String]
    public let charset: String
    public let encoding: String.Encoding
    public let timeout: TimeInterval

    public static func configurationURL(in directory: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        // Keep a Windows installation's original configuration intact when desired.
        for name in ["shiolink.utatane.ini", "shiolink.ini"] {
            if let file = files.first(where: { $0.lastPathComponent.lowercased() == name }) {
                return file
            }
        }
        return nil
    }

    public init(directory: URL, text: String, timeout: TimeInterval = 10) throws {
        guard timeout.isFinite, timeout > 0 else { throw ShiolinkError.configuration("invalid timeout") }
        self.directory = directory.standardizedFileURL
        self.timeout = timeout
        var values: [String: String] = [:]
        var inSection = false
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("[") {
                inSection = line.lowercased() == "[shiolink]"
                continue
            }
            guard inSection, let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            values[key] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        // Original SHIOLINK defaults to ANSI (Japanese Windows: Shift_JIS).
        switch values["charmode"]?.lowercased() {
        case "utf-8", "utf8":
            charset = "UTF-8"
            encoding = .utf8
        case nil, "ansi", "shift_jis", "shift-jis", "sjis", "cp932":
            charset = "Shift_JIS"
            encoding = .shiftJIS
        default:
            throw ShiolinkError.configuration("set charmode = UTF-8, ANSI or Shift_JIS")
        }
        let words = try Self.splitCommand(values["commandline"] ?? "")
        guard let command = words.first, command.hasPrefix("/") else {
            throw ShiolinkError.configuration("commandline must start with an absolute executable path")
        }
        executable = URL(filePath: command)
        arguments = Array(words.dropFirst())
    }

    public init(directory: URL) throws {
        guard let file = Self.configurationURL(in: directory) else {
            throw ShiolinkError.configuration("SHIOLINK.INI not found")
        }
        let data = try Data(contentsOf: file)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            throw ShiolinkError.configuration("INI must be UTF-8 or Shift_JIS")
        }
        try self.init(directory: directory, text: text)
    }

    /// Argument splitting only; never invokes a shell or expands variables/operators.
    static func splitCommand(_ command: String) throws -> [String] {
        var result: [String] = []
        var word = ""
        var quote: Character?
        var started = false
        for character in command {
            guard character != "\0", character != "\r", character != "\n" else {
                throw ShiolinkError.configuration("invalid commandline")
            }
            if let currentQuote = quote {
                if character == currentQuote {
                    quote = nil
                } else {
                    word.append(character)
                }
                started = true
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started {
                    result.append(word)
                }
                word = ""
                started = false
            } else {
                word.append(character)
                started = true
            }
        }
        guard quote == nil else { throw ShiolinkError.configuration("unclosed quote") }
        if started {
            result.append(word)
        }
        return result
    }
}

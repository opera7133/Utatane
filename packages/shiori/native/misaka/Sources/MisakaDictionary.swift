import Foundation

struct MisakaCandidate: Sendable {
    enum Selection: Sendable {
        case random
        case nonoverlap
        case sequential
    }

    let conditions: [String]
    let selection: Selection
    let values: [String]
}

struct MisakaDictionary: Sendable {
    var symbols: [String: [MisakaCandidate]] = [:]
    var debugEnabled = false
    var debugSaoriEnabled = false
    var errorEnabled = false
    var propertyHandlerEnabled = false
    var diagnostics: [String] = []

    static func load(masterDirectoryURL: URL) throws -> Self {
        let iniURL = masterDirectoryURL.appending(path: "misaka.ini")
        let ini = try decode(Data(contentsOf: iniURL))
        let names = dictionaryNames(from: ini)
        var result = Self()
        let options = configurationOptions(from: ini)
        result.debugEnabled = options["debug"] == "1"
        result.debugSaoriEnabled = options["debugsaori"] == "1"
        result.errorEnabled = options["error"] == "1"
        result.propertyHandlerEnabled = options["propertyhandler"] == "1"
        for name in names {
            let url = masterDirectoryURL.appending(path: name.replacingOccurrences(of: "\\", with: "/"))
            guard FileManager.default.fileExists(atPath: url.path) else {
                result.diagnostics.append("dictionary not found: \(name)")
                continue
            }
            try result.parse(decode(Data(contentsOf: url)))
        }
        return result
    }

    private static func configurationOptions(from ini: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in normalizedLines(ini) {
            let fields = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            if fields.count == 2 {
                result[fields[0]] = fields[1]
            }
        }
        return result
    }

    private static func dictionaryNames(from ini: String) -> [String] {
        let lines = normalizedLines(ini)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "dictionaries" }) else {
            return ["misaka.txt"]
        }
        var result: [String] = []
        var inside = false
        for line in lines.dropFirst(start + 1) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value == "{" {
                inside = true; continue
            }
            if value == "}" {
                break
            }
            if inside, !value.isEmpty, !value.hasPrefix("//") {
                result.append(value)
            }
        }
        return result.isEmpty ? ["misaka.txt"] : result
    }

    private static func decode(_ data: Data) throws -> String {
        if let value = String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .utf8) {
            return value
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private mutating func parse(_ text: String) {
        let lines = Self.normalizedLines(text)
        var index = 0
        var commonConditions: [String] = []
        while index < lines.count {
            let header = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if header == "#_Common" {
                index += 1
                var body: [String] = []
                while index < lines.count {
                    let line = lines[index]
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("$") || trimmed == "#_Common" {
                        break
                    }
                    if !trimmed.isEmpty, !trimmed.hasPrefix("//") {
                        body.append(trimmed)
                    }
                    index += 1
                }
                commonConditions = body
                continue
            }
            guard header.hasPrefix("$"), !header.hasPrefix("{$") else {
                index += 1
                continue
            }
            let fields = Self.splitHeader(header)
            let name = fields[0]
            let conditions = commonConditions + fields.dropFirst().filter {
                $0 != "sequential" && $0 != "nonoverlap"
            }
            let selection: MisakaCandidate.Selection = if fields.contains(where: { $0 == "sequential" }) {
                .sequential
            } else if fields.contains(where: { $0 == "nonoverlap" }) {
                .nonoverlap
            } else {
                .random
            }
            index += 1
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            }
            var body: [String] = []
            let usesBlockBody = index < lines.count
                && lines[index].trimmingCharacters(in: .whitespaces) == "{"
            if usesBlockBody {
                index += 1
                var depth = 1
                while index < lines.count, depth > 0 {
                    let line = lines[index]
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed == "{" {
                        depth += 1
                    }
                    if trimmed == "}" {
                        depth -= 1
                        if depth == 0 {
                            index += 1; break
                        }
                    }
                    if depth > 0 {
                        body.append(line)
                    }
                    index += 1
                }
                if depth > 0 {
                    diagnostics.append("unterminated symbol block: \(name)")
                }
            } else {
                while index < lines.count {
                    let line = lines[index]
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("$"), !trimmed.hasPrefix("{$") {
                        break
                    }
                    if !trimmed.hasPrefix("//") {
                        body.append(line)
                    }
                    index += 1
                }
            }
            let values = Self.candidateValues(body, usesBlockBody: usesBlockBody).filter { !$0.isEmpty }
            symbols[name, default: []].append(MisakaCandidate(
                conditions: conditions,
                selection: selection,
                values: values.isEmpty ? [""] : values
            ))
        }
    }

    private static func splitHeader(_ header: String) -> [String] {
        header.split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func candidateValues(_ lines: [String], usesBlockBody: Bool) -> [String] {
        if usesBlockBody {
            var result: [String] = []
            var current: [String] = []
            var depth = 0
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "{" {
                    depth += 1
                }
                if trimmed == "}" {
                    depth -= 1
                }
                if depth == 0, trimmed.isEmpty {
                    if !current.isEmpty {
                        result.append(current.joined(separator: "\n"))
                        current = []
                    }
                } else {
                    current.append(line)
                }
            }
            if !current.isEmpty {
                result.append(current.joined(separator: "\n"))
            }
            return result
        }

        // Without an enclosing block, each top-level line is an independent
        // candidate. Explicit nested blocks still form multiline candidates.
        var result: [String] = []
        var current: [String] = []
        var depth = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "{" {
                if depth == 0, !current.isEmpty {
                    result.append(current.joined(separator: "\n"))
                    current = []
                }
                current.append(line)
                depth += 1
                continue
            }
            if trimmed == "}" {
                depth -= 1
                current.append(line)
                if depth == 0, !current.isEmpty {
                    result.append(current.joined(separator: "\n"))
                    current = []
                }
                continue
            }
            if depth == 0 {
                if !trimmed.isEmpty {
                    result.append(line)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            result.append(current.joined(separator: "\n"))
        }
        return result
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }
}

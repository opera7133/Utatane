import Foundation

public struct ContentPathFilter: Sendable {
    private struct Rule: Sendable {
        let expression: NSRegularExpression
        let includes: Bool
    }

    private let ignoreRules: [Rule]
    private let includeRules: [Rule]

    public static func load(
        from directoryURL: URL,
        ignoreFilename: String,
        includeFilename: String
    ) throws -> ContentPathFilter {
        try ContentPathFilter(
            ignoreRules: loadRules(filename: ignoreFilename, from: directoryURL, allowsNegation: true),
            includeRules: loadRules(filename: includeFilename, from: directoryURL, allowsNegation: false)
        )
    }

    public func includes(relativePath: String) -> Bool {
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        if !includeRules.isEmpty,
           !includeRules.contains(where: { $0.expression.firstMatch(in: relativePath, range: range) != nil })
        {
            return false
        }
        var ignored = false
        for rule in ignoreRules where rule.expression.firstMatch(in: relativePath, range: range) != nil {
            ignored = !rule.includes
        }
        return !ignored
    }

    private static func loadRules(
        filename: String,
        from directoryURL: URL,
        allowsNegation: Bool,
        visited: Set<String> = []
    ) throws -> [Rule] {
        guard !visited.contains(filename) else { return [] }
        let url = directoryURL.appending(path: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        var rules: [Rule] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.lowercased().hasPrefix("include:") {
                let included = String(line.dropFirst("include:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !included.isEmpty, !included.contains("/"), !included.contains("\\") else { continue }
                try rules.append(contentsOf: loadRules(
                    filename: included,
                    from: directoryURL,
                    allowsNegation: allowsNegation,
                    visited: visited.union([filename])
                ))
                continue
            }
            let isNegated = allowsNegation && line.hasPrefix("!")
            let pattern = isNegated ? String(line.dropFirst()) : line
            guard !pattern.isEmpty,
                  let expression = try? NSRegularExpression(pattern: regularExpression(for: pattern))
            else { continue }
            rules.append(Rule(expression: expression, includes: isNegated))
        }
        return rules
    }

    private static func regularExpression(for rawPattern: String) -> String {
        let anchored = rawPattern.hasPrefix("/")
        var pattern = anchored ? String(rawPattern.dropFirst()) : rawPattern
        let directory = pattern.hasSuffix("/")
        if directory {
            pattern.removeLast()
        }
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    result += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                result += "[^/]*"
            } else if character == "?" {
                result += "[^/]"
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = pattern.index(after: index)
        }
        let prefix = anchored || pattern.contains("/") ? "^" : "(?:^|.*/)"
        return prefix + result + (directory ? "(?:/.*)?$" : "$")
    }
}

import Foundation

public struct DeveloperOptions: Sendable, Equatable {
    public struct Rule: Sendable, Equatable {
        public let path: String
        public let options: Set<String>

        public init(path: String, options: Set<String>) {
            self.path = path
            self.options = options
        }
    }

    public let rules: [Rule]

    public init(rules: [Rule] = []) {
        self.rules = rules
    }

    public static func load(from directoryURL: URL) throws -> DeveloperOptions {
        let url = directoryURL.appending(path: "developer_options.txt")
        guard FileManager.default.fileExists(atPath: url.path) else { return DeveloperOptions() }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        var rulesByPath: [String: Rule] = [:]
        var order: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let rawPath = fields.first, !rawPath.isEmpty else { continue }
            let path = rawPath.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty,
                  !path.split(separator: "/").contains("..")
            else { continue }
            let options = Set(fields.dropFirst().map { $0.lowercased() }.filter { !$0.isEmpty })
            if rulesByPath[path] == nil {
                order.append(path)
            }
            rulesByPath[path] = Rule(path: path, options: options)
        }
        return DeveloperOptions(rules: order.compactMap { rulesByPath[$0] })
    }

    public func excludesFromUpdate(relativePath: String) -> Bool {
        excludes(relativePath: relativePath, option: "noupdate")
    }

    public func excludesFromNar(relativePath: String) -> Bool {
        excludes(relativePath: relativePath, option: "nonar")
    }

    public func exclusionPatterns(option: String) -> [String] {
        rules.filter { $0.options.contains(option) }.flatMap { [$0.path, $0.path + "/*"] }
    }

    public static func isStandardExcluded(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map { $0.lowercased() }
        guard let filename = components.last else { return true }
        let excludedFiles = [
            "desktop.ini", "thumbs.db", "folder.htt", "mscreate.dir", ".ds_store", "_catalog.vix"
        ]
        let excludedDirectories = ["profile", "var", "__macosx", "xtrastuf.mac"]
        return excludedFiles.contains(filename)
            || excludedDirectories.contains(where: components.contains)
            || filename.hasSuffix("_variable.cfg")
    }

    private func excludes(relativePath: String, option: String) -> Bool {
        rules.last(where: { Self.matches(relativePath, pattern: $0.path) })?
            .options.contains(option) == true
    }

    private static func matches(_ path: String, pattern: String) -> Bool {
        if !pattern.contains("*"), !pattern.contains("?") {
            return path == pattern || path.hasPrefix(pattern + "/")
        }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return path.range(of: "^\(escaped)(?:/.*)?$", options: .regularExpression) != nil
    }
}

import Foundation
import UtataneCore
import UtataneSakuraScript

/// Native compatibility for "Makoto Basic with Select and Repeat".
///
/// The original translator uses `makoto0.lst` while `\h` is active and
/// `makoto1.lst` while `\u` is active. Each non-comment line containing a
/// comma replaces the text before the first comma with the remainder.
public struct BasicMakotoTranslator: SakuraScriptTranslator {
    private let sakuraRules: [(source: String, replacement: String)]
    private let keroRules: [(source: String, replacement: String)]

    public init(masterDirectoryURL: URL) throws {
        sakuraRules = try Self.loadRules(masterDirectoryURL.appending(path: "makoto0.lst"))
        keroRules = try Self.loadRules(masterDirectoryURL.appending(path: "makoto1.lst"))
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        let manager = FileManager.default
        return manager.fileExists(atPath: masterDirectoryURL.appending(path: "makoto.dll").path)
            && manager.fileExists(atPath: masterDirectoryURL.appending(path: "makoto0.lst").path)
    }

    public func translate(_ script: SakuraScript) -> SakuraScript {
        SakuraScript(rawValue: translate(script.rawValue))
    }

    public func translate(_ source: String) -> String {
        var result = ""
        var segmentStart = source.startIndex
        var rules = sakuraRules
        var cursor = source.startIndex

        while cursor < source.endIndex {
            guard source[cursor] == "\\" else {
                cursor = source.index(after: cursor)
                continue
            }
            let commandEnd = source.index(after: cursor)
            guard commandEnd < source.endIndex, source[commandEnd] == "h" || source[commandEnd] == "u" else {
                cursor = commandEnd
                continue
            }
            result += applying(rules, to: String(source[segmentStart ..< cursor]))
            let afterCommand = source.index(after: commandEnd)
            result += source[cursor ..< afterCommand]
            rules = source[commandEnd] == "h" ? sakuraRules : keroRules
            segmentStart = afterCommand
            cursor = afterCommand
        }
        result += applying(rules, to: String(source[segmentStart...]))
        return result
    }

    private func applying(_ rules: [(source: String, replacement: String)], to source: String) -> String {
        rules.reduce(source) { value, rule in
            value.replacingOccurrences(of: rule.source, with: rule.replacement)
        }
    }

    private static func loadRules(_ url: URL) throws -> [(source: String, replacement: String)] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let source = LegacyTextDecoder.decode(data) else { return [] }
        return source.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("["),
                  let comma = line.firstIndex(of: ",")
            else { return nil }
            let original = String(line[..<comma])
            guard !original.isEmpty else { return nil }
            return (original, String(line[line.index(after: comma)...]))
        }
    }
}

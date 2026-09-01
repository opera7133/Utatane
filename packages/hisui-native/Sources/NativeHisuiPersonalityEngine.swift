import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

private struct HisuiEntry: Sendable {
    let token: String
    let condition: String?
    let fallback: String?
    let scripts: [String]
}

public final class NativeHisuiPersonalityEngine: PersonalityEngine, @unchecked Sendable {
    private let adapter = GhostEventShioriAdapter()
    private var entries: [String: [HisuiEntry]] = [:]
    private var selfName = ""
    private var keroName = ""

    public init(masterDirectoryURL: URL) throws {
        try loadDescription(masterDirectoryURL)
        let urls = try dictionaryURLs(masterDirectoryURL)
        for url in urls {
            guard let source = try LegacyTextDecoder.decode(Data(contentsOf: url)) else { continue }
            parse(source)
        }
    }

    public static func supports(shioriFilename: String?) -> Bool {
        shioriFilename?.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?
            .caseInsensitiveCompare("hisui.dll") == .orderedSame
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        let request = adapter.request(for: event)
        let requestID = request.id ?? ""
        let start = requestID.caseInsensitiveCompare("OnChoiceSelect") == .orderedSame
            ? request.reference(0) ?? requestID : requestID
        guard let value = evaluate(token: start, request: request, visited: []) else { return nil }
        return value.isEmpty ? nil : SakuraScript(rawValue: value)
    }

    private func evaluate(token: String, request: ShioriRequest, visited: Set<String>) -> String? {
        guard visited.count < 32, !visited.contains(token.lowercased()) else { return nil }
        var visited = visited
        visited.insert(token.lowercased())
        guard let candidates = entries.first(where: { $0.key.caseInsensitiveCompare(token) == .orderedSame })?.value else { return nil }
        for entry in candidates {
            if let condition = entry.condition, !matches(condition, request: request) {
                if let fallback = entry.fallback, let value = evaluate(token: fallback, request: request, visited: visited) {
                    return value
                }
                continue
            }
            let directlySupported = entry.scripts.filter {
                !$0.contains("%if(") && !$0.contains("%switch(") && !$0.contains("%while(")
            }
            guard let script = (directlySupported.isEmpty ? entry.scripts : directlySupported).randomElement() else { continue }
            return expand(script, request: request, visited: visited)
        }
        return nil
    }

    private func expand(_ source: String, request: ShioriRequest, visited: Set<String>) -> String {
        var value = source
        for index in 0 ... 31 {
            if let reference = request.reference(index) {
                value = value.replacingOccurrences(of: "%ref\(index)", with: reference)
            }
        }
        value = value.replacingOccurrences(of: "%selfname", with: selfName)
        value = value.replacingOccurrences(of: "%keroname", with: keroName)
        value = replacing(pattern: #"%BYTE\[(\d+)\]"#, in: value) { capture in
            UnicodeScalar(Int(capture) ?? 0).map(String.init) ?? ""
        }
        value = replacing(pattern: #"%token\[([^]]+)\]"#, in: value) { token in
            evaluate(token: token, request: request, visited: visited) ?? ""
        }
        return value
    }

    private func matches(_ source: String, request: ShioriRequest) -> Bool {
        let expanded = conditionValue(source, request: request)
        for op in ["==", "!=", ">=", "<=", ">", "<"] where expanded.contains(op) {
            let parts = expanded.components(separatedBy: op)
            guard parts.count == 2 else { return false }
            let lhs = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            let rhs = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if let l = Double(lhs), let r = Double(rhs) {
                return ["==": l == r, "!=": l != r, ">=": l >= r, "<=": l <= r, ">": l > r, "<": l < r][op] ?? false
            }
            return op == "==" ? lhs == rhs : op == "!=" ? lhs != rhs : false
        }
        return expanded != "0" && !expanded.isEmpty
    }

    private func conditionValue(_ source: String, request: ShioriRequest) -> String {
        var value = source
        for index in 0 ... 31 {
            if let reference = request.reference(index) {
                value = value.replacingOccurrences(of: "%ref\(index)", with: reference)
            }
        }
        if value.contains("%[__ID]") {
            value = value.replacingOccurrences(of: "%[__ID]", with: request.id ?? "")
        }
        return value
    }

    private func parse(_ source: String) {
        let withoutComments = source.replacingOccurrences(of: #"(?m)//.*$"#, with: "", options: .regularExpression)
        for body in topLevelBlocks(in: withoutComments) {
            let fields = fields(in: body)
            guard let token = fields["token"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { continue }
            let entry = HisuiEntry(
                token: token,
                condition: fields["conditional"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                fallback: fields["conditionalelse"]?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                scripts: fields["script", default: []].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            )
            entries[token, default: []].append(entry)
        }
    }

    private func topLevelBlocks(in source: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var blockStart: String.Index?
        for index in source.indices {
            switch source[index] {
            case "{":
                if depth == 0 {
                    blockStart = source.index(after: index)
                }
                depth += 1
            case "}" where depth > 0:
                depth -= 1
                if depth == 0 {
                    if let start = blockStart {
                        result.append(String(source[start ..< index]))
                    }
                    blockStart = nil
                }
            default:
                break
            }
        }
        return result
    }

    private func fields(in body: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var key: String?
        var value = ""
        func finish() {
            guard let key else { return }
            result[key, default: []].append(value)
        }
        for line in body.components(separatedBy: .newlines) {
            if let colon = line.firstIndex(of: ":") {
                let candidate = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if ["token", "conditional", "conditionalelse", "script"].contains(candidate) {
                    finish()
                    key = candidate
                    value = String(line[line.index(after: colon)...])
                    continue
                }
            }
            if key != nil {
                value += "\n" + line
            }
        }
        finish()
        return result
    }

    private func dictionaryURLs(_ master: URL) throws -> [URL] {
        let manager = FileManager.default
        let rootFiles = try manager.contentsOfDirectory(at: master, includingPropertiesForKeys: nil)
        let directories = rootFiles.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
                url.lastPathComponent.lowercased().contains("hisui")
        }
        return try directories.flatMap { directory in
            try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "tlk" }
        }
    }

    private func loadDescription(_ directory: URL) throws {
        let url = directory.appending(path: "descript.txt")
        guard let source = try LegacyTextDecoder.decode(Data(contentsOf: url)) else { return }
        for line in source.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "sakura.name" {
                selfName = parts[1]
            }
            if parts[0] == "kero.name" {
                keroName = parts[1]
            }
        }
    }
}

private func replacing(pattern: String, in source: String, transform: (String) -> String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
    var value = source
    for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
        guard let whole = Range(match.range, in: value), let capture = Range(match.range(at: 1), in: value) else { continue }
        value.replaceSubrange(whole, with: transform(String(value[capture])))
    }
    return value
}

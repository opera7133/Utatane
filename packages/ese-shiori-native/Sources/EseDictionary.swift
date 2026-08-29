import Foundation

struct EseRule: Sendable {
    enum Kind: Sendable { case event, response, resource }
    let kind: Kind
    let conditions: [String]
    var values: [String]
}

struct EseDictionary: Sendable {
    var entries: [String: [String]] = [:]
    var rules: [EseRule] = []

    static func load(masterDirectoryURL: URL, charset: String) throws -> Self {
        let files = try FileManager.default.contentsOfDirectory(
            at: masterDirectoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.lowercased().hasPrefix("eseai_") }
        var selected: [String: URL] = [:]
        for file in files where ["dic", "txt"].contains(file.pathExtension.lowercased()) {
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            if selected[stem]?.pathExtension.lowercased() != "txt" || file.pathExtension.lowercased() == "txt" {
                selected[stem] = file
            }
        }
        var result = Self()
        for file in selected.values.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try EseDictionaryDecoder.decode(Data(contentsOf: file), charset: charset) else { continue }
            result.parse(text)
        }
        return result
    }

    mutating func parse(_ text: String) {
        var entry: String?
        var ruleIndex: Int?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("##") {
                entry = nil
                let kind: EseRule.Kind
                if trimmed.hasPrefix("##EVNT") {
                    kind = .event
                } else if trimmed.hasPrefix("##RESP") {
                    kind = .response
                } else if trimmed.hasPrefix("##GETS") {
                    kind = .resource
                } else {
                    ruleIndex = nil; continue
                }
                let conditions = Self.quotedStrings(in: trimmed)
                rules.append(EseRule(kind: kind, conditions: conditions, values: []))
                ruleIndex = rules.indices.last
                continue
            }
            if trimmed.hasPrefix("#") {
                ruleIndex = nil
                entry = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let entry {
                entries[entry, default: []].append(line)
            } else if let ruleIndex {
                rules[ruleIndex].values.append(line)
            }
        }
    }

    private static func quotedStrings(in text: String) -> [String] {
        var result: [String] = [], current = ""
        var quoted = false, escaped = false
        for character in text {
            if escaped {
                current.append(character); escaped = false; continue
            }
            if character == "\\", quoted {
                escaped = true; current.append(character); continue
            }
            if character == "\"" {
                if quoted {
                    result.append(current); current = ""
                }
                quoted.toggle()
            } else if quoted {
                current.append(character)
            }
        }
        return result
    }
}

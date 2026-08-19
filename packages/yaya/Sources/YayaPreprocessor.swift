import Foundation

public struct YayaPreprocessor {
    public init() {}

    public func process(source: String, globalDefinitions: inout [String: String]) -> String {
        var definitions = globalDefinitions
        var output: [String] = []

        for sourceLine in source.components(separatedBy: .newlines) {
            let line = sourceLine.trimmingCharacters(in: .whitespaces)
            if let definition = parseDefinition(line, directive: "#globaldefine") {
                definitions[definition.name] = definition.replacement
                globalDefinitions[definition.name] = definition.replacement
                output.append("")
            } else if let definition = parseDefinition(line, directive: "#define") {
                definitions[definition.name] = definition.replacement
                output.append("")
            } else {
                output.append(expand(sourceLine, definitions: definitions))
            }
        }
        return output.joined(separator: "\n")
    }

    private func parseDefinition(_ line: String, directive: String) -> (name: String, replacement: String)? {
        guard line.hasPrefix(directive) else { return nil }
        let remainder = line.dropFirst(directive.count).trimmingCharacters(in: .whitespaces)
        guard let separator = remainder.firstIndex(where: { $0.isWhitespace }) else {
            return remainder.isEmpty ? nil : (String(remainder), "")
        }
        let name = String(remainder[..<separator])
        var replacement = remainder[separator...].trimmingCharacters(in: .whitespaces)
        if let comment = replacement.range(of: "//") {
            replacement = replacement[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        if let comment = replacement.range(of: "/*") {
            replacement = replacement[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : (name, String(replacement))
    }

    private func expand(_ line: String, definitions: [String: String]) -> String {
        var result = line
        let definitions = definitions.sorted { $0.key.count > $1.key.count }
        for _ in 0 ..< 16 {
            let previous = result
            for (name, replacement) in definitions {
                result = result.replacingOccurrences(of: name, with: replacement)
            }
            if result == previous {
                break
            }
        }
        return result
    }
}

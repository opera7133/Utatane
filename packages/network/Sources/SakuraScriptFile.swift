import Foundation

public struct SakuraScriptFile: Sendable {
    public enum Step: Equatable, Sendable {
        case ghost(String)
        case script(String, waitsForPrevious: Bool)
        case wait(milliseconds: Int)
    }

    public let steps: [Step]

    public init(data: Data) throws {
        guard let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        var steps: [Step] = []
        var validType = false
        for line in source.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") {
                continue
            }
            guard let comma = line.firstIndex(of: ",") else { throw CocoaError(.fileReadCorruptFile) }
            let key = line[..<comma].lowercased()
            let value = String(line[line.index(after: comma)...])
            switch key {
            case "type": validType = value == "sakura_script_file"
            case "ghost": steps.append(.ghost(value))
            case "script": steps.append(.script(value, waitsForPrevious: true))
            case "script_nowait": steps.append(.script(value, waitsForPrevious: false))
            case "wait":
                guard let milliseconds = Int(value), (0 ... 86_400_000).contains(milliseconds) else { throw CocoaError(.fileReadCorruptFile) }
                steps.append(.wait(milliseconds: milliseconds))
            case "version": guard value == "1.0" else { throw CocoaError(.fileReadCorruptFile) }
            case "charset", "name", "craftman", "craftmanurl": break
            default: throw CocoaError(.fileReadCorruptFile)
            }
        }
        guard validType else { throw CocoaError(.fileReadCorruptFile) }
        self.steps = steps
    }
}

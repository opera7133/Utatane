import Foundation
import UtataneCore

public struct DescriptParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> [String: String] {
        text.components(separatedBy: .newlines).reduce(into: [:]) { result, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//"),
                  let separator = trimmed.firstIndex(of: ",")
            else {
                return
            }

            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: separator)
            let value = trimmed[valueStart...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
    }

    public func parse(contentsOf url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        guard let text = LegacyTextDecoder.decode(data) else {
            throw GhostPackageError.unsupportedTextEncoding(url)
        }
        return parse(text)
    }
}

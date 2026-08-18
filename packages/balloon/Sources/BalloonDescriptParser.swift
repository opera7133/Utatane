import Foundation

struct BalloonDescriptParser: Sendable {
    func parse(_ text: String) -> [String: String] {
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
}

import Foundation

/// Explicit holiday tables; no guessed dates or online request at ghost startup.
public struct HolidayInfo: Sendable {
    public let name: String
    public let date: String
    public let countryCode: String
    public var references: [Int: String] {
        [0: name, 1: date, 2: countryCode]
    }

    public static func today(
        at date: Date = Date(), countryCode: String = Locale.current.region?.identifier ?? "",
        timeZone: TimeZone = .current, userDirectory: URL? = nil,
        bundledDirectory: URL? = nil
    ) -> Self? {
        let bundled = bundledDirectory ?? Bundle.module.resourceURL
        let code = countryCode.uppercased()
        let validCode = code.utf8.count == 2 && code.utf8.allSatisfy { (65 ... 90).contains($0) }
        let roots = [userDirectory, bundled].compactMap(\.self)
        var candidates: [(URL, String)] = []
        if validCode {
            candidates += roots.map { ($0.appending(path: "holidays-\(code).txt"), code) }
        }
        candidates += roots.map { ($0.appending(path: "holidays.txt"), "") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        for (file, code) in candidates {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            // An existing country/override table is authoritative, even when
            // empty or unreadable. Do not mix in another country's holidays.
            guard let data = try? Data(contentsOf: file), data.count <= 1024 * 1024,
                  let text = LegacyTextDecoder.decode(data) else { return nil }
            guard let name = parse(text)[key] else { return nil }
            return Self(name: name, date: String(format: "%04d,%02d,%02d", year, month, day), countryCode: code)
        }
        return nil
    }

    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "")
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: ",") else { continue }
            let parts = line[..<separator].split(whereSeparator: { $0 == "/" || $0 == "-" })
            guard parts.count == 3 else { continue }
            let fields = parts.compactMap { Int($0) }
            let name = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard fields.count == 3, (1 ... 9999).contains(fields[0]), !name.isEmpty, !name.contains("\0"),
                  let date = calendar.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2])),
                  calendar.component(.year, from: date) == fields[0],
                  calendar.component(.month, from: date) == fields[1], calendar.component(.day, from: date) == fields[2] else { continue }
            result[String(format: "%04d-%02d-%02d", fields[0], fields[1], fields[2])] = name
        }
        return result
    }
}

import Foundation

struct FirstTodoItem: Codable, Equatable, Sendable {
    var id = UUID().uuidString
    var text: String
    var completed = false
}

enum FirstReminderRepeatRule: Codable, Equatable, Sendable {
    case everyMinutes(Int)
    case daily(hour: Int, minute: Int)
}

struct FirstReminder: Codable, Equatable, Sendable {
    var id = UUID().uuidString
    var text: String
    var dueDate: Date
    var repeatRule: FirstReminderRepeatRule? = nil
    var filePath: String? = nil

    static func validatedFilePath(_ input: String) -> String? {
        let path = (input as NSString).expandingTildeInPath
        guard path.hasPrefix("/"), path.count <= 4096,
              !path.contains(where: { ",[]\\\"%".contains($0) || $0.unicodeScalars.contains(where: { $0.value < 32 }) }) else { return nil }
        return path
    }

    var fileOpenScript: String {
        guard let filePath, let path = Self.validatedFilePath(filePath) else { return "" }
        return "\\![open,file,\(path)]"
    }

    func followingDate(after now: Date, calendar: Calendar = .current) -> Date? {
        switch repeatRule {
        case let .everyMinutes(minutes):
            guard (1 ... 525_600).contains(minutes) else { return nil }
            let interval = TimeInterval(minutes * 60)
            let steps = max(1, floor(now.timeIntervalSince(dueDate) / interval) + 1)
            return dueDate.addingTimeInterval(steps * interval)
        case let .daily(hour, minute):
            return calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
        case nil: return nil
        }
    }

    static func parse(_ input: String, now: Date) -> FirstReminder? {
        let fields = input.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard fields.count == 2 else { return nil }
        let schedule = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let text = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { return nil }
        let dueDate: Date?
        let repeatRule: FirstReminderRepeatRule?
        if schedule.hasPrefix("every"), schedule.hasSuffix("m"),
           let minutes = Int(schedule.dropFirst(5).dropLast()), (1 ... 525_600).contains(minutes)
        {
            dueDate = now.addingTimeInterval(TimeInterval(minutes * 60))
            repeatRule = .everyMinutes(minutes)
        } else if schedule.hasPrefix("daily") {
            let time = schedule.dropFirst(5).split(separator: ":", omittingEmptySubsequences: false)
            guard time.count == 2, time.allSatisfy({ $0.count == 2 }),
                  let hour = Int(time[0]), let minute = Int(time[1]),
                  (0 ... 23).contains(hour), (0 ... 59).contains(minute) else { return nil }
            repeatRule = .daily(hour: hour, minute: minute)
            dueDate = Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
        } else if schedule.hasSuffix("m"), let minutes = Int(schedule.dropLast()), (1 ... 525_600).contains(minutes) {
            dueDate = now.addingTimeInterval(TimeInterval(minutes * 60))
            repeatRule = nil
        } else {
            let formatter = dateFormatter()
            dueDate = formatter.date(from: schedule).flatMap { formatter.string(from: $0) == schedule ? $0 : nil }
            repeatRule = nil
        }
        guard let dueDate, dueDate > now else { return nil }
        return FirstReminder(text: text, dueDate: dueDate, repeatRule: repeatRule)
    }

    static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter
    }
}

enum FirstUtilityText {
    /// Neutral host UI, never attributed to the ghost's dialogue.
    static func hostNotice(_ text: String) -> String {
        "\\n\\_q[Utatane] \(literal(text))\\_q\\n"
    }

    /// Stored notes are plain text; escape scripting and percent expansions.
    static func literal(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func gravity(_ input: String) -> String? {
        // Tjtogvform: percent-encode SJIS lead bytes, CharLowerBuffA on
        // the ASCII stream, then decode. Uppercase ASCII trail bytes also
        // become lowercase, producing the original deliberate mojibake.
        guard let encoded = input.data(using: .shiftJIS) else { return nil }
        let lowered = Data(encoded.map { (65 ... 90).contains($0) ? $0 + 32 : $0 })
        return String(data: lowered, encoding: .shiftJIS)
    }
}

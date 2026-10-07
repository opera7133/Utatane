import Foundation
import UtataneCore
import UtatanePlatformMacOS
import UtataneSakuraScript

enum SakuraScriptCalendarSupport {
    static func options(_ command: SakuraScriptHTTPRequest) -> [String: String] {
        var result: [String: String] = [:]
        for option in command.options where option.hasPrefix("--") {
            let fields = option.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
            result[fields[0].lowercased()] = fields.count > 1 ? fields[1] : ""
        }
        return result
    }

    static func completeEvent(data: Data, command: SakuraScriptHTTPRequest) throws -> GhostEvent {
        guard let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        _ = try ICalendarCodec().decode(source)
        let id = command.eventID?.hasPrefix("On") == true ? command.eventID! : "OnExecuteICalComplete"
        return .shiori(id: id, references: references(source: source, options: options(command)))
    }

    static func failureEvent(
        command: SakuraScriptHTTPRequest,
        reason: String,
        cookie: String = "",
        headers: String = ""
    ) -> GhostEvent {
        let id = command.eventID?.hasPrefix("On") == true
            ? command.eventID! + "Failure"
            : "OnExecuteICalFailure"
        return .shiori(id: id, references: [
            0: command.method.lowercased(), 1: command.eventID ?? "", 2: command.url,
            3: "", 4: reason, 5: cookie, 6: headers
        ])
    }

    static func references(source: String, options: [String: String] = [:]) -> [Int: String] {
        let schedules = (try? ICalendarCodec().decode(source)) ?? []
        let periodMode = ["from", "to", "expand", "limit"].contains { options[$0] != nil }
        var filtered: [(schedule: UtataneSchedule, occurrenceDay: Date?)] = schedules.map { ($0, nil) }
        var from: Date?
        var to: Date?
        if periodMode {
            let calendar = Calendar.current
            let lower = options["from"].flatMap { ICalendarDateParser.parse($0) } ?? calendar.startOfDay(for: Date())
            let days = options["expand"].map { Int($0) ?? 30 } ?? 1830
            let maximumEnd = calendar.date(byAdding: .day, value: 1830, to: lower)!
            let requestedEnd = options["to"].flatMap { ICalendarDateParser.parse($0) }
                .flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
                ?? calendar.date(byAdding: .day, value: max(0, min(1830, days)), to: lower)!
            let upper = min(maximumEnd, requestedEnd)
            from = lower
            to = upper.addingTimeInterval(-1)
            if upper <= lower {
                filtered = []
            } else {
                let range = DateInterval(start: lower, end: upper)
                filtered = schedules.flatMap { schedule -> [(schedule: UtataneSchedule, occurrenceDay: Date?)] in
                    let occurrences = schedule.occurrences(in: range)
                    var entries: [(schedule: UtataneSchedule, occurrenceDay: Date?)] = []
                    for occurrence in occurrences {
                        let days = CalendarRecurrence.occurrenceDays(start: occurrence.start, end: occurrence.end, excluded: schedule.excludedDates ?? [], in: range)
                        for day in days {
                            entries.append((occurrence, day))
                            if options["expand"] == nil {
                                return entries
                            }
                        }
                    }
                    return entries
                }.sorted { left, right in
                    left.occurrenceDay == right.occurrenceDay ? left.schedule.start < right.schedule.start : left.occurrenceDay! < right.occurrenceDay!
                }
            }
        }
        let limit = options["limit"].flatMap(Int.init) ?? (periodMode ? 200 : 0)
        let selected = limit == 0 ? filtered : Array(filtered.prefix(max(0, limit)))
        let fields = calendarFields(source)
        var result = [
            0: [
                fields["X-WR-CALNAME"] ?? "",
                fields["X-WR-TIMEZONE"] ?? "",
                fields["CALSCALE"] ?? "GREGORIAN",
                String(selected.count),
                String(schedules.count),
                from.map { sspDate($0, allDay: true) } ?? "",
                to.map { sspDate($0, allDay: true) } ?? ""
            ].joined(separator: "\u{1}")
        ]
        for (index, entry) in selected.enumerated() {
            let schedule = entry.schedule
            let end = schedule.isAllDay
                ? Calendar.current.date(byAdding: .day, value: -1, to: schedule.end) ?? schedule.end
                : schedule.end
            result[index + 1] = [
                schedule.uid ?? schedule.id.uuidString,
                sspDate(schedule.start, allDay: schedule.isAllDay),
                sspDate(end, allDay: schedule.isAllDay),
                escaped(schedule.caption),
                escaped(schedule.subtitle),
                escaped(schedule.location ?? ""),
                escaped(schedule.url ?? ""),
                schedule.status ?? "",
                escaped(schedule.type),
                schedule.recurrenceRule ?? "",
                schedule.isAllDay ? "1" : "0",
                entry.occurrenceDay.map { sspDate($0, allDay: true) } ?? ""
            ].joined(separator: "\u{1}")
        }
        return result
    }

    private static func calendarFields(_ source: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in source.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].split(separator: ";", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
            if ["X-WR-CALNAME", "X-WR-TIMEZONE", "CALSCALE"].contains(key) {
                result[key] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    private static func sspDate(_ source: String?) -> String {
        guard let source, source.count >= 8 else { return "" }
        return "\(source.prefix(4)),\(source.dropFirst(4).prefix(2)),\(source.dropFirst(6).prefix(2)),,,"
    }

    private static func sspDate(_ date: Date, allDay: Bool) -> String {
        let values = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return [values.year, values.month, values.day, allDay ? nil : values.hour, allDay ? nil : values.minute, allDay ? nil : values.second]
            .map { $0.map(String.init) ?? "" }.joined(separator: ",")
    }

    private static func escaped(_ source: String) -> String {
        source.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}

import Foundation
import UtataneCore
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
        let limit = options["limit"].flatMap(Int.init)
        let selected = limit.map { $0 == 0 ? schedules : Array(schedules.prefix(max(0, $0))) } ?? schedules
        let fields = calendarFields(source)
        var result = [
            0: [
                fields["X-WR-CALNAME"] ?? "",
                fields["X-WR-TIMEZONE"] ?? "",
                fields["CALSCALE"] ?? "GREGORIAN",
                String(selected.count),
                String(schedules.count),
                sspDate(options["from"]),
                sspDate(options["to"])
            ].joined(separator: "\u{1}")
        ]
        for (index, schedule) in selected.enumerated() {
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
                ""
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

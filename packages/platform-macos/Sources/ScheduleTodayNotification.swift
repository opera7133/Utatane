import Foundation

public struct ScheduleTodayNotificationItem: Equatable, Sendable {
    public let type: String
    public let caption: String
    public let subtitle: String
    public let script: String
    public let start: Date
    public let end: Date?
    public let isAllDay: Bool

    public init(
        type: String,
        caption: String,
        subtitle: String,
        script: String,
        start: Date,
        end: Date?,
        isAllDay: Bool
    ) {
        self.type = type
        self.caption = caption
        self.subtitle = subtitle
        self.script = script
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

public enum ScheduleTodayNotificationFormatter {
    public static func references(
        for items: [ScheduleTodayNotificationItem],
        calendar: Calendar = .current
    ) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { index, item in
            let fields = [
                item.type,
                item.caption,
                item.subtitle,
                item.script,
                dateTime(item.start, isAllDay: item.isAllDay, calendar: calendar),
                item.end.map { dateTime($0, isAllDay: item.isAllDay, calendar: calendar) } ?? ""
            ]
            return (index, fields.joined(separator: "\u{1}") + "\u{1}")
        })
    }

    private static func dateTime(_ date: Date, isAllDay: Bool, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let dateFields = [components.year, components.month, components.day].map { String($0 ?? 0) }
        let timeFields = isAllDay
            ? ["", "", ""]
            : [components.hour, components.minute, components.second].map { String($0 ?? 0) }
        return (dateFields + timeFields).joined(separator: ",")
    }
}

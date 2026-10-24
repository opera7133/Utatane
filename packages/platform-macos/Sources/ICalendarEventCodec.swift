import Foundation

/// Portable calendar content; presentation and subscription state stay in the app.
public struct ICalendarEvent: Codable, Sendable, Equatable {
    public var uid: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var timeZoneIdentifier: String?
    public var fields: [String: String]
    public var rule: String?
    public var excludedDays: [Date]
    public var excludedDateTimes: [Date]
    public var additionalDates: [Date]
    public var recurrenceID: Date?
    public var recurrenceIsDate: Bool
    public var recurrenceTimeZoneIdentifier: String?
    public var overrides: [ICalendarEvent]
    public init(uid: String? = nil, start: Date, end: Date, isAllDay: Bool = false, timeZoneIdentifier: String? = nil,
                fields: [String: String] = [:], rule: String? = nil, excludedDays: [Date] = [], excludedDateTimes: [Date] = [],
                additionalDates: [Date] = [], recurrenceID: Date? = nil, recurrenceIsDate: Bool = false,
                recurrenceTimeZoneIdentifier: String? = nil, overrides: [ICalendarEvent] = [])
    {
        self.uid = uid; self.start = start; self.end = end; self.isAllDay = isAllDay; self.timeZoneIdentifier = timeZoneIdentifier
        self.fields = fields; self.rule = rule; self.excludedDays = excludedDays; self.excludedDateTimes = excludedDateTimes
        self.additionalDates = additionalDates; self.recurrenceID = recurrenceID; self.recurrenceIsDate = recurrenceIsDate
        self.recurrenceTimeZoneIdentifier = recurrenceTimeZoneIdentifier; self.overrides = overrides
    }

    public func occurrences(in range: DateInterval, calendar: Calendar = .current) throws -> [Self] {
        guard fields["STATUS"]?.uppercased() != "CANCELLED" else { return [] }
        var calendar = calendar
        if let zone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) {
            calendar.timeZone = zone
        }
        let replaced = Set(overrides.compactMap(\.recurrenceID))
        let starts = try CalendarRecurrence.starts(start: start, end: end, rule: rule, excluded: excludedDays,
                                                   excludedDateTimes: excludedDateTimes, additional: additionalDates, in: range, calendar: calendar)
        var result = starts.filter { !replaced.contains($0) }.map { date -> Self in
            var value = self
            value.start = date
            if isAllDay {
                let days = calendar.dateComponents([.day], from: start, to: end).day ?? 1
                value.end = calendar.date(byAdding: .day, value: days, to: date) ?? date
            } else {
                value.end = date.addingTimeInterval(end.timeIntervalSince(start))
            }
            value.rule = nil; value.overrides = []
            return value
        }
        // A moved instance can enter the range from an original date outside it.
        for override in overrides where override.fields["STATUS"]?.uppercased() != "CANCELLED" {
            guard override.start < range.end, override.end > range.start || (override.end == override.start && override.start >= range.start) else { continue }
            var value = override
            value.fields = fields.merging(override.fields) { _, replacement in replacement }
            value.rule = nil; value.overrides = []
            result.append(value)
        }
        return result.sorted { $0.start < $1.start }
    }
}

public enum ICalendarEventCodec {
    public enum Failure: Error { case invalidDocument, unsupportedRange, tooLarge }
    private struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }

    private struct Component {
        var properties: [Property]
        var fields: [String: String] {
            properties.reduce(into: [:]) { $0[$1.name] = $1.value }
        }

        func property(_ name: String) -> Property? {
            properties.last { $0.name == name }
        }

        var sequence: Int {
            Int(fields["SEQUENCE"] ?? "0") ?? 0
        }

        var modified: Date {
            fields["LAST-MODIFIED"].flatMap { ICalendarDateParser.parse($0) } ?? .distantPast
        }
    }

    public static func decode(_ source: String) throws -> [ICalendarEvent] {
        guard source.utf8.count <= 16 * 1024 * 1024 else { throw Failure.tooLarge }
        let unfolded = source.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\r\n\t", with: "")
        let lines = unfolded.components(separatedBy: .newlines)
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else { throw Failure.invalidDocument }
        var components: [Component] = [], current: [Property]?, nesting = 0
        for line in lines {
            if line == "BEGIN:VEVENT" {
                guard current == nil else { throw Failure.invalidDocument }
                current = []; nesting = 0
            } else if line == "END:VEVENT" {
                guard let properties = current, nesting == 0 else { throw Failure.invalidDocument }
                components.append(Component(properties: properties)); current = nil
                guard components.count <= 10000 else { throw Failure.tooLarge }
            } else if current != nil {
                if line.hasPrefix("BEGIN:") {
                    nesting += 1; continue
                }
                if line.hasPrefix("END:"), nesting > 0 {
                    nesting -= 1; continue
                }
                guard nesting == 0, !line.isEmpty else { continue }
                guard let colon = line.firstIndex(of: ":") else { throw Failure.invalidDocument }
                let pieces = line[..<colon].split(separator: ";", omittingEmptySubsequences: false)
                guard let name = pieces.first, !name.isEmpty else { throw Failure.invalidDocument }
                var parameters: [String: String] = [:]
                for piece in pieces.dropFirst() {
                    let pair = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard pair.count == 2 else { throw Failure.invalidDocument }
                    parameters[String(pair[0]).uppercased()] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                let key = name.uppercased()
                if ["UID", "DTSTART", "DTEND", "RECURRENCE-ID", "RRULE"].contains(key), current!.contains(where: { $0.name == key }) {
                    throw Failure.invalidDocument
                }
                current!.append(Property(name: key, parameters: parameters, value: String(line[line.index(after: colon)...])))
                guard current!.count <= 1024 else { throw Failure.tooLarge }
            }
        }
        guard current == nil else { throw Failure.invalidDocument }
        func newer(_ a: Component, _ b: Component) -> Component {
            if a.sequence != b.sequence {
                return a.sequence > b.sequence ? a : b
            }
            return a.modified > b.modified ? a : b
        }
        var masters: [String: Component] = [:], anonymous: [Component] = [], exceptions: [Component] = []
        for component in components {
            if component.property("RECURRENCE-ID") != nil {
                exceptions.append(component)
            } else if let uid = component.fields["UID"], !uid.isEmpty {
                masters[uid] = masters[uid].map { newer($0, component) } ?? component
            } else {
                anonymous.append(component)
            }
        }
        var result = try masters.mapValues { try event($0) }
        var selected: [String: [Date: Component]] = [:]
        for component in exceptions {
            guard let uid = component.fields["UID"], !uid.isEmpty, let property = component.property("RECURRENCE-ID") else { throw Failure.invalidDocument }
            guard property.parameters["RANGE"] == nil else { throw Failure.unsupportedRange }
            let original = try date(property, defaultZone: result[uid]?.timeZoneIdentifier)
            let previous = selected[uid]?[original]
            selected[uid, default: [:]][original] = previous.map { newer($0, component) } ?? component
        }
        var orphans: [ICalendarEvent] = []
        for (uid, values) in selected {
            let parent = result[uid]
            let overrides = try values.values.map { try event($0, parent: parent) }
            if parent != nil {
                result[uid]!.overrides = overrides.sorted { $0.recurrenceID! < $1.recurrenceID! }
            } else {
                orphans += overrides.filter { $0.fields["STATUS"]?.uppercased() != "CANCELLED" }
            }
        }
        return try (Array(result.values) + (anonymous.map { try event($0) }) + orphans).sorted { $0.start < $1.start }
    }

    private static func date(_ property: Property, defaultZone: String?) throws -> Date {
        let zone = property.parameters["TZID"] ?? defaultZone
        guard zone == nil || TimeZone(identifier: zone!) != nil,
              let result = ICalendarDateParser.parse(property.value, timeZoneIdentifier: zone) else { throw Failure.invalidDocument }
        return result
    }

    private static func event(_ component: Component, parent: ICalendarEvent? = nil) throws -> ICalendarEvent {
        let fields = component.fields
        let recurrence = try component.property("RECURRENCE-ID").map { try date($0, defaultZone: parent?.timeZoneIdentifier) }
        let startProperty = component.property("DTSTART")
        let isCancelled = fields["STATUS"]?.uppercased() == "CANCELLED"
        let start: Date
        if let startProperty {
            start = try date(startProperty, defaultZone: parent?.timeZoneIdentifier)
        } else if isCancelled, let recurrence {
            start = recurrence
        } else {
            throw Failure.invalidDocument
        }
        let zone = startProperty?.parameters["TZID"] ?? parent?.timeZoneIdentifier
        var calendar = Calendar(identifier: .gregorian)
        if let zone, let timeZone = TimeZone(identifier: zone) {
            calendar.timeZone = timeZone
        }
        let allDay = startProperty.map { $0.value.count == 8 } ?? parent?.isAllDay ?? (component.property("RECURRENCE-ID")?.value.count == 8)
        let end: Date
        if let property = component.property("DTEND") {
            end = try date(property, defaultZone: zone)
        } else if let duration = fields["DURATION"] {
            guard let value = ICalendarDateParser.durationEnd(start: start, source: duration, calendar: calendar) else { throw Failure.invalidDocument }
            end = value
        } else if let parent {
            if parent.isAllDay {
                end = calendar.date(byAdding: .day, value: calendar.dateComponents([.day], from: parent.start, to: parent.end).day ?? 1, to: start)!
            } else {
                end = start.addingTimeInterval(parent.end.timeIntervalSince(parent.start))
            }
        } else {
            end = allDay ? calendar.date(byAdding: .day, value: 1, to: start)! : start.addingTimeInterval(3600)
        }
        guard end >= start else { throw Failure.invalidDocument }
        var excludedDays: [Date] = [], excludedDates: [Date] = [], additional: [Date] = []
        for property in component.properties where ["EXDATE", "RDATE"].contains(property.name) {
            for value in property.value.split(separator: ",", omittingEmptySubsequences: false) {
                var item = property; item.value = String(value)
                let parsed = try date(item, defaultZone: zone)
                if property.name == "RDATE" {
                    additional.append(parsed)
                } else if value.count == 8 {
                    excludedDays.append(parsed)
                } else {
                    excludedDates.append(parsed)
                }
            }
        }
        var content: [String: String] = [:]
        for key in ["SUMMARY", "DESCRIPTION", "LOCATION", "CATEGORIES", "URL", "STATUS", "SEQUENCE", "LAST-MODIFIED"] {
            if let value = fields[key] {
                content[key] = unescape(value)
            }
        }
        return ICalendarEvent(uid: fields["UID"].map(unescape), start: start, end: end, isAllDay: allDay, timeZoneIdentifier: zone, fields: content,
                              rule: fields["RRULE"], excludedDays: excludedDays, excludedDateTimes: excludedDates, additionalDates: additional,
                              recurrenceID: recurrence, recurrenceIsDate: component.property("RECURRENCE-ID")?.value.count == 8,
                              recurrenceTimeZoneIdentifier: component.property("RECURRENCE-ID")?.parameters["TZID"] ?? parent?.timeZoneIdentifier)
    }

    public static func encode(_ events: [ICalendarEvent]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Utatane//Calendar//JA"]
        func append(_ event: ICalendarEvent, uid: String) {
            func property(_ name: String, _ date: Date, allDay: Bool, zone: String?) -> String {
                name + (allDay ? ";VALUE=DATE" : zone.map { ";TZID=" + $0 } ?? "") + ":" + format(date, allDay: allDay, zone: zone)
            }
            lines += ["BEGIN:VEVENT", "UID:" + escape(uid), property("DTSTART", event.start, allDay: event.isAllDay, zone: event.timeZoneIdentifier), property("DTEND", event.end, allDay: event.isAllDay, zone: event.timeZoneIdentifier)]
            if let original = event.recurrenceID {
                lines.append(property("RECURRENCE-ID", original, allDay: event.recurrenceIsDate, zone: event.recurrenceTimeZoneIdentifier))
            }
            for key in event.fields.keys.sorted() {
                let raw = event.fields[key]!
                let value = ["SUMMARY", "DESCRIPTION", "LOCATION", "CATEGORIES"].contains(key) ? escape(raw) : raw.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
                lines.append(key + ":" + value)
            }
            if let rule = event.rule {
                lines.append("RRULE:" + rule)
            }
            for (name, dates, allDay) in [("EXDATE", event.excludedDays, true), ("EXDATE", event.excludedDateTimes, false), ("RDATE", event.additionalDates, event.isAllDay)] where !dates.isEmpty {
                lines.append(name + (allDay ? ";VALUE=DATE" : "") + ":" + dates.map { format($0, allDay: allDay, zone: nil) }.joined(separator: ","))
            }
            lines.append("END:VEVENT")
        }
        for event in events {
            let uid = event.uid ?? UUID().uuidString
            append(event, uid: uid)
            for override in event.overrides {
                append(override, uid: uid)
            }
        }
        return (lines + ["END:VCALENDAR"]).joined(separator: "\r\n") + "\r\n"
    }

    private static func format(_ date: Date, allDay: Bool, zone: String?) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? (allDay ? .current : TimeZone(secondsFromGMT: 0)!)
        formatter.dateFormat = allDay ? "yyyyMMdd" : zone == nil ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\n").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ";", with: "\\;")
    }

    private static func unescape(_ value: String) -> String {
        var result = "", escaped = false
        for character in value {
            if escaped {
                result.append(character == "n" || character == "N" ? "\n" : character); escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped {
            result.append("\\")
        }
        return result
    }
}

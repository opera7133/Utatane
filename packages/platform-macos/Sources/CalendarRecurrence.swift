import Foundation

public enum ICalendarDateParser {
    public static func durationEnd(start: Date, source: String, calendar: Calendar = .current) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: "^P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$"),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        var values = [Int]()
        var hasValue = false
        for index in 1 ... 5 {
            guard let range = Range(match.range(at: index), in: source) else { values.append(0); continue }
            guard let value = Int(source[range]), value <= 1_000_000 else { return nil }
            values.append(value); hasValue = true
        }
        guard hasValue, let day = calendar.date(byAdding: .day, value: values[0] * 7 + values[1], to: start) else { return nil }
        return day.addingTimeInterval(Double(values[2] * 3600 + values[3] * 60 + values[4]))
    }

    public static func parse(_ source: String, timeZoneIdentifier: String? = nil) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        formatter.timeZone = source.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = source.count == 8 ? "yyyyMMdd" : source.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return formatter.date(from: source)
    }
}

public enum CalendarRecurrence {
    public enum Failure: Error { case invalidRule, unsupportedRule, expansionLimit }

    public static func occurrenceDays(start: Date, end: Date, excluded: [Date] = [], in range: DateInterval, calendar: Calendar = .current) -> [Date] {
        let exclusions = Set(excluded.map { calendar.startOfDay(for: $0) })
        var day = max(calendar.startOfDay(for: start), calendar.startOfDay(for: range.start))
        let upper = min(end > start ? end : start.addingTimeInterval(1), range.end)
        var days: [Date] = []
        while day < upper, days.count < 1830 {
            if !exclusions.contains(day) {
                days.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    public static func starts(start: Date, end: Date, rule: String?, excluded: [Date] = [], excludedDateTimes: [Date] = [], additional: [Date] = [],
                              in range: DateInterval, calendar: Calendar = .current) throws -> [Date]
    {
        let duration = max(0, end.timeIntervalSince(start))
        func overlaps(_ date: Date) -> Bool {
            date < range.end && (duration == 0 ? date >= range.start : date.addingTimeInterval(duration) > range.start)
        }
        let exclusions = Set(excluded.map { calendar.startOfDay(for: $0) })
        let exactExclusions = Set(excludedDateTimes)
        var output = Set(additional.filter { overlaps($0) && !exactExclusions.contains($0) && !exclusions.contains(calendar.startOfDay(for: $0)) })
        guard let rule, !rule.isEmpty else {
            if overlaps(start), !exactExclusions.contains(start), !exclusions.contains(calendar.startOfDay(for: start)) {
                output.insert(start)
            }
            return output.sorted()
        }
        var fields: [String: String] = [:]
        for part in rule.uppercased().split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { throw Failure.invalidRule }
            guard fields[String(pair[0])] == nil else { throw Failure.invalidRule }
            fields[String(pair[0])] = String(pair[1])
        }
        let supported: Set = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "BYMONTH", "BYSETPOS", "WKST"]
        guard Set(fields.keys).isSubset(of: supported) else { throw Failure.unsupportedRule }
        guard let frequency = fields["FREQ"], ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(frequency),
              let interval = Int(fields["INTERVAL"] ?? "1"), interval > 0,
              let count = Int(fields["COUNT"] ?? String(Int.max)), count > 0 else { throw Failure.invalidRule }
        let until = fields["UNTIL"].flatMap { ICalendarDateParser.parse($0, timeZoneIdentifier: calendar.timeZone.identifier) }
        if fields["UNTIL"] != nil, until == nil {
            throw Failure.invalidRule
        }
        func integers(_ name: String) throws -> [Int] {
            guard let text = fields[name] else { return [] }
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            let result = parts.compactMap { Int($0) }
            guard result.count == parts.count else { throw Failure.invalidRule }
            return result
        }
        let months = try integers("BYMONTH")
        let monthDays = try integers("BYMONTHDAY")
        let positions = try integers("BYSETPOS")
        guard positions.allSatisfy({ $0 != 0 && (-366 ... 366).contains($0) }),
              positions.isEmpty || fields.keys.contains(where: { $0.hasPrefix("BY") && $0 != "BYSETPOS" }) else { throw Failure.invalidRule }
        guard months.allSatisfy({ (1 ... 12).contains($0) }), monthDays.allSatisfy({ $0 != 0 && (-31 ... 31).contains($0) }) else { throw Failure.invalidRule }
        let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        var weekCalendar = calendar
        if let weekStart = fields["WKST"] {
            guard let weekday = weekdays[weekStart] else { throw Failure.invalidRule }
            weekCalendar.firstWeekday = weekday
        } else {
            weekCalendar.firstWeekday = 2
        }
        let byDays: [(day: Int, ordinal: Int?)] = try (fields["BYDAY"]?.split(separator: ",") ?? []).map { value in
            guard let day = weekdays[String(value.suffix(2))] else { throw Failure.invalidRule }
            let prefix = value.dropLast(2)
            let ordinal = prefix.isEmpty ? nil : Int(prefix)
            guard prefix.isEmpty || (ordinal != nil && ordinal != 0 && (-53 ... 53).contains(ordinal!)) else { throw Failure.invalidRule }
            return (day, ordinal)
        }
        let origin = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second], from: start)
        let subsecond = start.timeIntervalSince1970 - floor(start.timeIntervalSince1970)
        let firstWeek = weekCalendar.dateInterval(of: .weekOfYear, for: start)!.start
        let periodComponent: Calendar.Component = switch frequency { case "DAILY": .day; case "WEEKLY": .weekOfYear; case "MONTHLY": .month; default: .year }
        let periodCalendar = frequency == "WEEKLY" ? weekCalendar : calendar
        let firstPeriod = periodCalendar.dateInterval(of: periodComponent, for: start)!
        // Position selection must see the whole interval, even when the requested
        // range or UNTIL ends in its middle. COUNT/EXDATE apply after selection.
        let lastPeriod = periodCalendar.dateInterval(of: periodComponent, for: range.end.addingTimeInterval(-0.001))!
        let upper = positions.isEmpty ? range.end : lastPeriod.end
        var cursor = positions.isEmpty ? calendar.startOfDay(for: start) : firstPeriod.start
        var matches = 0, iterations = 0
        var bucket: [Date] = [], bucketStart: Date?
        func accept(_ date: Date) {
            guard date >= start, until.map({ date <= $0 }) ?? true, matches < count else { return }
            matches += 1
            if overlaps(date), !exactExclusions.contains(date), !exclusions.contains(calendar.startOfDay(for: date)) {
                output.insert(date)
            }
        }
        func flush() {
            let selected = Set(positions.compactMap { position -> Date? in
                let index = position > 0 ? position - 1 : bucket.count + position
                return bucket.indices.contains(index) ? bucket[index] : nil
            })
            for date in selected.sorted() {
                accept(date)
            }
            bucket.removeAll(keepingCapacity: true)
        }
        while cursor < upper, matches < count {
            iterations += 1
            guard iterations <= 100_000, output.count <= 10000 else { throw Failure.expansionLimit }
            let dayCursor = cursor
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            let period = periodCalendar.dateInterval(of: periodComponent, for: dayCursor)!
            if !positions.isEmpty, period.start != bucketStart {
                flush(); bucketStart = period.start
                if matches >= count {
                    break
                }
            }
            if let until, period.start > until {
                break
            }
            guard let wholeDate = calendar.date(bySettingHour: origin.hour!, minute: origin.minute!, second: origin.second!, of: dayCursor,
                                                matchingPolicy: .strict, repeatedTimePolicy: .first),
                calendar.isDate(wholeDate, inSameDayAs: dayCursor) else { continue }
            let date = wholeDate.addingTimeInterval(subsecond)
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let day = components.day!
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)!.count
            let elapsed: Int = switch frequency {
            case "DAILY": calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: dayCursor).day ?? 0
            case "WEEKLY": (calendar.dateComponents([.day], from: firstWeek, to: weekCalendar.dateInterval(of: .weekOfYear, for: date)!.start).day ?? 0) / 7
            case "MONTHLY": (components.year! - origin.year!) * 12 + components.month! - origin.month!
            default: components.year! - origin.year!
            }
            let defaultMonth = frequency != "YEARLY" || !months.isEmpty || !byDays.isEmpty || !monthDays.isEmpty || components.month == origin.month
            let defaultDay = (frequency != "MONTHLY" && frequency != "YEARLY") || !monthDays.isEmpty || !byDays.isEmpty || components.day == origin.day
            let defaultWeekday = frequency != "WEEKLY" || !byDays.isEmpty || components.weekday == origin.weekday
            let matchesDay = byDays.isEmpty || byDays.contains { requirement in
                guard requirement.day == components.weekday else { return false }
                guard let ordinal = requirement.ordinal else { return true }
                if frequency == "YEARLY", months.isEmpty {
                    let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date)!
                    let daysInYear = calendar.range(of: .day, in: .year, for: date)!.count
                    return ordinal > 0 ? (dayOfYear - 1) / 7 + 1 == ordinal : -((daysInYear - dayOfYear) / 7 + 1) == ordinal
                }
                return ordinal > 0 ? (day - 1) / 7 + 1 == ordinal : -((daysInMonth - day) / 7 + 1) == ordinal
            }
            let matchesMonthDay = monthDays.isEmpty || monthDays.contains { $0 > 0 ? $0 == day : daysInMonth + $0 + 1 == day }
            if elapsed >= 0, elapsed % interval == 0, defaultMonth, defaultDay, defaultWeekday, matchesDay, matchesMonthDay,
               months.isEmpty || months.contains(components.month!)
            {
                if positions.isEmpty {
                    accept(date)
                } else {
                    bucket.append(date)
                }
            }
        }
        if !positions.isEmpty {
            flush()
        }
        guard output.count <= 10000 else { throw Failure.expansionLimit }
        return output.sorted()
    }
}

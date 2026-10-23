import Foundation

/// Gregorian date arithmetic. Named zones use the macOS IANA database.
enum InternalSaoriTime {
    struct Failure: Error { let message: String }
    static let minimum: Int64 = -62_135_596_800
    static let maximum: Int64 = 253_402_300_799

    static func execute(_ function: String, arguments: [String], now: Date) throws -> String {
        let count = function == "Format" ? 2 : 3
        var arguments = arguments
        if function == "Format", arguments.count == 1 {
            arguments.append("")
        }
        guard arguments.count >= count else { throw Failure(message: "invalid parameter") }
        var zoneName = "local"
        for option in arguments.dropFirst(count) {
            guard option.lowercased().hasPrefix("--tz=") else { throw Failure(message: "invalid parameter") }
            zoneName = String(option.dropFirst(5))
        }
        let zone = try zone(zoneName)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = zone
        let first = try parse(arguments[0], zone: zone, now: now, local: zoneName.lowercased() == "local")
        if function == "Format" {
            return try format(first, pattern: arguments[1], calendar: calendar)
        }
        let unit = arguments[2].lowercased()
        let normalized = unit.hasSuffix("s") ? String(unit.dropLast()) : unit
        let components: [String: Calendar.Component] = ["day": .day, "week": .weekOfYear, "month": .month, "year": .year]
        let seconds: [String: Int64] = ["second": 1, "minute": 60, "hour": 3600]
        guard components[normalized] != nil || seconds[normalized] != nil else { throw Failure(message: "invalid parameter") }
        if function == "Add" {
            guard let amount = Int64(arguments[1]) else { throw Failure(message: "invalid parameter") }
            let result: Date
            if let scale = seconds[normalized] {
                let (delta, overflow) = amount.multipliedReportingOverflow(by: scale)
                guard !overflow else { throw Failure(message: "out of range") }
                result = first.addingTimeInterval(Double(delta))
            } else {
                // Bounds also prevent Calendar from spending time on absurd component values.
                guard abs(Double(amount)) <= 3_652_059,
                      let date = adding(components[normalized]!, value: Int(amount), to: first, calendar: calendar)
                else { throw Failure(message: "out of range") }
                result = date
            }
            return try String(epoch(result, local: zoneName.lowercased() == "local"))
        }
        let second = try parse(arguments[1], zone: zone, now: now, local: zoneName.lowercased() == "local")
        if let scale = seconds[normalized] {
            return String(Int64(second.timeIntervalSince(first)) / scale)
        }
        let component = components[normalized]!
        let firstParts = civil(first, zone: zone), secondParts = civil(second, zone: zone)
        var difference: Int
        switch normalized {
        case "year": difference = secondParts.year! - firstParts.year!
        case "month": difference = (secondParts.year! - firstParts.year!) * 12 + secondParts.month! - firstParts.month!
        default:
            let days = civilDays(secondParts) - civilDays(firstParts)
            difference = normalized == "week" ? days / 7 : days
        }
        // Calendar's raw month count can disagree with Add's end-of-month clamping.
        if components[normalized] != nil {
            let direction = first <= second ? 1 : -1
            func fits(_ amount: Int) -> Bool {
                guard let candidate = adding(component, value: amount, to: first, calendar: calendar) else { return false }
                return direction > 0 ? candidate <= second : candidate >= second
            }
            while !fits(difference) {
                difference -= direction
            }
            while fits(difference + direction) {
                difference += direction
            }
        }
        return String(difference)
    }

    static func zone(_ value: String) throws -> TimeZone {
        if value.lowercased() == "local" {
            return .current
        }
        if ["utc", "z"].contains(value.lowercased()) {
            return TimeZone(secondsFromGMT: 0)!
        }
        if let match = captures(#"^([+-])(\d{2})(?::?(\d{2}))?$"#, value),
           let hours = Int(match[1]), let minutes = Int(match[2].isEmpty ? "0" : match[2]),
           hours <= 18, minutes < 60, hours < 18 || minutes == 0,
           let zone = TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (match[0] == "-" ? -1 : 1))
        {
            return zone
        }
        guard let name = TimeZone.knownTimeZoneIdentifiers.first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }),
              let zone = TimeZone(identifier: name) else { throw Failure(message: "invalid parameter") }
        return zone
    }

    static func epoch(_ date: Date, local: Bool = false) throws -> Int64 {
        let seconds = floor(date.timeIntervalSince1970)
        guard seconds.isFinite, seconds >= Double(local ? -11_644_473_600 : minimum), seconds <= Double(maximum) else { throw Failure(message: "out of range") }
        return Int64(seconds)
    }

    static func parse(_ text: String, zone: TimeZone, now: Date, local: Bool) throws -> Date {
        if text.lowercased() == "now" {
            return try Date(timeIntervalSince1970: Double(epoch(now, local: local)))
        }
        if captures(#"^[+-]?\d+$"#, text) != nil {
            guard let number = Int64(text), number >= (local ? -11_644_473_600 : minimum), number <= maximum else { throw Failure(message: "out of range") }
            return Date(timeIntervalSince1970: Double(number))
        }
        let iso = #"^(\d{4})-?(\d{2})-?(\d{2})(?:[Tt ](\d{2}):?(\d{2})(?::?(\d{2})(?:\.\d+)?)?([Zz]|[+-]\d{2}(?::?\d{2})?)?)?$"#
        if let fields = captures(iso, text) {
            let year = Int(fields[0])!, month = Int(fields[1])!, day = Int(fields[2])!
            let hour = Int(fields[3]) ?? 0, minute = Int(fields[4]) ?? 0, second = Int(fields[5]) ?? 0
            guard year >= 1601, month >= 1, month <= 12, day >= 1, day <= 31, hour < 24, minute < 60, second < 60 else { throw Failure(message: "invalid parameter") }
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = fields[6].isEmpty ? zone : try self.zone(fields[6])
            let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            guard let date = calendar.date(from: parts),
                  calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == parts
            else { throw Failure(message: "invalid parameter") }
            _ = try epoch(date, local: local)
            return date
        }
        // RFC 7231 IMF-fixdate only; reject lenient DateFormatter rollover and bad weekdays.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.isLenient = false
        if let date = formatter.date(from: text), formatter.string(from: date) == text,
           formatter.calendar.component(.year, from: date) >= 1601
        {
            _ = try epoch(date, local: local)
            return date
        }
        throw Failure(message: "invalid parameter")
    }

    static func format(_ date: Date, pattern: String, calendar: Calendar) throws -> String {
        let seconds = try epoch(date)
        switch pattern.lowercased() {
        case "epoch": return String(seconds)
        case "epochms": return String(seconds * 1000)
        case "", "iso8601", "rfc3339": return try format(date, pattern: "%Y-%m-%dT%H:%M:%S", calendar: calendar) + offset(calendar.timeZone.secondsFromGMT(for: date), colon: true, zulu: true)
        case "http":
            var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
            return try format(date, pattern: "%a, %d %b %Y %H:%M:%S GMT", calendar: utc)
        default: break
        }
        guard pattern.contains("%") else { throw Failure(message: "invalid parameter") }
        let parts = civil(date, zone: calendar.timeZone)
        let weekday = parts.weekday! - 1
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let values: [Character: String] = [
            "Y": String(format: "%04d", parts.year!), "y": String(format: "%02d", parts.year! % 100),
            "m": String(format: "%02d", parts.month!), "d": String(format: "%02d", parts.day!),
            "H": String(format: "%02d", parts.hour!), "M": String(format: "%02d", parts.minute!), "S": String(format: "%02d", parts.second!),
            "j": String(format: "%03d", daysBeforeMonth(parts.month!, year: parts.year!) + parts.day!),
            "w": String(weekday), "u": String(weekday == 0 ? 7 : weekday),
            "a": String(days[weekday].prefix(3)), "A": days[weekday],
            "b": String(months[parts.month! - 1].prefix(3)), "B": months[parts.month! - 1],
            "s": String(seconds), "%": "%", "z": offset(calendar.timeZone.secondsFromGMT(for: date), colon: false)
        ]
        let characters = Array(pattern)
        var index = 0, output = ""
        while index < characters.count {
            if characters[index] != "%" {
                output.append(characters[index]); index += 1; continue
            }
            index += 1
            guard index < characters.count else { throw Failure(message: "invalid parameter") }
            if characters[index] == ":", index + 1 < characters.count, characters[index + 1] == "z" {
                output += offset(calendar.timeZone.secondsFromGMT(for: date), colon: true); index += 2
            } else {
                guard let value = values[characters[index]] else { throw Failure(message: "invalid parameter") }
                output += value; index += 1
            }
        }
        return output
    }

    /// Foundation's Gregorian/ISO calendars use a historical Julian cutover.
    /// Epoch arithmetic and formatting require the proleptic Gregorian calendar.
    private static func floorDivide(_ number: Int, _ divisor: Int) -> Int {
        let quotient = number / divisor
        return number < 0 && number % divisor != 0 ? quotient - 1 : quotient
    }

    private static func leap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    private static func daysBeforeYear(_ year: Int) -> Int {
        let previous = year - 1
        return previous * 365 + floorDivide(previous, 4) - floorDivide(previous, 100) + floorDivide(previous, 400)
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        month == 2 ? (leap(year) ? 29 : 28) : ([4, 6, 9, 11].contains(month) ? 30 : 31)
    }

    private static func daysBeforeMonth(_ month: Int, year: Int) -> Int {
        (1 ..< month).reduce(0) { $0 + daysInMonth($1, year: year) }
    }

    private static func civilDays(_ parts: DateComponents) -> Int {
        daysBeforeYear(parts.year!) + daysBeforeMonth(parts.month!, year: parts.year!) + parts.day! - 1 - 719_162
    }

    private static func civil(_ date: Date, zone: TimeZone) -> DateComponents {
        let local = Int(floor(date.timeIntervalSince1970)) + zone.secondsFromGMT(for: date)
        let days = floorDivide(local, 86400), second = local - days * 86400
        let absolute = days + 719_162
        var year = floorDivide(absolute, 366) + 1
        while daysBeforeYear(year + 1) <= absolute {
            year += 1
        }
        while daysBeforeYear(year) > absolute {
            year -= 1
        }
        var remaining = absolute - daysBeforeYear(year), month = 1
        while remaining >= daysInMonth(month, year: year) {
            remaining -= daysInMonth(month, year: year); month += 1
        }
        return DateComponents(year: year, month: month, day: remaining + 1, hour: second / 3600, minute: second % 3600 / 60, second: second % 60, weekday: ((days + 4) % 7 + 7) % 7 + 1)
    }

    private static func adding(_ component: Calendar.Component, value: Int, to date: Date, calendar: Calendar) -> Date? {
        var parts = civil(date, zone: calendar.timeZone)
        if parts.year! >= 1601 {
            // Foundation handles modern gaps/repeated times and end-of-month clamping.
            let result = calendar.date(byAdding: component, value: value, to: date)
            if let result, civil(result, zone: calendar.timeZone).year! >= 1601 {
                return result
            }
        }
        switch component {
        case .month, .year:
            let index = (parts.year! - 1) * 12 + parts.month! - 1 + (component == .year ? value * 12 : value)
            parts.year = floorDivide(index, 12) + 1
            parts.month = index - (parts.year! - 1) * 12 + 1
            guard (1 ... 9999).contains(parts.year!) else { return nil }
            parts.day = min(parts.day!, daysInMonth(parts.month!, year: parts.year!))
        default: break
        }
        let dayDelta = component == .day ? value : component == .weekOfYear ? value * 7 : 0
        let local = Double((civilDays(parts) + dayDelta) * 86400 + parts.hour! * 3600 + parts.minute! * 60 + parts.second!)
        var result = Date(timeIntervalSince1970: local - Double(calendar.timeZone.secondsFromGMT(for: date)))
        // Resolve the target zone offset, which can differ across a transition.
        for _ in 0 ..< 2 {
            result = Date(timeIntervalSince1970: local - Double(calendar.timeZone.secondsFromGMT(for: result)))
        }
        return result
    }

    private static func offset(_ seconds: Int, colon: Bool, zulu: Bool = false) -> String {
        if seconds == 0, zulu {
            return "Z"
        }
        return String(format: colon ? "%@%02d:%02d" : "%@%02d%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
    }

    private static func captures(_ pattern: String, _ value: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1 ..< match.numberOfRanges).map { index in
            Range(match.range(at: index), in: value).map { String(value[$0]) } ?? ""
        }
    }
}

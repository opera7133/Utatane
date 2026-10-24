import Foundation
import Testing
@testable import UtatanePlatformMacOS

private func recurrenceDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private var recurrenceCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar
}

@Test func `calendar recurrence counts excluded occurrences and includes additional dates`() throws {
    let start = recurrenceDate("2026-10-01T09:00:00Z")
    let excluded = recurrenceDate("2026-10-02T00:00:00Z")
    let extra = recurrenceDate("2026-10-05T09:00:00Z")
    let result = try CalendarRecurrence.starts(start: start, end: start.addingTimeInterval(3600), rule: "FREQ=DAILY;COUNT=3", excluded: [excluded], additional: [extra], in: DateInterval(start: start, duration: 7 * 86400), calendar: recurrenceCalendar)
    #expect(result == [start, start.addingTimeInterval(2 * 86400), extra])
}

@Test func `calendar recurrence handles intervals weekdays month ends and inclusive until`() throws {
    let start = recurrenceDate("2026-10-01T09:00:00Z")
    let range = DateInterval(start: start, duration: 70 * 86400)
    let monthly = try CalendarRecurrence.starts(start: start, end: start, rule: "FREQ=MONTHLY;BYDAY=-1TU", in: range, calendar: recurrenceCalendar)
    #expect(monthly == [recurrenceDate("2026-10-27T09:00:00Z"), recurrenceDate("2026-11-24T09:00:00Z")])
    let weekly = try CalendarRecurrence.starts(start: start, end: start, rule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;UNTIL=20261015T090000Z", in: range, calendar: recurrenceCalendar)
    #expect(weekly == [start, recurrenceDate("2026-10-12T09:00:00Z"), recurrenceDate("2026-10-15T09:00:00Z")])
    let lastDay = try CalendarRecurrence.starts(start: start, end: start, rule: "FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=2", in: range, calendar: recurrenceCalendar)
    #expect(lastDay == [recurrenceDate("2026-10-31T09:00:00Z"), recurrenceDate("2026-11-30T09:00:00Z")])
}

@Test func `calendar dates respect TZID and event end is exclusive`() throws {
    #expect(ICalendarDateParser.parse("20260401T090000", timeZoneIdentifier: "Asia/Tokyo") == recurrenceDate("2026-04-01T00:00:00Z"))
    let start = recurrenceDate("2026-10-01T00:00:00Z")
    let range = DateInterval(start: start.addingTimeInterval(86400), duration: 86400)
    #expect(try CalendarRecurrence.starts(start: start, end: range.start, rule: nil, in: range, calendar: recurrenceCalendar).isEmpty)
    #expect(throws: CalendarRecurrence.Failure.self) { try CalendarRecurrence.starts(start: start, end: start, rule: "FREQ=DAILY;INTERVAL=0", in: range) }
}

@Test func `calendar duration and multi day expansion preserve exclusive end`() throws {
    let start = recurrenceDate("2026-10-01T00:00:00Z")
    let end = try #require(ICalendarDateParser.durationEnd(start: start, source: "P3DT2H", calendar: recurrenceCalendar))
    #expect(end == recurrenceDate("2026-10-04T02:00:00Z"))
    let excluded = recurrenceDate("2026-10-02T00:00:00Z")
    let days = CalendarRecurrence.occurrenceDays(start: start, end: start.addingTimeInterval(3 * 86400), excluded: [excluded], in: DateInterval(start: start, duration: 7 * 86400), calendar: recurrenceCalendar)
    #expect(days == [start, start.addingTimeInterval(2 * 86400)])
    #expect(ICalendarDateParser.durationEnd(start: start, source: "garbage") == nil)
}

@Test func `BYSETPOS selects within complete periods before COUNT UNTIL and exclusions`() throws {
    let start = recurrenceDate("2026-10-01T09:00:00Z")
    let end = recurrenceDate("2027-01-01T00:00:00Z")
    let rule = "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=2"
    let dates = try CalendarRecurrence.starts(start: start, end: start, rule: rule, in: DateInterval(start: start, end: end), calendar: recurrenceCalendar)
    #expect(dates == [recurrenceDate("2026-10-30T09:00:00Z"), recurrenceDate("2026-11-30T09:00:00Z")])
    let partial = try CalendarRecurrence.starts(start: start, end: start, rule: rule, in: DateInterval(start: start, end: recurrenceDate("2026-10-15T00:00:00Z")), calendar: recurrenceCalendar)
    #expect(partial.isEmpty)
    let limited = try CalendarRecurrence.starts(start: start, end: start, rule: "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;UNTIL=20261015T090000Z", in: DateInterval(start: start, end: end), calendar: recurrenceCalendar)
    #expect(limited.isEmpty)
    let excluded = try CalendarRecurrence.starts(start: start, end: start, rule: rule, excludedDateTimes: [dates[0]], in: DateInterval(start: start, end: end), calendar: recurrenceCalendar)
    #expect(excluded == [dates[1]])
    for invalid in ["FREQ=MONTHLY;BYSETPOS=0;BYDAY=MO", "FREQ=MONTHLY;BYSETPOS=1", "FREQ=MONTHLY;BYDAY=-9223372036854775808MO"] {
        #expect(throws: CalendarRecurrence.Failure.self) { try CalendarRecurrence.starts(start: start, end: start, rule: invalid, in: DateInterval(start: start, end: end), calendar: recurrenceCalendar) }
    }
}

@Test func `recurrence preserves fractional starts and skips nonexistent local times`() throws {
    let fractional = recurrenceDate("2026-10-01T09:00:00Z").addingTimeInterval(0.25)
    #expect(try CalendarRecurrence.starts(start: fractional, end: fractional, rule: "FREQ=DAILY;COUNT=2", in: DateInterval(start: fractional, duration: 3 * 86400), calendar: recurrenceCalendar) == [fractional, fractional.addingTimeInterval(86400)])
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let start = try #require(ICalendarDateParser.parse("20260307T023000", timeZoneIdentifier: calendar.timeZone.identifier))
    let result = try CalendarRecurrence.starts(start: start, end: start, rule: "FREQ=DAILY;COUNT=2", in: DateInterval(start: start, duration: 4 * 86400), calendar: calendar)
    #expect(result.map { calendar.component(.day, from: $0) } == [7, 9])
    #expect(result.map { calendar.component(.hour, from: $0) } == [2, 2])
}

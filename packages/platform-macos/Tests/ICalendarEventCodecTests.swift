import Foundation
import Testing
@testable import UtatanePlatformMacOS

private let exceptionCalendar = """
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:series@example.test
RECURRENCE-ID;TZID=Asia/Tokyo:20261008T090000
DTSTART;TZID=Asia/Tokyo:20261009T120000
SEQUENCE:1
SUMMARY:old revision
END:VEVENT
BEGIN:VEVENT
UID:series@example.test
DTSTART;TZID=Asia/Tokyo:20261001T090000
DTEND;TZID=Asia/Tokyo:20261001T100000
RRULE:FREQ=WEEKLY;COUNT=4
SUMMARY:Weekly meeting
DESCRIPTION:shared notes
BEGIN:VALARM
SUMMARY:alarm title must not replace event
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:series@example.test
RECURRENCE-ID;TZID=Asia/Tokyo:20261008T090000
DTSTART;TZID=Asia/Tokyo:20261105T120000
SEQUENCE:2
SUMMARY:Moved meeting
END:VEVENT
BEGIN:VEVENT
UID:series@example.test
RECURRENCE-ID;TZID=Asia/Tokyo:20261015T090000
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR
"""
private func tokyo(_ value: String) -> Date {
    ICalendarDateParser.parse(value, timeZoneIdentifier: "Asia/Tokyo")!
}

@Test func `calendar exceptions replace original instances including moves across query ranges`() throws {
    let events = try ICalendarEventCodec.decode(exceptionCalendar)
    #expect(events.count == 1)
    #expect(events[0].overrides.count == 2)
    #expect(events[0].fields["SUMMARY"] == "Weekly meeting")
    let october = try events[0].occurrences(in: DateInterval(start: tokyo("20261001T000000"), end: tokyo("20261101T000000")))
    #expect(october.map(\.start) == [tokyo("20261001T090000"), tokyo("20261022T090000")])
    let november = try events[0].occurrences(in: DateInterval(start: tokyo("20261101T000000"), end: tokyo("20261110T000000")))
    #expect(november.count == 1)
    #expect(november.first?.start == tokyo("20261105T120000"))
    #expect(november.first?.end == tokyo("20261105T130000"))
    #expect(november.first?.fields["SUMMARY"] == "Moved meeting")
    #expect(november.first?.fields["DESCRIPTION"] == "shared notes")
    let roundTrip = try ICalendarEventCodec.decode(ICalendarEventCodec.encode(events))
    #expect(try roundTrip[0].occurrences(in: DateInterval(start: tokyo("20261001T000000"), end: tokyo("20261201T000000"))).map(\.start) == [tokyo("20261001T090000"), tokyo("20261022T090000"), tokyo("20261105T120000")])
}

@Test func `date time exclusions do not remove another RDATE on the same day`() throws {
    let source = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:times
    DTSTART:20261001T090000Z
    DTEND:20261001T100000Z
    RRULE:FREQ=DAILY;COUNT=1
    RDATE:20261001T120000Z
    EXDATE:20261001T090000Z
    END:VEVENT
    END:VCALENDAR
    """
    let event = try #require(ICalendarEventCodec.decode(source).first)
    let range = try DateInterval(start: #require(ICalendarDateParser.parse("20261001T000000Z")), duration: 86400)
    #expect(try event.occurrences(in: range).map(\.start) == [#require(ICalendarDateParser.parse("20261001T120000Z"))])
    let futureRange = source.replacingOccurrences(of: "UID:times", with: "UID:times\nRECURRENCE-ID;RANGE=THISANDFUTURE:20261001T090000Z")
    #expect(throws: ICalendarEventCodec.Failure.self) { try ICalendarEventCodec.decode(futureRange) }
}

@Test func `all day exceptions and text escaping survive calendar export`() throws {
    let source = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:days
    DTSTART;VALUE=DATE:20261001
    DTEND;VALUE=DATE:20261002
    RRULE:FREQ=DAILY;COUNT=2
    SUMMARY:one\\,two\\;three\\nnext
    END:VEVENT
    BEGIN:VEVENT
    UID:days
    RECURRENCE-ID;VALUE=DATE:20261002
    DTSTART;VALUE=DATE:20261004
    SUMMARY:
    END:VEVENT
    END:VCALENDAR
    """
    let event = try #require(ICalendarEventCodec.decode(source).first)
    #expect(event.fields["SUMMARY"] == "one,two;three\nnext")
    let encoded = ICalendarEventCodec.encode([event])
    #expect(encoded.contains("RECURRENCE-ID;VALUE=DATE:20261002"))
    let decoded = try #require(ICalendarEventCodec.decode(encoded).first)
    let lower = try #require(ICalendarDateParser.parse("20261001"))
    let result = try decoded.occurrences(in: DateInterval(start: lower, duration: 6 * 86400))
    #expect(try result.map(\.start) == [lower, #require(ICalendarDateParser.parse("20261004"))])
    #expect(result.last?.fields["SUMMARY"] == "")
    #expect(result.filter { !$0.isAllDay }.isEmpty)
}

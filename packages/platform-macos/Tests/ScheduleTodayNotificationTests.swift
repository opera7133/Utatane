import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test
func `today schedule notification uses SSP separators and date formats`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 60 * 60))
    let timedStart = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 9,
        day: 13,
        hour: 10,
        minute: 30,
        second: 45
    )))
    let allDayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))
    let references = ScheduleTodayNotificationFormatter.references(for: [
        .init(
            type: "event",
            caption: "講義",
            subtitle: "教室A",
            script: "\\0行くよ。\\e",
            start: timedStart,
            end: timedStart.addingTimeInterval(3600),
            isAllDay: false
        ),
        .init(
            type: "holiday",
            caption: "休み",
            subtitle: "",
            script: "",
            start: allDayStart,
            end: nil,
            isAllDay: true
        )
    ], calendar: calendar)

    #expect(references[0] == "event\u{1}講義\u{1}教室A\u{1}\\0行くよ。\\e\u{1}2026,9,13,10,30,45\u{1}2026,9,13,11,30,45\u{1}")
    #expect(references[1] == "holiday\u{1}休み\u{1}\u{1}\u{1}2026,9,13,,,\u{1}\u{1}")
    #expect(ScheduleTodayNotificationFormatter.references(for: [], calendar: calendar).isEmpty)
}

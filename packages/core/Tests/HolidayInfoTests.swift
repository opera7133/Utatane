import Foundation
import Testing
@testable import UtataneCore

private func holidayDate(_ text: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
}

@Test func `holiday bundle notifies actual dates including substitutes and moved holidays`() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    for (date, name) in [("1955-01-01", "元日"), ("2026-01-01", "元日"), ("2026-05-06", "休日"), ("2026-09-22", "休日"), ("2021-07-22", "海の日"), ("2027-11-23", "勤労感謝の日")] {
        let info = try #require(HolidayInfo.today(at: holidayDate(date + "T03:00:00Z"), countryCode: "JP", timeZone: zone))
        #expect(info.name == name)
        #expect(info.references[1] == date.replacingOccurrences(of: "-", with: ","))
        #expect(info.references[2] == "JP")
    }
    #expect(try HolidayInfo.today(at: holidayDate("2026-10-24T03:00:00Z"), countryCode: "JP", timeZone: zone) == nil)
    #expect(try HolidayInfo.today(at: holidayDate("2028-01-01T03:00:00Z"), countryCode: "JP", timeZone: zone) == nil)
    #expect(try HolidayInfo.today(at: holidayDate("2026-01-01T03:00:00Z"), countryCode: "US", timeZone: zone) == nil)
}

@Test func `holiday overrides are authoritative and use the caller clock and timezone`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = try holidayDate("2025-12-31T16:00:00Z")
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    try "2026/1/1,Custom\n".write(to: root.appending(path: "holidays-JP.txt"), atomically: true, encoding: .utf8)
    #expect(HolidayInfo.today(at: now, countryCode: "jp", timeZone: tokyo, userDirectory: root)?.name == "Custom")
    #expect(try HolidayInfo.today(at: now, countryCode: "JP", timeZone: #require(.init(secondsFromGMT: 0)), userDirectory: root) == nil)
    try "2026/1/1,Fallback\n".write(to: root.appending(path: "holidays.txt"), atomically: true, encoding: .utf8)
    try "".write(to: root.appending(path: "holidays-JP.txt"), atomically: true, encoding: .utf8)
    #expect(HolidayInfo.today(at: now, countryCode: "JP", timeZone: tokyo, userDirectory: root) == nil)
    #expect(HolidayInfo.today(at: now, countryCode: "GB", timeZone: tokyo, userDirectory: root)?.countryCode == "")
    #expect(HolidayInfo.parse("#comment\n2026-02-30,invalid\n2026/1/1,\nnot a date,x\n2026/1/1,Valid\n") == ["2026-01-01": "Valid"])
}

import Foundation
import Testing
@testable import UtataneCore

@Test @MainActor func `usage history persists daily time and never accrues offline time`() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "usage.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    var date = try #require(ISO8601DateFormatter().date(from: "2026-10-01T23:30:00Z"))
    let identity = GhostUsageIdentity(id: "one", name: "One")
    let store = GhostUsageStore(fileURL: file, calendar: calendar, now: { date })
    store.begin(identity)
    store.begin(identity)
    date += 3600
    store.end(identity.id)
    var rows = store.rows(installed: [identity])
    #expect(rows[0].boots == 1)
    #expect(rows[0].seconds == 3600)
    #expect(rows[0].status == "install")
    date += 40 * 86400
    let restored = GhostUsageStore(fileURL: file, calendar: calendar, now: { date })
    rows = restored.rows(installed: [identity])
    #expect(rows[0].seconds == 3600)
    #expect(rows[0].weeklySeconds == 0)
    #expect(rows[0].monthlySeconds == 0)
    restored.begin(identity, countsBoot: false)
    date += 120
    rows = restored.rows(installed: [identity])
    #expect(rows[0].boots == 1)
    #expect(rows[0].seconds == 3720)
    #expect(rows[0].weeklySeconds == 120)
    #expect(rows[0].percent == 100)
    #expect(rows[0].status == "boot")
    #expect(rows[0].shioriValue.split(separator: "\u{1}", omittingEmptySubsequences: false).count == 13)
    restored.end(identity.id)
    #expect(restored.rows(installed: [])[0].status == "vanish")
}

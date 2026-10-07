import Foundation

public struct GhostUsageIdentity: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sakuraName: String
    public let keroName: String
    public init(id: String, name: String, sakuraName: String = "", keroName: String = "") {
        self.id = id; self.name = name; self.sakuraName = sakuraName; self.keroName = keroName
    }
}

public struct GhostUsageRow: Sendable {
    public let identity: GhostUsageIdentity
    public let boots: Int
    public let seconds: Double
    public let percent: Double
    public let weeklyBoots: Int
    public let weeklySeconds: Double
    public let weeklyPercent: Double
    public let monthlyBoots: Int
    public let monthlySeconds: Double
    public let monthlyPercent: Double
    public let status: String

    public var shioriValue: String {
        [identity.name, identity.sakuraName, identity.keroName, String(boots), String(Int(seconds / 60)), String(percent), status,
         String(weeklyBoots), String(Int(weeklySeconds / 60)), String(weeklyPercent),
         String(monthlyBoots), String(Int(monthlySeconds / 60)), String(monthlyPercent)].joined(separator: "\u{1}")
    }
}

@MainActor public final class GhostUsageStore {
    private struct Day: Codable { var boots = 0; var seconds: Double = 0 }
    private struct Record: Codable { var identity: GhostUsageIdentity; var days: [String: Day] = [:] }
    private let fileURL: URL
    private let now: () -> Date
    private var records: [String: Record] = [:]
    private var active: [String: Date] = [:]
    private let calendar: Calendar

    public init(fileURL: URL, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL; self.calendar = calendar; self.now = now
        if let data = try? Data(contentsOf: fileURL), let records = try? JSONDecoder().decode([String: Record].self, from: data) {
            self.records = records
        }
    }

    public func begin(_ identity: GhostUsageIdentity, countsBoot: Bool = true) {
        guard active[identity.id] == nil else { return }
        let date = now()
        var record = records[identity.id] ?? Record(identity: identity)
        record.identity = identity
        if countsBoot {
            record.days[key(date), default: Day()].boots += 1
        }
        records[identity.id] = record
        active[identity.id] = date
        save()
    }

    public func end(_ id: String) {
        checkpoint(); active[id] = nil
    }

    public func checkpoint() {
        let date = now()
        for (id, previous) in active {
            guard var record = records[id] else { continue }
            var start = previous
            while start < date {
                let next = min(date, calendar.dateInterval(of: .day, for: start)!.end)
                record.days[key(start), default: Day()].seconds += next.timeIntervalSince(start)
                start = next
            }
            records[id] = record
            active[id] = date
        }
        save()
    }

    public func rows(installed: [GhostUsageIdentity]) -> [GhostUsageRow] {
        checkpoint()
        var all = records
        for identity in installed {
            if all[identity.id] == nil {
                all[identity.id] = Record(identity: identity)
            }
        }
        let installedIDs = Set(installed.map(\.id))
        let date = calendar.startOfDay(for: now())
        let week = key(calendar.date(byAdding: .day, value: -7, to: date)!)
        let month = key(calendar.date(byAdding: .day, value: -30, to: date)!)
        func totals(_ record: Record, since: String = "") -> (Int, Double) {
            record.days.filter { $0.key >= since }.values.reduce((0, 0)) { ($0.0 + $1.boots, $0.1 + $1.seconds) }
        }
        let seconds = all.values.reduce(0) { $0 + totals($1).1 }
        let weekly = all.values.reduce(0) { $0 + totals($1, since: week).1 }
        let monthly = all.values.reduce(0) { $0 + totals($1, since: month).1 }
        func ratio(_ value: Double, _ total: Double) -> Double {
            total > 0 ? value / total * 100 : 0
        }
        return all.values.map { record in
            let total = totals(record); let weekTotal = totals(record, since: week); let monthTotal = totals(record, since: month)
            return GhostUsageRow(identity: record.identity, boots: total.0, seconds: total.1, percent: ratio(total.1, seconds),
                                 weeklyBoots: weekTotal.0, weeklySeconds: weekTotal.1, weeklyPercent: ratio(weekTotal.1, weekly),
                                 monthlyBoots: monthTotal.0, monthlySeconds: monthTotal.1, monthlyPercent: ratio(monthTotal.1, monthly),
                                 status: active[record.identity.id] != nil ? "boot" : installedIDs.contains(record.identity.id) ? "install" : "vanish")
        }.sorted { $0.seconds == $1.seconds ? $0.identity.id < $1.identity.id : $0.seconds > $1.seconds }
    }

    private func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
        } catch { AppLogStore.shared.warning("利用履歴の保存に失敗: " + error.localizedDescription, category: "Usage") }
    }
}

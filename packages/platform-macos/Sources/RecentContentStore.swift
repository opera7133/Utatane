import Foundation

public enum RecentContentKind: String, Codable, CaseIterable, Sendable {
    case ghost
    case balloon
    case headline
    case plugin
}

public struct RecentContentItem: Codable, Equatable, Sendable {
    public let kind: RecentContentKind
    public let identifier: String
    public let name: String

    public init(kind: RecentContentKind, identifier: String, name: String) {
        self.kind = kind
        self.identifier = identifier
        self.name = name
    }
}

@MainActor
public final class RecentContentStore {
    private let defaults: UserDefaults
    private let key: String
    private var maximumCount: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = "dev.utatane.recent-content",
        maximumCount: Int = 12
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumCount = max(maximumCount, 1)
    }

    public var items: [RecentContentItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentContentItem].self, from: data)
        else { return [] }
        return Array(decoded.prefix(maximumCount))
    }

    public func record(kind: RecentContentKind, identifier: String, name: String) {
        guard !identifier.isEmpty, !name.isEmpty else { return }
        let item = RecentContentItem(kind: kind, identifier: identifier, name: name)
        let remaining = items.filter {
            $0.kind != item.kind || $0.identifier != item.identifier
        }
        save(Array(([item] + remaining).prefix(maximumCount)))
    }

    public func retain(_ predicate: (RecentContentItem) -> Bool) {
        save(items.filter(predicate))
    }

    public func setMaximumCount(_ maximumCount: Int) {
        self.maximumCount = max(maximumCount, 1)
        save(items)
    }

    private func save(_ items: [RecentContentItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}

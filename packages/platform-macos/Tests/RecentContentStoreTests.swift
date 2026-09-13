import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test
@MainActor
func `recent content moves repeated entries to the front`() throws {
    let suiteName = "RecentContentStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = RecentContentStore(defaults: defaults, key: "test", maximumCount: 3)

    store.record(kind: .ghost, identifier: "/ghost/a", name: "A")
    store.record(kind: .balloon, identifier: "/balloon/b", name: "B")
    store.record(kind: .ghost, identifier: "/ghost/a", name: "A renamed")

    #expect(store.items == [
        RecentContentItem(kind: .ghost, identifier: "/ghost/a", name: "A renamed"),
        RecentContentItem(kind: .balloon, identifier: "/balloon/b", name: "B")
    ])
}

@Test
@MainActor
func `recent content is capped and can discard unavailable entries`() throws {
    let suiteName = "RecentContentStoreLimitTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = RecentContentStore(defaults: defaults, key: "test", maximumCount: 2)

    store.record(kind: .ghost, identifier: "a", name: "A")
    store.record(kind: .headline, identifier: "b", name: "B")
    store.record(kind: .plugin, identifier: "c", name: "C")
    #expect(store.items.map(\.identifier) == ["c", "b"])

    store.retain { $0.kind != .headline }
    #expect(store.items.map(\.identifier) == ["c"])
}

@Test
@MainActor
func `recent content ignores corrupted stored data`() throws {
    let suiteName = "RecentContentStoreCorruptionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data("not json".utf8), forKey: "test")

    let store = RecentContentStore(defaults: defaults, key: "test")

    #expect(store.items.isEmpty)
}

@Test
@MainActor
func `recent content limit can change without recreating the store`() throws {
    let suiteName = "RecentContentStoreDynamicLimitTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = RecentContentStore(defaults: defaults, key: "test", maximumCount: 3)
    store.record(kind: .ghost, identifier: "a", name: "A")
    store.record(kind: .ghost, identifier: "b", name: "B")
    store.record(kind: .ghost, identifier: "c", name: "C")

    store.setMaximumCount(2)

    #expect(store.items.map(\.identifier) == ["c", "b"])
}

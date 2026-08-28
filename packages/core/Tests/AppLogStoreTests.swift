import Combine
import Foundation
import Testing
@testable import UtataneCore

struct AppLogStoreTests {
    @Test func `logs entries and enforces limit`() {
        let store = AppLogStore(maxEntries: 3)
        store.info("message 1", category: "Test")
        store.warning("message 2", category: "Test")
        store.error("message 3", category: "Test", details: "stack trace", ghostName: "Ria")
        store.debug("message 4", category: "Test")

        let entries = store.snapshot()
        #expect(entries.count == 3)
        #expect(entries[0].message == "message 2")
        #expect(entries[1].message == "message 3")
        #expect(entries[1].ghostName == "Ria")
        #expect(entries[1].details == "stack trace")
        #expect(entries[2].message == "message 4")
    }

    @Test func `clears entries`() {
        let store = AppLogStore()
        store.info("hello", category: "Test")
        var entries = store.snapshot()
        #expect(entries.count == 1)

        store.clear()
        entries = store.snapshot()
        #expect(entries.isEmpty)
    }

    @Test func `ring wraps repeatedly without changing previously read snapshots`() {
        let store = AppLogStore(maxEntries: 3)
        for index in 0 ..< 3 {
            store.debug("\(index)")
        }
        let original = store.snapshot()
        for index in 3 ..< 100 {
            store.debug("\(index)")
        }
        #expect(original.map(\.message) == ["0", "1", "2"])
        #expect(store.snapshot().map(\.message) == ["97", "98", "99"])
        store.clear()
        store.error("after clear")
        #expect(store.snapshot().map(\.message) == ["after clear"])
    }

    @Test @MainActor func `hidden logging is bounded and publishes only on refresh`() {
        let store = AppLogStore(maxEntries: 20)
        var publications = 0
        let subscription = store.$entries.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        for index in 0 ..< 1000 {
            store.debug("\(index)")
        }
        #expect(publications == 0)
        #expect(store.entries.isEmpty)
        #expect(store.snapshot().count == 20)

        store.publishSnapshot()
        #expect(publications == 1)
        #expect(store.entries.map(\.message) == (980 ..< 1000).map(String.init))
        store.publishSnapshot()
        #expect(publications == 1)

        store.discardPublishedSnapshot()
        #expect(store.entries.isEmpty)
        #expect(store.snapshot().count == 20)
        let hiddenPublications = publications
        store.warning("hidden warning")
        store.error("hidden error")
        #expect(publications == hiddenPublications)
        #expect(store.entries.isEmpty)
        store.publishSnapshot()
        #expect(publications == hiddenPublications + 1)
        #expect(store.entries.suffix(2).map(\.message) == ["hidden warning", "hidden error"])
    }

    @Test @MainActor func `clear does not restore stale published entries`() {
        let store = AppLogStore()
        store.info("old")
        store.publishSnapshot()
        store.info("unpublished")
        store.clear()
        store.publishSnapshot()
        #expect(store.entries.isEmpty)
        store.error("new")
        store.publishSnapshot()
        #expect(store.entries.map(\.message) == ["new"])
    }

    @Test func `zero and negative capacities do not retain entries`() {
        for capacity in [0, -1] {
            let store = AppLogStore(maxEntries: capacity)
            store.info("discarded")
            #expect(store.snapshot().isEmpty)
        }
    }

    @Test func `concurrent producers preserve entries and each producers order`() async {
        let store = AppLogStore(maxEntries: 400)
        await withTaskGroup(of: Void.self) { group in
            for producer in 0 ..< 4 {
                group.addTask {
                    for index in 0 ..< 100 {
                        store.debug("\(index)", category: "\(producer)")
                    }
                }
            }
        }
        let entries = store.snapshot()
        #expect(entries.count == 400)
        #expect(Set(entries.map(\.id)).count == 400)
        for producer in 0 ..< 4 {
            #expect(entries.filter { $0.category == "\(producer)" }.map(\.message) == (0 ..< 100).map(String.init))
        }
    }

    @Test func `formats text`() {
        let entry = LogEntry(
            level: .error,
            category: "Update",
            message: "Update failed",
            details: "404 Not Found",
            ghostName: "Ria"
        )
        let text = AppLogStore.formatText(for: [entry])
        #expect(text.contains("[ERROR]"))
        #expect(text.contains("[Update]"))
        #expect(text.contains("[Ria]"))
        #expect(text.contains("Update failed"))
        #expect(text.contains("404 Not Found"))
    }
}

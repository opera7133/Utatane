import Foundation
import Testing
@testable import UtataneCore

struct AppLogStoreTests {
    @Test func `logs entries and enforces limit`() async {
        let store = AppLogStore(maxEntries: 3)
        store.info("message 1", category: "Test")
        store.warning("message 2", category: "Test")
        store.error("message 3", category: "Test", details: "stack trace", ghostName: "Ria")
        store.debug("message 4", category: "Test")

        // Wait a bit for MainActor publish
        try? await Task.sleep(for: .milliseconds(50))

        let entries = await MainActor.run { store.entries }
        #expect(entries.count == 3)
        #expect(entries[0].message == "message 2")
        #expect(entries[1].message == "message 3")
        #expect(entries[1].ghostName == "Ria")
        #expect(entries[1].details == "stack trace")
        #expect(entries[2].message == "message 4")
    }

    @Test func `clears entries`() async {
        let store = AppLogStore()
        store.info("hello", category: "Test")
        try? await Task.sleep(for: .milliseconds(50))

        var entries = await MainActor.run { store.entries }
        #expect(entries.count == 1)

        store.clear()
        try? await Task.sleep(for: .milliseconds(50))

        entries = await MainActor.run { store.entries }
        #expect(entries.isEmpty)
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

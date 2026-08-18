import Foundation
import Testing
@testable import UtataneRuntime

@Test
func `persists ghost variables as JSON`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "variables.json", directoryHint: .notDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstStore = GhostVariableStore(fileURL: fileURL)
    try await firstStore.setValue("めもりーな", forKey: "name")
    try await firstStore.setValue("1", forKey: "boot-count")

    let reloadedStore = GhostVariableStore(fileURL: fileURL)
    #expect(try await reloadedStore.value(forKey: "name") == "めもりーな")
    #expect(try await reloadedStore.snapshot() == ["boot-count": "1", "name": "めもりーな"])

    try await reloadedStore.setValue(nil, forKey: "boot-count")
    #expect(try await reloadedStore.value(forKey: "boot-count") == nil)
}

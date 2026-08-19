import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test
@MainActor
func `persists content selections independently for each ghost`() throws {
    let suiteName = "ContentSelectionStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ContentSelectionStore(defaults: defaults, namespace: "test")
    let ghostA = URL(filePath: "/ghosts/a", directoryHint: .isDirectory)
    let ghostB = URL(filePath: "/ghosts/b", directoryHint: .isDirectory)

    store.ghostDirectoryName = "a"
    store.setShellDirectoryName("master", for: ghostA)
    store.setBalloonDirectoryName("ssp", for: ghostA)
    store.setShellDirectoryName("winter", for: ghostB)

    #expect(store.ghostDirectoryName == "a")
    #expect(store.shellDirectoryName(for: ghostA) == "master")
    #expect(store.balloonDirectoryName(for: ghostA) == "ssp")
    #expect(store.shellDirectoryName(for: ghostB) == "winter")
    #expect(store.balloonDirectoryName(for: ghostB) == nil)
}

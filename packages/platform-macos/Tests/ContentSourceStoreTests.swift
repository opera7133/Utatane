import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test
@MainActor
func `content sources preserve configured state while refreshing built in paths`() throws {
    let suiteName = "ContentSourceStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let original = ContentSource(
        id: "standard.ghost",
        kind: .ghost,
        name: "Ghosts",
        directory: URL(filePath: "/old"),
        isBuiltIn: true
    )
    let first = ContentSourceStore(defaultSources: [original], defaults: defaults)
    var disabled = try #require(first.sources.first)
    disabled.isEnabled = false
    disabled.allowsAutomaticUpdates = false
    first.update(disabled)

    let moved = ContentSource(
        id: "standard.ghost",
        kind: .ghost,
        name: "Standard Ghosts",
        directory: URL(filePath: "/new"),
        isBuiltIn: true
    )
    let restored = ContentSourceStore(defaultSources: [moved], defaults: defaults)

    #expect(restored.sources == [ContentSource(
        id: "standard.ghost",
        kind: .ghost,
        name: "Standard Ghosts",
        directory: URL(filePath: "/new"),
        isEnabled: false,
        allowsAutomaticUpdates: false,
        isBuiltIn: true
    )])
}

@Test
@MainActor
func `content source directories follow priority and ignore duplicates`() throws {
    let suiteName = "ContentSourcePriorityTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let root = URL(filePath: "/ghosts", directoryHint: .isDirectory)
    let store = ContentSourceStore(defaultSources: [ContentSource(
        id: "standard.ghost",
        kind: .ghost,
        name: "Ghosts",
        directory: root,
        isBuiltIn: true
    )], defaults: defaults)
    _ = store.add(kind: .ghost, name: "Duplicate", directory: root)
    let second = store.add(
        kind: .ghost,
        name: "Second",
        directory: URL(filePath: "/second", directoryHint: .isDirectory)
    )

    #expect(store.enabledDirectories(for: .ghost) == [
        root.standardizedFileURL,
        second.directory.standardizedFileURL
    ])
    store.move(kind: .ghost, fromOffsets: IndexSet(integer: 2), toOffset: 0)
    #expect(store.enabledDirectories(for: .ghost).first == second.directory.standardizedFileURL)
}

@Test
@MainActor
func `built in content sources cannot be removed`() throws {
    let suiteName = "ContentSourceRemovalTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let source = ContentSource(
        id: "standard.plugin",
        kind: .plugin,
        name: "Plugins",
        directory: URL(filePath: "/plugins"),
        isBuiltIn: true
    )
    let store = ContentSourceStore(defaultSources: [source], defaults: defaults)

    store.remove(id: source.id)

    #expect(store.sources == [source])
}

import Foundation
import Testing
import UtataneBalloon
import UtataneCore
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

@Test
@MainActor
func `falls back from deleted shell and balloon selections`() throws {
    let suiteName = "ContentSelectionStoreFallbackTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ContentSelectionStore(defaults: defaults, namespace: "test")
    let root = URL(filePath: "/ghosts/a", directoryHint: .isDirectory)
    let master = InstalledShell(
        name: "Master",
        directory: root.appending(path: "shell/master", directoryHint: .isDirectory)
    )
    let ghost = InstalledGhost(
        name: "A",
        rootDirectory: root,
        defaultShellDirectory: master.directory,
        shells: [master],
        defaultBalloonDirectoryName: "ghost-balloon"
    )
    let first = balloon("first")
    let ghostBalloon = balloon("ghost-balloon")
    let globalBalloon = balloon("global-balloon")
    store.setShellDirectoryName("deleted-shell", for: ghost.id)
    store.setBalloonDirectoryName("deleted-balloon", for: ghost.id)

    #expect(store.resolveShell(for: ghost) == master)
    #expect(store.resolveBalloon(
        for: ghost,
        from: [first, globalBalloon, ghostBalloon],
        defaultDirectoryName: "global-balloon"
    ) == ghostBalloon)
    #expect(store.shellDirectoryName(for: ghost.id) == "master")
    #expect(store.balloonDirectoryName(for: ghost.id) == "ghost-balloon")
}

private func balloon(_ directoryName: String) -> BalloonDefinition {
    BalloonDefinition(
        directory: URL(filePath: "/balloons/\(directoryName)", directoryHint: .isDirectory),
        name: directoryName,
        originX: 0,
        originY: 0,
        wordWrapPointX: 0,
        wordWrapPointY: 0,
        fontHeight: 12,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )
}

import Foundation
import Testing
@testable import UtatanePlatformMacOS

@MainActor
@Test func `content explorer keeps one shared catalog across content kinds`() {
    let ghost = ContentExplorerEntry(
        kind: .ghost,
        name: "Emily",
        detail: "emily4",
        directory: URL(filePath: "/tmp/Ghosts/emily4", directoryHint: .isDirectory)
    )
    let balloon = ContentExplorerEntry(
        kind: .balloon,
        name: "Origin",
        detail: "origin",
        directory: URL(filePath: "/tmp/Balloons/origin", directoryHint: .isDirectory)
    )
    let model = ContentExplorerModel()

    model.update(entries: [ghost, balloon], preferredKind: .ghost)
    #expect(model.filteredEntries == [ghost])
    #expect(model.selectedEntry == ghost)

    model.selectedKind = .balloon
    model.searchText = "orig"
    model.selection = model.filteredEntries.first?.id
    #expect(model.filteredEntries == [balloon])
    #expect(model.selectedEntry == balloon)
}

@MainActor
@Test func `content explorer selects an available kind when a catalog changes`() {
    let plugin = ContentExplorerEntry(
        kind: .plugin,
        name: "Sample Plugin",
        directory: URL(filePath: "/tmp/Plugins/sample", directoryHint: .isDirectory)
    )
    let model = ContentExplorerModel()

    model.update(entries: [plugin], preferredKind: .ghost)

    #expect(model.selectedKind == .plugin)
    #expect(model.selectedEntry == plugin)
}

@MainActor
@Test func `content explorer opens at a practical browsing size`() {
    let controller = ContentExplorerWindowController()
    let entry = ContentExplorerEntry(
        kind: .ghost,
        name: "Emily",
        directory: URL(filePath: "/tmp/Ghosts/emily4", directoryHint: .isDirectory)
    )
    controller.show(
        entries: [entry],
        onActivate: { _ in },
        onCheckUpdate: { _ in },
        onUpdate: { _ in },
        onRemove: { _ in }
    )
    defer { controller.close() }

    #expect(controller.contentSize?.width == 1120)
    #expect(controller.contentSize?.height == 720)
    #expect(ContentExplorerWindowController.minimumContentSize.width < ContentExplorerWindowController.initialContentSize.width)
    #expect(ContentExplorerWindowController.minimumContentSize.height < ContentExplorerWindowController.initialContentSize.height)
}

@MainActor
@Test func `content explorer keeps distribution and update URLs separate`() throws {
    let distributionURL = try #require(URL(string: "https://example.test/plugin/"))
    let updateURL = try #require(URL(string: "https://updates.example.test/plugin/"))
    let entry = ContentExplorerEntry(
        kind: .plugin,
        name: "Sample Plugin",
        directory: URL(filePath: "/tmp/Plugins/sample", directoryHint: .isDirectory),
        websiteURL: distributionURL,
        updateURL: updateURL
    )

    #expect(entry.websiteURL == distributionURL)
    #expect(entry.updateURL == updateURL)
    #expect(entry.hasUpdateAction)
    #expect(entry.canUpdate)

    let updateOnlyEntry = ContentExplorerEntry(
        kind: .balloon,
        name: "Origin",
        directory: URL(filePath: "/tmp/Balloons/origin", directoryHint: .isDirectory),
        updateURL: updateURL
    )
    #expect(updateOnlyEntry.websiteURL == nil)
    #expect(updateOnlyEntry.hasUpdateAction)
}

@Test func `content explorer can expose runtime resolved ghost updates`() {
    let entry = ContentExplorerEntry(
        kind: .ghost,
        name: "Emily",
        directory: URL(filePath: "/tmp/Ghosts/emily4", directoryHint: .isDirectory),
        resolvesUpdateURLDynamically: true
    )

    #expect(entry.updateURL == nil)
    #expect(entry.hasUpdateAction)
}

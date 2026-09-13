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
    controller.show(entries: [entry], onActivate: { _ in }, onRemove: { _ in })
    defer { controller.close() }

    #expect(controller.contentSize?.width == 1120)
    #expect(controller.contentSize?.height == 720)
    #expect(ContentExplorerWindowController.minimumContentSize.width < ContentExplorerWindowController.initialContentSize.width)
    #expect(ContentExplorerWindowController.minimumContentSize.height < ContentExplorerWindowController.initialContentSize.height)
}

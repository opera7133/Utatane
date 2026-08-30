import Foundation
import Testing
@testable import UtataneShell

@Test
func `loads an APNG base surface`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let image = root.appending(path: "surface0.apng", directoryHint: .notDirectory)
    try Data().write(to: image)
    try Data("surface0 {}".utf8).write(to: root.appending(path: "surfaces.txt"))

    let shell = try ShellLoader().load(from: root)
    let asset = try ShellLoader().loadSurface(id: 0, from: root)

    #expect(shell.surfaces[0] != nil)
    #expect(asset.imageURL == image)
}

@Test
func `loads legacy per-surface animation and collision files`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "surface0.png"))
    try Data("""
    0interval,sometimes
    0patturn0,100,5,overlay,105,86
    """.utf8).write(to: root.appending(path: "surface0a.txt"))
    try Data("""
    collision0,116,30,176,62,Head
    point.kinoko.centerx,135
    point.kinoko.centery,42
    """.utf8).write(to: root.appending(path: "surface0s.txt"))

    let shell = try ShellLoader().load(from: root)
    let surface = try #require(shell.surfaces[0])
    let animation = try #require(surface.animations.first { $0.id == 0 })

    #expect(animation.interval == "sometimes")
    #expect(animation.patterns.first?.surfaceID == 100)
    #expect(surface.collisions.first?.name == "Head")
    #expect(surface.points["kinoko.center"] == SurfacePoint(x: 135, y: 42))
}

@Test
func `loads an SSP element path containing backslashes`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let parts = root.appending(path: "parts", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
    let image = parts.appending(path: "21000_CC_2.png", directoryHint: .notDirectory)
    try Data().write(to: image)

    let asset = try ShellLoader().loadElement(
        filename: "parts\\21000_CC_2.png",
        from: root
    )

    #expect(asset.imageURL == image)
}

@Test
func `rejects traversal in an SSP element path containing backslashes`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    #expect(throws: ShellError.self) {
        try ShellLoader().loadElement(filename: "..\\outside.png", from: root)
    }
}

@Test
func `loads bundled ria winter outfit with expressions and hand collision`() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let shellDirectory = repositoryRoot.appending(
        path: "Content/Bundled/Ghosts/ria/shell/master",
        directoryHint: .isDirectory
    )

    let shell = try ShellLoader().load(from: shellDirectory)
    let base = try #require(shell.surfaces[20000])
    let expression = try #require(shell.surfaces[20322])

    #expect(base.elements.first?.filename == "surface20000.png")
    #expect(base.collisions.contains { $0.name == "Hand" })
    #expect(expression.elements.contains { $0.filename == "surface00322.png" })
}

@Test
func `parses bind names options defaults and add ids`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("""
    charset,UTF-8
    sakura.bindgroup10.name,服,コート,coat.png
    sakura.bindgroup10.default,1
    sakura.bindgroup10.addid,20,21
    sakura.bindgroup11.name,服,パーカー
    sakura.bindoption0.group,服,mustselect+multiple
    char2.bindgroup30.name,帽子,ニット帽
    """.utf8).write(to: root.appending(path: "descript.txt"))
    try Data("surface0 {}".utf8).write(to: root.appending(path: "surfaces.txt"))

    let shell = try ShellLoader().load(from: root)

    #expect(shell.defaultBindGroups[0] == [10])
    #expect(shell.bindGroups[0]?[10] == ShellBindGroup(
        id: 10,
        category: "服",
        part: "コート",
        thumbnail: "coat.png",
        addIDs: [20, 21]
    ))
    #expect(shell.bindGroups[2]?[30]?.part == "ニット帽")
    #expect(shell.bindOptions[0]?["服"] == ShellBindOptions(mustSelect: true, multiple: true))
    #expect(shell.effectiveBindGroups(scope: 0, enabled: [10]) == [10, 20, 21])
}

@Test
func `loads surfacetable development metadata without treating names as aliases`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("surface0 {}".utf8).write(to: root.appending(path: "surfaces.txt"))
    try Data("""
    charset,UTF-8
    version,1
    option,DisableNoDefineSurfaces

    group,__disabled
    {
        4000,__parts
    }
    group,[メイド]通常
    {
        scope,0
        0,素
        1,
    }
    """.utf8).write(to: root.appending(path: "surfacetable.txt"))

    let shell = try ShellLoader().load(from: root)
    let table = try #require(shell.surfaceTable)

    #expect(table.version == 1)
    #expect(table.disablesUndefinedSurfaces)
    #expect(table.groups.count == 2)
    #expect(table.groups[0].isDisabled)
    #expect(table.groups[0].entries[0].isPart)
    #expect(table.groups[1].scope == 0)
    #expect(table.entriesByID[0]?.name == "素")
    #expect(table.entriesByID[1]?.name == "")
    #expect(shell.resolveSurface("素", scope: 0) == nil)
}

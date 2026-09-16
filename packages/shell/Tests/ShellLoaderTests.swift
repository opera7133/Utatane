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
func `loads an image only legacy shell`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "surface0.png"))
    try Data().write(to: root.appending(path: "surface12.png"))

    let shell = try ShellLoader().load(from: root)

    #expect(shell.surfaces.keys.sorted() == [0, 12])
}

@Test
func `loads full self alpha mode`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("seriko.use_self_alpha,full".utf8).write(to: root.appending(path: "descript.txt"))
    try Data("surface0 {}".utf8).write(to: root.appending(path: "surfaces.txt"))

    let shell = try ShellLoader().load(from: root)

    #expect(shell.usesSelfAlpha)
    #expect(shell.usesFullSelfAlpha)
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
func `loads an SSP element path containing a yen separator`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    let parts = root.appending(path: "parts", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
    let image = parts.appending(path: "coat.png", directoryHint: .notDirectory)
    try Data().write(to: image)

    let asset = try ShellLoader().loadElement(filename: "parts¥coat.png", from: root)

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
    sakura.menuitem0,11
    sakura.menuitem1,-
    sakura.menuitemex2,冬のコート,10
    char2.menu,hidden
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
    #expect(shell.bindMenuItems[0] == [
        .group(id: 11),
        .separator,
        .group(id: 10, title: "冬のコート")
    ])
    #expect(shell.hiddenBindMenuScopes == [2])
    #expect(shell.effectiveBindGroups(scope: 0, enabled: [10]) == [10, 20, 21])
}

@Test
func `parses shell window and balloon presentation defaults`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("""
    charset,UTF-8
    seriko.zorder,1,0,2
    seriko.sticky-window,0,1
    seriko.alignmenttodesktop,bottom
    sakura.seriko.alignmenttodesktop,free
    sakura.defaultx,120
    sakura.defaulty,450
    sakura.defaultleft,32
    sakura.defaulttop,48
    sakura.balloon.offsetx,10
    sakura.balloon.offsety,20
    sakura.balloon.offsetxl,30
    sakura.balloon.offsetyr,40
    sakura.balloon.alignment,left
    sakura.balloon.dontmove,true
    sakura.balloon.syncscale,true
    char2.seriko.alignmenttodesktop,top
    """.utf8).write(to: root.appending(path: "descript.txt"))
    try Data("surface0 {}".utf8).write(to: root.appending(path: "surfaces.txt"))

    let shell = try ShellLoader().load(from: root)
    let sakura = try #require(shell.presentationSettings[0])

    #expect(shell.zOrder == [1, 0, 2])
    #expect(shell.stickyWindowScopes == [0, 1])
    #expect(shell.desktopAlignment == .bottom)
    #expect(sakura.desktopAlignment == .free)
    #expect(sakura.defaultX == 120)
    #expect(sakura.defaultY == 450)
    #expect(sakura.defaultLeft == 32)
    #expect(sakura.defaultTop == 48)
    #expect(sakura.balloonOffsets == ShellBalloonOffsets(x: 10, y: 20, leftX: 30, rightY: 40))
    #expect(sakura.balloonAlignment == .left)
    #expect(sakura.preventsBalloonMovement)
    #expect(sakura.synchronizesBalloonScale)
    #expect(shell.presentationSettings[2]?.desktopAlignment == .top)
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

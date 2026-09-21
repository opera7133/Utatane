import AppKit
import CoreText
import SwiftUI
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@Test func `default ghost dialogue font prefers Japanese glyphs`() {
    let font = ghostDialogueFont(named: nil, size: 14)
    let resolved = CTFontCreateForString(
        font as CTFont,
        "漢" as CFString,
        CFRange(location: 0, length: 1)
    )
    #expect((CTFontCopyPostScriptName(resolved) as String).contains("Hiragino"))

    let explicit = ghostDialogueFont(named: "Menlo", size: 14)
    #expect(explicit.fontName.contains("Menlo"))
}

@Test func `automatic animation probabilities match SERIKO intervals`() {
    #expect(automaticAnimationRandomDenominator(components: ["sometimes"], parameter: nil) == 2)
    #expect(automaticAnimationRandomDenominator(components: ["rarely"], parameter: nil) == 4)
    #expect(automaticAnimationRandomDenominator(components: ["random"], parameter: 7) == 7)
    #expect(automaticAnimationRandomDenominator(components: ["periodic"], parameter: 7) == nil)
}

@Test func `automatic surface fit only shrinks oversized images`() {
    #expect(automaticSurfaceFitScale(
        imageSize: NSSize(width: 400, height: 600),
        visibleSize: NSSize(width: 1440, height: 900)
    ) == 1)
    #expect(abs(automaticSurfaceFitScale(
        imageSize: NSSize(width: 676, height: 1000),
        visibleSize: NSSize(width: 1440, height: 900)
    ) - 0.675) < 0.0001)
    #expect(automaticSurfaceFitScale(imageSize: NSSize(width: 676, height: 1000), visibleSize: nil) == 1)
}

@Test func `chooses interaction cursors from collision regions`() {
    #expect(SurfaceCursorStyle(region: nil) == .arrow)
    #expect(SurfaceCursorStyle(region: "Head") == .openHand)
    #expect(SurfaceCursorStyle(region: "Ear1") == .openHand)
    #expect(SurfaceCursorStyle(region: "hair") == .openHand)
    #expect(SurfaceCursorStyle(region: "Mouth") == .pointingHand)
    #expect(SurfaceCursorStyle(region: "MenuButton") == .pointingHand)
}

@MainActor
@Test func `collision overlay state survives developer palette reconstruction`() {
    let controller = SurfaceWindowController()

    #expect(!controller.isCollisionModeEnabled)
    #expect(controller.showsCollisionNames)

    controller.setCollisionMode(true, showsNames: false)

    #expect(controller.isCollisionModeEnabled)
    #expect(!controller.showsCollisionNames)
}

@MainActor
@Test func `renders all Emily Phase4 default characters`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(path: "Content/Local/Ghosts/emily4/shell/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    let shell = try ShellLoader().load(from: root)
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10, 2: 200])
    #expect(controller.visibleScopes == [0, 1, 2])
    #expect(controller.renderedImage(for: 2) != nil)
    controller.hideAll()
}

@MainActor
@Test func `renders Juda System default characters`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(path: "Content/Local/Ghosts/Juda-System/shell/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    let shell = try ShellLoader().load(from: root)
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10])
    #expect(controller.visibleScopes == [0, 1])
    #expect(try #require(controller.renderedImage(for: 0)).hasVisiblePixels)
    #expect(controller.renderedImage(for: 1) != nil)
    try controller.changeSurface(scope: 0, to: 1)
    for animationID in [6, 29, 7, 4, 5, 40] {
        controller.playAnimation(id: animationID, scope: 0)
        #expect(
            try #require(controller.renderedImage(for: 0)).hasVisiblePixels,
            "animation \(animationID) must contribute visible pixels"
        )
    }
    #expect(try #require(controller.renderedImage(for: 0)).hasVisiblePixels)
    controller.hideAll()
}

@MainActor
@Test func `animates a surface stored with the APNG extension`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(Data(base64Encoded: animatedPNGBase64))
        .write(to: directory.appending(path: "surface0.apng"))

    let controller = SurfaceWindowController()
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:]), surfaceID: 0)
    defer { controller.hideAll() }

    let rendered = try #require(controller.renderedImage())
    let representation = try #require(rendered.representations.first as? NSBitmapImageRep)
    #expect(representation.value(forProperty: .frameCount) as? Int == 2)
    #expect(controller.isImageAnimationEnabled())
}

@MainActor
@Test func `dumps selected surfaces with a prefix`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let output = directory.appending(path: "output", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 8, height: 8, color: .red).write(to: directory.appending(path: "surface2.png"))

    let controller = SurfaceWindowController()
    try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:]), surfaceID: 0)
    defer { controller.hideAll() }

    let count = try controller.dumpSurfaceImages(
        to: output,
        scope: 0,
        surfaceList: "surface0-2,!surface1",
        prefix: "preview"
    )
    #expect(count == 2)
    #expect(FileManager.default.fileExists(atPath: output.appending(path: "preview0.png").path))
    #expect(FileManager.default.fileExists(atPath: output.appending(path: "preview2.png").path))

    #expect(throws: CocoaError.self) {
        try controller.dumpSurfaceImages(
            to: output,
            scope: 0,
            surfaceList: "surface0",
            prefix: "../escaped"
        )
    }
}

@MainActor
@Test func `animates an APNG base after composing a static surface element`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(Data(base64Encoded: animatedPNGBase64))
        .write(to: directory.appending(path: "body.apng"))
    try makePNG(width: 1, height: 1, color: .green)
        .write(to: directory.appending(path: "badge.png"))
    let definition = SurfaceDefinition(
        id: 5,
        elements: [
            SurfaceElement(id: 0, method: "base", filename: "body.apng", x: 0, y: 0),
            SurfaceElement(id: 1, method: "overlay", filename: "badge.png", x: 0, y: 0)
        ],
        collisions: [],
        animations: []
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [5: definition], usesSelfAlpha: true),
        surfaceID: 5
    )
    defer { controller.hideAll() }

    let rendered = try #require(controller.renderedImage())
    let representation = try #require(rendered.representations.first as? NSBitmapImageRep)
    #expect(representation.value(forProperty: .frameCount) as? Int == 2)
    #expect(controller.isImageAnimationEnabled())
}

@MainActor
@Test func `renders an asis element without applying its transparency`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "body.png"))
    let definition = SurfaceDefinition(
        id: 5,
        elements: [SurfaceElement(id: 0, method: "asis", filename: "body.png", x: 0, y: 0)],
        collisions: [],
        animations: []
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [5: definition], usesSelfAlpha: true),
        surfaceID: 5
    )
    defer { controller.hideAll() }

    #expect(try #require(controller.renderedImage()).transparentPixelRatio == 0)
}

@MainActor
@Test func `renders remaining elements when an optional element image is missing`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 4, height: 4, color: .green).write(to: directory.appending(path: "body.png"))
    try makePNG(width: 2, height: 2, color: .blue).write(to: directory.appending(path: "badge.png"))
    let definition = SurfaceDefinition(
        id: 5,
        elements: [
            SurfaceElement(id: 0, method: "base", filename: "body.png", x: 0, y: 0),
            SurfaceElement(id: 1, method: "overlay", filename: "missing.png", x: 0, y: 0),
            SurfaceElement(id: 2, method: "overlay", filename: "badge.png", x: 0, y: 0)
        ],
        collisions: [],
        animations: []
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [5: definition], usesSelfAlpha: true),
        surfaceID: 5
    )
    defer { controller.hideAll() }

    #expect(controller.renderedImage() != nil)
}

@MainActor
@Test func `renders an asis bind pattern without applying its transparency`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface1.png"))
    let definition = SurfaceDefinition(
        id: 0,
        collisions: [],
        animations: [SurfaceAnimation(
            id: 1,
            interval: "bind",
            patterns: [SurfaceAnimationPattern(
                order: 0,
                method: "asis",
                surfaceID: 1,
                waitMilliseconds: 0,
                x: 0,
                y: 0
            )]
        )]
    )
    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(
            directory: directory,
            surfaces: [0: definition],
            usesSelfAlpha: true,
            defaultBindGroups: [0: [1]]
        ),
        surfaceID: 0
    )
    defer { controller.hideAll() }

    #expect(try #require(controller.renderedImage()).transparentPixelRatio == 0)
}

@MainActor
@Test func `renders the installed Umaumauma default APNG surfaces`() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = repositoryRoot.appending(
        path: "Content/Local/Ghosts/umaumauma/shell/master",
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: root.path) else { return }

    let shell = try ShellLoader().load(from: root)
    #expect(shell.surfaces[2004]?.elements.map(\.filename) == ["tb1020.png", "tb1204.png"])
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 10])
    defer { controller.hideAll() }

    let renderedHorse = try #require(controller.renderedImage(for: 0))
    #expect(controller.renderedImage(for: 1) != nil)
    #expect(renderedHorse.transparentPixelRatio > 0.5)
    try controller.changeSurface(scope: 2, to: 999)
    #expect(try #require(controller.renderedImage(for: 2)).transparentPixelRatio == 1)
}

@MainActor
@Test func `persistent animation layers follow SERIKO animation ID order`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))

    func animation(_ id: Int) -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: "never",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: id,
                waitMilliseconds: 0, x: 0, y: 0
            )]
        )
    }
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [animation(2), animation(1)]
        )],
        usesSelfAlpha: true
    )
    #expect(shell.surfaces[0]?.animations.map(\.id) == [2, 1])
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 2, scope: 0)
    controller.playAnimation(id: 1, scope: 0)
    let color = try #require(controller.renderedImage(for: 0)?.colorAtCenter())
    #expect(color.blueComponent > 0.9)
    #expect(color.redComponent < 0.1)
}

@MainActor
@Test func `SERIKO insert reserves a nested bind layer position`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))
    let outer = SurfaceAnimation(
        id: 10, interval: "bind",
        patterns: [
            SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: 1,
                waitMilliseconds: 0, x: 0, y: 0
            ),
            SurfaceAnimationPattern(
                order: 1, method: "insert", surfaceID: 20,
                waitMilliseconds: 0, x: 0, y: 0, targetAnimationIDs: [20]
            )
        ]
    )
    let nested = SurfaceAnimation(
        id: 20, interval: "bind",
        patterns: [SurfaceAnimationPattern(
            order: 0, method: "overlay", surfaceID: 2,
            waitMilliseconds: 0, x: 0, y: 0
        )]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(id: 0, collisions: [], animations: [outer, nested])],
        usesSelfAlpha: true,
        defaultBindGroups: [0: [10, 20]]
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    let color = try #require(controller.renderedImage(for: 0)?.colorAtCenter())
    #expect(color.blueComponent > 0.9)
    #expect(color.redComponent < 0.1)
}

@MainActor
@Test func `independent SERIKO animations remain visible concurrently`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 8, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 2, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 2, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))

    func animation(_ id: Int, x: Int) -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: "never",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: id,
                waitMilliseconds: 500, x: x, y: 0
            )]
        )
    }
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [animation(1, x: 0), animation(2, x: 6)]
        )],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 1, scope: 0)
    controller.playAnimation(id: 2, scope: 0)
    try await requireEventually {
        guard let image = controller.renderedImage(for: 0) else { return false }
        let containsRed = image.containsColor { $0.redComponent > 0.8 && $0.blueComponent < 0.2 }
        let containsBlue = image.containsColor { $0.blueComponent > 0.8 && $0.redComponent < 0.2 }
        return containsRed && containsBlue
    }

    let image = try #require(controller.renderedImage(for: 0))
    #expect(image.containsColor { $0.redComponent > 0.8 && $0.blueComponent < 0.2 })
    #expect(image.containsColor { $0.blueComponent > 0.8 && $0.redComponent < 0.2 })
}

@MainActor
@Test func `exclusive SERIKO animation stops and blocks only its configured targets`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 9, height: 3, color: .clear).write(to: directory.appending(path: "surface0.png"))
    let colors: [NSColor] = [
        NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1),
        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1),
        NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
    ]
    for (index, color) in colors.enumerated() {
        try makePNG(width: 3, height: 3, color: color)
            .write(to: directory.appending(path: "surface\(index + 1).png"))
    }
    func animation(_ id: Int, x: Int, exclusiveIDs: Set<Int>? = nil) -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: "never",
            options: exclusiveIDs == nil ? [] : ["exclusive"],
            exclusiveAnimationIDs: exclusiveIDs,
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: id,
                waitMilliseconds: 1000, x: x, y: 0
            )]
        )
    }
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [
                animation(1, x: 0, exclusiveIDs: [2]),
                animation(2, x: 3),
                animation(3, x: 6)
            ]
        )],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 2, scope: 0)
    controller.playAnimation(id: 3, scope: 0)
    controller.playAnimation(id: 1, scope: 0)
    try await Task.sleep(for: .milliseconds(80))
    controller.playAnimation(id: 2, scope: 0)
    try await Task.sleep(for: .milliseconds(40))

    let image = try #require(controller.renderedImage(for: 0))
    #expect(image.containsColor { $0.redComponent > 0.8 && $0.blueComponent < 0.2 })
    #expect(!image.containsColor { $0.blueComponent > 0.8 && $0.redComponent < 0.2 })
    #expect(image.containsColor { $0.greenComponent > 0.8 && $0.redComponent < 0.2 })
}

@MainActor
@Test func `shared index resumes the current pattern across a surface change`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface10.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))
    let shared = SurfaceAnimation(
        id: 5,
        interval: "never",
        options: ["shared-index"],
        patterns: [
            SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: 1,
                waitMilliseconds: 20, x: 0, y: 0
            ),
            SurfaceAnimationPattern(
                order: 1, method: "overlay", surfaceID: 2,
                waitMilliseconds: 1000, x: 0, y: 0
            )
        ]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [
            0: SurfaceDefinition(id: 0, collisions: [], animations: [shared]),
            10: SurfaceDefinition(id: 10, collisions: [], animations: [shared])
        ],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 5, scope: 0)
    try await requireEventually {
        controller.renderedImage(for: 0)?.containsColor { $0.blueComponent > 0.8 } == true
    }
    try controller.changeSurface(scope: 0, to: 10)
    try await requireEventually {
        controller.renderedImage(for: 0)?.containsColor {
            $0.blueComponent > 0.8 && $0.redComponent < 0.2
        } == true
    }

    let image = try #require(controller.renderedImage(for: 0))
    #expect(image.containsColor { $0.blueComponent > 0.8 && $0.redComponent < 0.2 })
    #expect(!image.containsColor { $0.redComponent > 0.8 && $0.blueComponent < 0.2 })
}

@MainActor
@Test func `background SERIKO animation stays behind the base surface`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    let background = SurfaceAnimation(
        id: 1,
        interval: "runonce",
        options: ["background"],
        patterns: [SurfaceAnimationPattern(
            order: 0, method: "overlay", surfaceID: 1,
            waitMilliseconds: 0, x: 0, y: 0
        )]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(id: 0, collisions: [], animations: [background])],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    let color = try #require(controller.renderedImage(for: 0)?.colorAtCenter())
    #expect(color.redComponent > 0.8)
    #expect(color.blueComponent < 0.2)
}

@MainActor
@Test func `SERIKO control patterns start and stop animations in parallel`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 8, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 2, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 2, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))
    let targetAnimations = [
        SurfaceAnimation(
            id: 1, interval: "never",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: 1,
                waitMilliseconds: 1000, x: 0, y: 0
            )]
        ),
        SurfaceAnimation(
            id: 2, interval: "never",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: 2,
                waitMilliseconds: 1000, x: 6, y: 0
            )]
        )
    ]
    let start = SurfaceAnimation(
        id: 0, interval: "never",
        patterns: [SurfaceAnimationPattern(
            order: 0, method: "parallelstart", surfaceID: 1,
            waitMilliseconds: 0, x: 0, y: 0, targetAnimationIDs: [1, 2]
        )]
    )
    let stop = SurfaceAnimation(
        id: 3, interval: "never",
        patterns: [SurfaceAnimationPattern(
            order: 0, method: "parallelstop", surfaceID: 1,
            waitMilliseconds: 0, x: 0, y: 0, targetAnimationIDs: [1, 2]
        )]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0, collisions: [], animations: [start] + targetAnimations + [stop]
        )],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 0, scope: 0)
    try await requireEventually {
        guard let image = controller.renderedImage(for: 0) else { return false }
        return image.containsColor { $0.redComponent > 0.8 }
            && image.containsColor { $0.blueComponent > 0.8 }
    }
    var image = try #require(controller.renderedImage(for: 0))
    #expect(image.containsColor { $0.redComponent > 0.8 })
    #expect(image.containsColor { $0.blueComponent > 0.8 })

    controller.playAnimation(id: 3, scope: 0)
    try await requireEventually {
        guard let candidate = controller.renderedImage(for: 0) else { return false }
        return !candidate.containsColor { $0.redComponent > 0.8 }
            && !candidate.containsColor { $0.blueComponent > 0.8 }
    }
    image = try #require(controller.renderedImage(for: 0))
    #expect(!image.containsColor { $0.redComponent > 0.8 })
    #expect(!image.containsColor { $0.blueComponent > 0.8 })
}

@MainActor
@Test func `SERIKO scaling temporarily resizes the character window`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 20, height: 10).write(to: directory.appending(path: "surface0.png"))
    let scaling = SurfaceAnimation(
        id: 0, interval: "never",
        patterns: [SurfaceAnimationPattern(
            order: 0, method: "scaling", surfaceID: -1,
            waitMilliseconds: 300, x: 200, y: 150,
            scaleXPercent: 200, scaleYPercent: 150
        )]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(id: 0, collisions: [], animations: [scaling])],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }
    let initialSize = try #require(controller.windowFrame(for: 0)?.size)

    controller.playAnimation(id: 0, scope: 0)
    try await requireEventually {
        controller.windowFrame(for: 0)?.width ?? 0 >= initialSize.width * 1.9
    }
    let scaledSize = try #require(controller.windowFrame(for: 0)?.size)
    #expect(scaledSize.width == initialSize.width * 2)
    #expect(scaledSize.height == initialSize.height * 1.5)

    await controller.waitForAnimation(id: 0)
    #expect(controller.windowFrame(for: 0)?.size == initialSize)
}

@MainActor
@Test func `SERIKO import waits before playing an external animation once`() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try #require(Data(base64Encoded: animatedPNGBase64)).write(to: directory.appending(path: "blink.apng"))
    let imported = SurfaceAnimation(
        id: 0, interval: "never",
        patterns: [SurfaceAnimationPattern(
            order: 0, method: "import", surfaceID: -1,
            waitMilliseconds: 150, x: 0, y: 0, fileName: "blink.apng"
        )]
    )
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(id: 0, collisions: [], animations: [imported])],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    controller.playAnimation(id: 0, scope: 0)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!controller.isImageAnimationEnabled())
    try await requireEventually {
        controller.isImageAnimationEnabled()
    }
    #expect(controller.isImageAnimationEnabled())

    await controller.waitForAnimation(id: 0)
    #expect(!controller.isImageAnimationEnabled())
}

@MainActor
@Test func `runonce animation layers follow SERIKO animation ID order`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: directory.appending(path: "surface0.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    ).write(to: directory.appending(path: "surface1.png"))
    try makePNG(
        width: 4, height: 4,
        color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    ).write(to: directory.appending(path: "surface2.png"))

    func runonce(_ id: Int) -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: "runonce",
            patterns: [SurfaceAnimationPattern(
                order: 0, method: "overlay", surfaceID: id,
                waitMilliseconds: 0, x: 0, y: 0
            )]
        )
    }
    let shell = ShellDefinition(
        directory: directory,
        surfaces: [0: SurfaceDefinition(
            id: 0,
            collisions: [],
            animations: [runonce(2), runonce(1)]
        )],
        usesSelfAlpha: true
    )
    let controller = SurfaceWindowController()
    try controller.show(shell: shell, scope: 0, surfaceID: 0)
    defer { controller.hideAll() }

    let color = try #require(controller.renderedImage(for: 0)?.colorAtCenter())
    #expect(color.blueComponent > 0.9)
    #expect(color.redComponent < 0.1)
}

@Test func `head strokes emit at a finer movement interval`() {
    #expect(SurfaceStrokeEventPolicy.minimumDistance(for: "Head") == 2)
    #expect(SurfaceStrokeEventPolicy.minimumDistance(for: "head") == 2)
    #expect(SurfaceStrokeEventPolicy.minimumDistance(for: "Hair") == 4)
}

@Test func `accepts NAR and ZIP files dropped on a surface`() {
    let urls = [
        URL(filePath: "/tmp/ghost.nar"),
        URL(filePath: "/tmp/SHELL.NAR"),
        URL(filePath: "/tmp/old_ghost.zip"),
        URL(filePath: "/tmp/BALLOON.ZIP"),
        URL(filePath: "/tmp/readme.txt"),
        URL(filePath: "/tmp/not-a-nar")
    ]

    #expect(SurfaceDropPayload.narURLs(from: urls).map(\.lastPathComponent) == [
        "ghost.nar", "SHELL.NAR", "old_ghost.zip", "BALLOON.ZIP"
    ])
}

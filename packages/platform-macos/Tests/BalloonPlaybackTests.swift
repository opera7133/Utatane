import AppKit
import CoreText
import SwiftUI
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@Test
@MainActor
func `cancels vanish playback on a balloon double click`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var heldReferences: (String, Int, Int)?
    var presentationReady = false
    player.onVanishButtonHold = { heldReferences = ($0, $1, $2) }
    let source = #"消滅します\_w[5000]\e"#
    let playback = Task {
        await player.playAndWait(
            SakuraScript(rawValue: source),
            balloon: makeBalloon(directory: directory),
            characterDelayMilliseconds: 0,
            context: .init(eventID: "OnVanishSelected"),
            onPresentationReady: { presentationReady = true }
        )
    }
    try await requireEventually { presentationReady }
    balloonController.onDoubleClick?(0)
    await playback.value

    #expect(player.didCancelVanishPlayback)
    #expect(heldReferences?.0 == source)
    #expect(heldReferences?.1 == 0)
}

@Test
@MainActor
func `keeps every speaker balloon until a completed dialogue is clicked`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 40, height: 80).write(
        to: directory.appending(path: "surface0000.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 20, height: 30).write(
        to: directory.appending(path: "surface0010.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 25, height: 35).write(
        to: directory.appending(path: "surface0200.png", directoryHint: .notDirectory)
    )
    let balloonImage = try makePNG(width: 120, height: 80)
    try balloonImage.write(to: directory.appending(path: "balloons0.png", directoryHint: .notDirectory))
    try balloonImage.write(to: directory.appending(path: "balloonk0.png", directoryHint: .notDirectory))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 10)
    try surfaceController.show(shell: shell, scope: 2, surfaceID: 200)
    defer { surfaceController.hideAll() }

    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var closedScript: String?
    player.onBalloonClose = { closedScript = $0 }
    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 4,
        originY: 4,
        wordWrapPointX: -4,
        wordWrapPointY: -4,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    let source = "\\0Sakura\\1Kero\\p[2]Charlie\\e"
    await player.playAndWait(
        SakuraScript(rawValue: source),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )
    #expect(balloonController.visibleScopes == [0, 1, 2])

    player.advance()
    #expect(balloonController.visibleScopes.isEmpty)
    #expect(closedScript == source)
}

@Test
@MainActor
func `does not show a balloon until its scope has text`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for surfaceID in [0, 5, 10] {
        try makePNG(width: 30, height: 40).write(
            to: directory.appending(
                path: String(format: "surface%04d.png", surfaceID),
                directoryHint: .notDirectory
            )
        )
    }
    let balloonImage = try makePNG(width: 120, height: 80)
    try balloonImage.write(to: directory.appending(path: "balloons0.png"))
    try balloonImage.write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        defaultSurfaceIDs: [0: 0, 1: 10]
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let balloon = makeBalloon(directory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: "\\u\\s[10]\\h\\s[5]hello\\e"),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.visibleScopes == [0])
}

@Test
@MainActor
func `changes balloon surface before and during dialogue`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons2.png"))
    try makePNG(width: 140, height: 90).write(to: directory.appending(path: "balloons3.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\b2hello\b[3]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.style(for: 0) == 3)
    #expect(balloonController.windowFrame(for: 0)?.size == NSSize(width: 140, height: 90))
}

@Test
@MainActor
func `negative balloon surface keeps a not yet shown scope hidden`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0010.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        defaultSurfaceIDs: [0: 0, 1: 10]
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\1\b[-1]非表示\0表示\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.visibleScopes == [0])
}

@Test
@MainActor
func `clears dialogue text in every active scope`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0001.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 1)
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\0さくら\1うにゅう\C\0後\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "後")
    #expect(balloonController.textAndLinks(for: 1)?.0 == "")
}

@Test
@MainActor
func `leading capital C continues the previous dialogue without hiding other scopes`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0001.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloonk0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 1)
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController,
        postDialogueDismissalMilliseconds: 60000
    )
    let balloon = makeBalloon(directory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"\0元のセリフ\1元の相方\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )
    await player.playAndWait(
        SakuraScript(rawValue: #"\C\1\cリンクの結果\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.visibleScopes == [0, 1])
    #expect(balloonController.textAndLinks(for: 0)?.0 == "元のセリフ")
    #expect(balloonController.textAndLinks(for: 1)?.0 == "リンクの結果")
}

@Test
@MainActor
func `partially clears characters and lines`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"abcdef\c[char,2]X\none\ntwo\nthree\c[line,1]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "abcdX\none\ntwo\n")
}

@Test
@MainActor
func `waits until elapsed playback time and resets the precise wait clock`() async {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let player = SakuraScriptPlayer(
        surfaceWindowController: SurfaceWindowController(positionStore: positionStore),
        balloonWindowController: BalloonWindowController(positionStore: positionStore)
    )
    let startedAt = Date()

    await player.playAndWait(
        SakuraScript(rawValue: #"\__w[80]\__w[clear]\__w[80]\e"#),
        balloon: makeBalloon(directory: FileManager.default.temporaryDirectory),
        characterDelayMilliseconds: 0
    )

    #expect(Date().timeIntervalSince(startedAt) >= 0.14)
}

@Test
@MainActor
func `renders SakuraScript font styles by text range`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try FileManager.default.copyItem(
        at: URL(fileURLWithPath: "/System/Library/Fonts/Menlo.ttc"),
        to: directory.appending(path: "custom.ttc")
    )

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\f[valign,bottom]A\f[color,#ff0000]B\f[bold,1]C\f[underline,true]D\f[sub,1]E\f[sup,1]F\f[sup,0]G\f[default]H\f[shadowcolor,#ffff00]I\f[shadowstyle,outline]J\f[shadowcolor,none]K\f[outline,true]L\f[outline,false]MN\f[align,right]O\n[half]P\f[name,custom.ttc]\f[height,large]Q\f[height,smaller]R\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let red = try #require(balloonController.textAttributes(at: 1, scope: 0)?[.foregroundColor] as? NSColor)
    #expect(red.redComponent > 0.9)
    let boldFont = try #require(balloonController.textAttributes(at: 2, scope: 0)?[.font] as? NSFont)
    #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
    #expect(balloonController.textAttributes(at: 3, scope: 0)?[.underlineStyle] as? Int == 1)
    let subOffset = try #require(balloonController.textAttributes(at: 4, scope: 0)?[.baselineOffset] as? CGFloat)
    let supOffset = try #require(balloonController.textAttributes(at: 5, scope: 0)?[.baselineOffset] as? CGFloat)
    #expect(subOffset < 0)
    #expect(supOffset > 0)
    #expect(balloonController.textAttributes(at: 6, scope: 0)?[.baselineOffset] == nil)
    #expect(balloonController.textAttributes(at: 7, scope: 0)?[.underlineStyle] == nil)
    let shadow = try #require(balloonController.textAttributes(at: 8, scope: 0)?[.shadow] as? NSShadow)
    #expect(shadow.shadowColor != nil)
    #expect(balloonController.textAttributes(at: 9, scope: 0)?[.strokeWidth] as? Int == -3)
    #expect(balloonController.textAttributes(at: 10, scope: 0)?[.shadow] == nil)
    #expect(balloonController.textAttributes(at: 11, scope: 0)?[.strokeWidth] as? Int == 3)
    #expect(balloonController.textAttributes(at: 12, scope: 0)?[.strokeWidth] == nil)
    let aligned = try #require(
        balloonController.textAttributes(at: 13, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(aligned.alignment == .right)
    let halfLine = try #require(
        balloonController.textAttributes(at: 14, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(halfLine.minimumLineHeight == 0)
    #expect(halfLine.maximumLineHeight == 0)
    #expect(balloonController.textAttributes(at: 16, scope: 0)?[.paragraphStyle] == nil)
    let largeFont = try #require(balloonController.textAttributes(at: 17, scope: 0)?[.font] as? NSFont)
    let smallerFont = try #require(balloonController.textAttributes(at: 18, scope: 0)?[.font] as? NSFont)
    #expect(largeFont.fontName.contains("Menlo"))
    #expect(abs(largeFont.pointSize - 16.8) < 0.1)
    #expect(abs(smallerFont.pointSize - 14) < 0.1)
}

@Test
@MainActor
func `plain choice dispatches only the ordinary choice event`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var ordinaryChoice: String?
    var extendedChoice: String?
    player.onChoice = { id, _ in ordinaryChoice = id }
    player.onChoiceSelectEx = { _, id, _ in extendedChoice = id }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[話す頻度はこれでいいの？,talkinterval]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    let link = try #require(balloonController.textAndLinks(for: 0)?.1.first)
    balloonController.onLinkActivate?(link, "話す頻度はこれでいいの？")
    balloonController.onLinkClick?(link.id, link.arguments)

    #expect(ordinaryChoice == "talkinterval")
    #expect(extendedChoice == nil)
    #expect(balloonController.visibleScopes.isEmpty)
}

@Test
@MainActor
func `unified choice callback suppresses independent legacy dispatch`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 180, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var selection: (String, String, [String])?
    var ordinaryChoice = false
    var independentExtendedChoice = false
    player.onChoiceSelection = { selection = ($0, $1, $2) }
    player.onChoice = { _, _ in ordinaryChoice = true }
    player.onChoiceSelectEx = { _, _, _ in independentExtendedChoice = true }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[秋,LikeSeason,月見,菊]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    let link = try #require(balloonController.textAndLinks(for: 0)?.1.first)
    balloonController.onLinkActivate?(link, "秋")
    balloonController.onLinkClick?(link.id, link.arguments)

    #expect(selection?.0 == "秋")
    #expect(selection?.1 == "LikeSeason")
    #expect(selection?.2 == ["月見", "菊"])
    #expect(!ordinaryChoice)
    #expect(!independentExtendedChoice)
}

@Test
@MainActor
func `choice and anchor enter and hover events preserve link references`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 220, height: 120).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var choiceEvents: [(String?, String?, [String])] = []
    var anchorEvents: [(String?, String?, [String])] = []
    var choiceHoverEvents: [(String, String, [String])] = []
    var anchorHoverEvents: [(String, String, [String])] = []
    player.onChoiceEnter = { choiceEvents.append(($0, $1, $2)) }
    player.onAnchorEnter = { anchorEvents.append(($0, $1, $2)) }
    player.onChoiceHover = { choiceHoverEvents.append(($0, $1, $2)) }
    player.onAnchorHover = { anchorHoverEvents.append(($0, $1, $2)) }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[選択肢,choice-id,extra]\n\_a[anchor-id,anchor-extra]アンカー\_a\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    let links = try #require(balloonController.textAndLinks(for: 0)?.1)
    let choice = try #require(links.first { $0.kind == .choice })
    let anchor = try #require(links.first { $0.kind == .anchor })
    balloonController.onLinkEnter?(choice, "選択肢")
    balloonController.onLinkEnter?(nil, nil)
    balloonController.onLinkEnter?(anchor, "アンカー")
    balloonController.onLinkEnter?(nil, nil)
    balloonController.onLinkHover?(choice, "選択肢")
    balloonController.onLinkHover?(anchor, "アンカー")

    #expect(choiceEvents.count == 2)
    #expect(choiceEvents[0].0 == "選択肢")
    #expect(choiceEvents[0].1 == "choice-id")
    #expect(choiceEvents[0].2 == ["extra"])
    #expect(choiceEvents[1].0 == nil)
    #expect(anchorEvents.count == 2)
    #expect(anchorEvents[0].0 == "アンカー")
    #expect(anchorEvents[0].1 == "anchor-id")
    #expect(anchorEvents[0].2 == ["anchor-extra"])
    #expect(anchorEvents[1].0 == nil)
    #expect(choiceHoverEvents.count == 1)
    #expect(choiceHoverEvents[0].0 == "選択肢")
    #expect(choiceHoverEvents[0].1 == "choice-id")
    #expect(choiceHoverEvents[0].2 == ["extra"])
    #expect(anchorHoverEvents.count == 1)
    #expect(anchorHoverEvents[0].0 == "アンカー")
    #expect(anchorHoverEvents[0].1 == "anchor-id")
    #expect(anchorHoverEvents[0].2 == ["anchor-extra"])
}

@Test
@MainActor
func `anchor response interrupts and then resumes the script that contains it`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 200, height: 120).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let balloon = makeBalloon(directory: directory)
    player.onAnchorSelectEx = { _, _, _ in
        player.interrupt(
            with: SakuraScript(rawValue: #"\C\1アンカー応答\e"#),
            balloon: balloon,
            characterDelayMilliseconds: 0
        )
    }

    player.play(
        SakuraScript(rawValue: #"\0\_a[keyword,keyword,KW]語\_a後続のセリフが最後まで流れる\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 20
    )
    try await requireEventually {
        balloonController.textAndLinks(for: 0)?.1.isEmpty == false
    }
    let link = try #require(balloonController.textAndLinks(for: 0)?.1.first)
    balloonController.onLinkActivate?(link, "語")
    balloonController.onLinkClick?(link.id, link.arguments)
    let expected = "語後続のセリフが最後まで流れる"
    try await requireEventually {
        balloonController.textAndLinks(for: 0)?.0 == expected
            && balloonController.textAndLinks(for: 1)?.0 == "アンカー応答"
    }

    #expect(balloonController.textAndLinks(for: 0)?.0 == expected)
    #expect(balloonController.textAndLinks(for: 1)?.0 == "アンカー応答")
}

@Test
@MainActor
func `numeric cursor moves separate compact ghost menu rows`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 240, height: 160).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"お気に入り\_l[0,0]\f[align,right]閉じる\_l[0,@12]罫線\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textAndLinks(for: 0)?.0 == "お気に入り\t閉じる\n罫線")
    let rightAligned = try #require(
        balloonController.textAttributes(at: 5, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(rightAligned.tabStops.count == 1)
    #expect(rightAligned.tabStops[0].alignment == .right)
    #expect(rightAligned.firstLineHeadIndent == 0)
    let relativeRow = try #require(
        balloonController.textAttributes(at: 10, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(relativeRow.firstLineHeadIndent == 0)
    #expect(abs(relativeRow.paragraphSpacingBefore + 5) < 1)
}

@Test
@MainActor
func `cursor moves resolve em and percent units into balloon coordinates`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 300, height: 240).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"先頭\_l[1em,2em]A\_l[12em,]B\_l[,@+70%]C\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let first = try #require(
        balloonController.textAttributes(at: 3, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    let second = try #require(
        balloonController.textAttributes(at: 5, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    let third = try #require(
        balloonController.textAttributes(at: 7, scope: 0)?[.paragraphStyle] as? NSParagraphStyle
    )
    #expect(abs(first.firstLineHeadIndent - 14) < 0.5)
    #expect(abs(second.firstLineHeadIndent - 168) < 0.5)
    #expect(third.firstLineHeadIndent > second.firstLineHeadIndent)
    #expect(third.paragraphSpacingBefore > 0)
}

@Test
@MainActor
func `clicking a terminal wait clears and closes the balloon`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    player.play(
        SakuraScript(rawValue: #"クリックして閉じる\x\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        !balloonController.visibleScopes.isEmpty
    }
    #expect(balloonController.visibleScopes == [0])

    player.advance()
    try await requireEventually {
        balloonController.visibleScopes.isEmpty
    }
    #expect(balloonController.visibleScopes.isEmpty)
}

@Test
@MainActor
func `renders adjacent extended choices without inserting a newline`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"\__q[OnSelect,arg]選択肢\__q次\f[anchor.font.color,#00ff00]\_a[OnAnchor]錨\_a\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let content = try #require(balloonController.textAndLinks(for: 0))
    #expect(content.0 == "選択肢次錨")
    #expect(content.1 == [
        BalloonTextLink(
            range: NSRange(location: 0, length: 3),
            id: "OnSelect",
            arguments: ["arg"]
        ),
        BalloonTextLink(
            range: NSRange(location: 4, length: 1),
            id: "OnAnchor",
            arguments: [],
            kind: .anchor,
            fontColor: BalloonColor(red: 0, green: 255, blue: 0)
        )
    ])
    let anchorColor = try #require(
        balloonController.textAttributes(at: 4, scope: 0)?[.foregroundColor] as? NSColor
    )
    #expect(anchorColor.greenComponent > 0.9)
}

@Test
@MainActor
func `applies balloon default font decoration`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let balloon = BalloonDefinition(
        directory: directory,
        name: "decorated",
        originX: 10,
        originY: 10,
        wordWrapPointX: -10,
        wordWrapPointY: -10,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        fontShadowColor: BalloonColor(red: 10, green: 20, blue: 30),
        fontShadowStyle: "outline",
        fontBold: true,
        fontItalic: true,
        fontUnderline: true,
        fontStrike: true
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"装飾\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    let attributes = try #require(balloonController.textAttributes(at: 0, scope: 0))
    let font = try #require(attributes[.font] as? NSFont)
    let traits = NSFontManager.shared.traits(of: font)
    #expect(traits.contains(.boldFontMask))
    #expect(attributes[.obliqueness] as? Double == 0.2)
    #expect(attributes[.underlineStyle] as? Int == 1)
    #expect(attributes[.strikethroughStyle] as? Int == 1)
    #expect(attributes[.strokeWidth] as? Int == -3)
}

@Test
@MainActor
func `lays out vertical balloon text with vertical glyphs`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 300, height: 200).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    let balloon = BalloonDefinition(
        directory: directory,
        name: "vertical",
        originX: 280,
        originY: 20,
        wordWrapPointX: 0,
        wordWrapPointY: 180,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0),
        validRectLeft: 20,
        validRectTop: 20,
        validRectRight: 280,
        validRectBottom: 180,
        isVertical: true
    )

    await player.playAndWait(
        SakuraScript(rawValue: #"縦書き\e"#),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )

    #expect(balloonController.textLayoutOrientation(scope: 0) == .vertical)
    #expect(balloonController.textAttributes(at: 0, scope: 0)?[.verticalGlyphForm] as? Int == 1)
}

@Test
@MainActor
func `runs a script choice directly without dispatching a SHIORI choice`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var dispatchedChoice = false
    player.onChoice = { _, _ in dispatchedChoice = true }

    await player.playAndWait(
        SakuraScript(rawValue: #"\q[実行,script:\0直接実行\e]"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    let initial = try #require(balloonController.textAndLinks(for: 0))
    #expect(initial.1.first?.id == #"script:\0直接実行\e"#)

    balloonController.onLinkClick?(initial.1[0].id, initial.1[0].arguments)
    try await requireEventually {
        balloonController.textAndLinks(for: 0)?.0 == "直接実行"
    }

    #expect(balloonController.textAndLinks(for: 0)?.0 == "直接実行")
    #expect(!dispatchedChoice)
}

@Test
@MainActor
func `expands environment names and replaces the script after raise`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let geometry = MutablePresentationGeometryProvider(
        screens: [
            PresentationScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 960, height: 540),
                visibleFrame: CGRect(x: 0, y: 0, width: 960, height: 520),
                bitsPerPixel: 32,
                scale: 2,
                isPrimary: true
            )
        ]
    )
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController,
        geometryProvider: geometry
    )
    player.configure(environmentVariables: ["selfname": "さくら"])
    player.onEmbeddedEvent = { id, arguments in
        #expect(id == "OnRaised")
        #expect(arguments == ["arg"])
        return SakuraScript(rawValue: "応答\\e")
    }

    await player.playAndWait(
        SakuraScript(rawValue: #"%selfnameと%me（%screenwidth×%screenheight）から\![raise,OnRaised,arg]捨てる\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let content = try #require(balloonController.textAndLinks(for: 0))
    #expect(content.0.hasPrefix("さくらと"))
    #expect(content.0.contains("960×540"))
    #expect(content.0.hasSuffix("から応答"))
    #expect(!content.0.contains("%me"))
}

@Test
@MainActor
func `long balloon text scrolls and follows its bottom`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(
        to: directory.appending(path: "balloons0.png", directoryHint: .notDirectory)
    )
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "arrow0.png"))
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "arrow1.png"))

    let controller = BalloonWindowController(positionStore: positionStore)
    try controller.show(
        balloon: makeBalloon(directory: directory),
        text: (0 ..< 20).map { "line \($0)" }.joined(separator: "\n"),
        near: NSRect(x: 500, y: 100, width: 40, height: 80)
    )
    defer { controller.hideAll() }

    #expect(controller.isTextScrollable(scope: 0))
    #expect(controller.isTextAtBottom(scope: 0))
    let arrows = try #require(controller.scrollArrowVisibility(scope: 0))
    #expect(arrows.previous)
    #expect(!arrows.next)
}

@Test
@MainActor
func `online mode displays the balloon online marker`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "online0.png"))

    let controller = BalloonWindowController(positionStore: positionStore)
    try controller.show(
        balloon: makeBalloon(directory: directory),
        text: "online",
        near: NSRect(x: 500, y: 100, width: 40, height: 80)
    )
    defer { controller.hideAll() }

    controller.setOnlineMode(true, scope: 0)
    #expect(controller.isOnlineMarkerVisible(scope: 0))
    controller.setOnlineMode(false, scope: 0)
    #expect(!controller.isOnlineMarkerVisible(scope: 0))
}

@Test
@MainActor
func `SSTP sender marker survives balloon activation and can be cleared`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "sstp.png"))

    let controller = BalloonWindowController(positionStore: positionStore)
    controller.setSSTPMessage("Test Sender")
    try controller.show(
        balloon: makeBalloon(directory: directory),
        text: "SSTP本文",
        near: NSRect(x: 500, y: 100, width: 40, height: 80)
    )
    defer { controller.hideAll() }
    #expect(controller.displayedSSTPMessage(scope: 0) == "Test Sender")

    controller.setSSTPMessage(nil)
    #expect(controller.displayedSSTPMessage(scope: 0) == nil)
}

@Test
@MainActor
func `dismisses balloons before requesting surface restore`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for surfaceID in [0, 1, 10, 11] {
        try makePNG(width: 30, height: 40).write(
            to: directory.appending(
                path: String(format: "surface%04d.png", surfaceID),
                directoryHint: .notDirectory
            )
        )
    }
    let balloonImage = try makePNG(width: 120, height: 80)
    try balloonImage.write(to: directory.appending(path: "balloons0.png", directoryHint: .notDirectory))
    try balloonImage.write(to: directory.appending(path: "balloonk0.png", directoryHint: .notDirectory))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let shell = ShellDefinition(directory: directory, surfaces: [:])
    try surfaceController.show(shell: shell, scope: 0, surfaceID: 0)
    try surfaceController.show(shell: shell, scope: 1, surfaceID: 10)
    defer { surfaceController.hideAll() }

    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController,
        postDialogueDismissalMilliseconds: 20,
        surfaceRestoreDelayMilliseconds: 40
    )
    var didRequestSurfaceRestore = false
    var timedOutScript: String?
    player.onSurfaceRestore = { didRequestSurfaceRestore = true }
    player.onBalloonTimeout = { timedOutScript = $0 }
    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 4,
        originY: 4,
        wordWrapPointX: -4,
        wordWrapPointY: -4,
        fontHeight: 14,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )

    let source = "\\0\\s[1]Sakura\\1\\s[11]Kero\\e"
    player.play(
        SakuraScript(rawValue: source),
        balloon: balloon,
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        surfaceController.surfaceID(for: 0) == 1
    }
    #expect(surfaceController.surfaceID(for: 0) == 1)
    #expect(surfaceController.surfaceID(for: 1) == 11)
    try await requireEventually {
        balloonController.visibleScopes.isEmpty
    }
    #expect(balloonController.visibleScopes.isEmpty)
    #expect(timedOutScript == source)
    #expect(!didRequestSurfaceRestore)
    try await requireEventually {
        didRequestSurfaceRestore
    }
    #expect(didRequestSurfaceRestore)
}

@Test
@MainActor
func `times out choices after playback and dispatches the timeout event`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    var timedOutScript: String?
    player.onChoiceTimeout = { timedOutScript = $0 }

    let source = #"\q[選択,OnSelect]\![set,choicetimeout,20]\e"#
    await player.playAndWait(
        SakuraScript(rawValue: source),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        timedOutScript != nil
    }

    #expect(timedOutScript == source)
    #expect(balloonController.visibleScopes.isEmpty)
}

@Test
@MainActor
func `exposes time critical state only until playback ends`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: BalloonWindowController(positionStore: positionStore)
    )

    player.play(
        SakuraScript(rawValue: #"\t\_w[100]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )
    try await requireEventually {
        player.isTimeCritical
    }
    #expect(player.isTimeCritical)
    try await requireEventually {
        !player.isTimeCritical
    }
    #expect(!player.isTimeCritical)
}

@Test
@MainActor
func `balloon repaint lock defers content and movement lock tracks state`() throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))

    let controller = BalloonWindowController(positionStore: positionStore)
    try controller.show(
        balloon: makeBalloon(directory: directory),
        text: "old",
        near: NSRect(x: 500, y: 100, width: 40, height: 80)
    )
    defer { controller.hideAll() }

    controller.setVerticalAlignment(.bottom, scope: 0)
    #expect(try #require(controller.verticalContentInset(scope: 0)) > 0)
    controller.setVerticalAlignment(.top, scope: 0)
    #expect(controller.verticalContentInset(scope: 0) == 0)
    controller.setMarkerText("更新中", scope: 0)
    #expect(controller.markerText(scope: 0) == "更新中")
    #expect(controller.displayedMarkerText(scope: 0) == "更新中")
    controller.setMarkerText("", scope: 0)
    #expect(controller.markerText(scope: 0) == nil)
    #expect(controller.displayedMarkerText(scope: 0) == "")
    controller.setNumber(file: "download.zip", current: "2", maximum: "5", scope: 0)
    #expect(controller.numberText(scope: 0) == "download.zip 2/5")
    controller.setNumber(file: "", current: "", maximum: "", scope: 0)
    #expect(controller.numberText(scope: 0) == nil)
    controller.setOffset(x: 25, y: -10, scope: 0)
    #expect(controller.offset(scope: 0) == NSPoint(x: 25, y: -10))
    controller.resetOffset(scope: 0)
    #expect(controller.offset(scope: 0) == nil)
    controller.setAlignment(.bottom, scope: 0)
    #expect(controller.alignment(scope: 0) == .bottom)

    controller.setRepaintLocked(true, scope: 0)
    controller.updateContent(text: "new", links: [], scope: 0)
    #expect(controller.isRepaintLocked(scope: 0))
    #expect(controller.textAndLinks(for: 0)?.0 == "new")
    #expect(controller.displayedText(for: 0) == "old")

    controller.setRepaintLocked(false, scope: 0)
    #expect(!controller.isRepaintLocked(scope: 0))
    #expect(controller.displayedText(for: 0) == "new")

    controller.setMovementLocked(true, scope: 0)
    #expect(controller.isMovementLocked(scope: 0))
    controller.setMovementLocked(false, scope: 0)
    #expect(!controller.isMovementLocked(scope: 0))
}

@Test
@MainActor
func `updates window level with stayOnTop`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    let balloonController = BalloonWindowController(positionStore: positionStore)

    surfaceController.setStayOnTop(false)
    balloonController.setStayOnTop(false)
    surfaceController.setStayOnTop(true)
    balloonController.setStayOnTop(true)
}

@Test
@MainActor
func `handles zorder and sticky window configuration`() {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaceController = SurfaceWindowController(positionStore: positionStore)

    surfaceController.setStickyWindows(scopes: [0, 1])
    surfaceController.resetStickyWindows()
    surfaceController.setZOrder(["1", "0"])
    surfaceController.resetZOrder()
}

@Test
@MainActor
func `sets and resets a fixed surface position`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 30, height: 40).write(to: directory.appending(path: "surface0000.png"))

    let controller = SurfaceWindowController(positionStore: positionStore)
    try controller.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { controller.hideAll() }

    await controller.setFixedPosition(x: 120, y: 200, scope: 0)

    #expect(controller.windowFrame(for: 0)?.origin == NSPoint(x: 120, y: 200))
    #expect(controller.isMovementLocked(scope: 0))

    controller.resetFixedPositions()
    #expect(!controller.isMovementLocked(scope: 0))
}

@Test
@MainActor
func `renders inline balloon images`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 100).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makeTopLeftKeyedPNG(width: 16, height: 16).write(to: directory.appending(path: "icon.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    player.configure(resourceBaseDirectory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"画像\_b[icon.png,inline]表示\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let attachment = try #require(balloonController.textAttributes(at: 2, scope: 0)?[.attachment] as? NSTextAttachment)
    let font = try #require(balloonController.textAttributes(at: 2, scope: 0)?[.font] as? NSFont)
    #expect(attachment.bounds.height == 16)
    #expect(attachment.bounds.origin.y == (font.capHeight - 16) / 2)
    let image = try #require(attachment.image)
    let representation = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    #expect((representation.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
    #expect((representation.colorAt(x: 1, y: 0)?.alphaComponent ?? 0) > 0.9)
}

@Test
@MainActor
func `renders choice marker aligned with text cap height`() async throws {
    let (defaults, positionStore) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 100, height: 100).write(to: directory.appending(path: "surface0.png"))
    try makePNG(width: 160, height: 100).write(to: directory.appending(path: "balloons0.png"))
    try makePNG(width: 8, height: 8).write(to: directory.appending(path: "marker.png"))

    let surfaceController = SurfaceWindowController(positionStore: positionStore)
    try surfaceController.show(
        shell: ShellDefinition(directory: directory, surfaces: [:]),
        scope: 0,
        surfaceID: 0
    )
    defer { surfaceController.hideAll() }
    let balloonController = BalloonWindowController(positionStore: positionStore)
    let player = SakuraScriptPlayer(
        surfaceWindowController: surfaceController,
        balloonWindowController: balloonController
    )
    player.configure(resourceBaseDirectory: directory)

    await player.playAndWait(
        SakuraScript(rawValue: #"\_q\![*]\q[選択肢,choice_id]\e"#),
        balloon: makeBalloon(directory: directory),
        characterDelayMilliseconds: 0
    )

    let attachment = try #require(balloonController.textAttributes(at: 0, scope: 0)?[.attachment] as? NSTextAttachment)
    let font = try #require(balloonController.textAttributes(at: 0, scope: 0)?[.font] as? NSFont)
    #expect(attachment.bounds.height == 8)
    #expect(attachment.bounds.origin.y == (font.capHeight - 8) / 2)
}

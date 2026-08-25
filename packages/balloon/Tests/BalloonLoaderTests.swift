import Foundation
import Testing
@testable import UtataneBalloon

@Test
func `parses balloon layout and colors`() {
    let source = """
    charset,UTF-8
    type,balloon
    name,Test Balloon
    origin.x,14
    origin.y,18
    wordwrappoint.x,-30
    wordwrappoint.y,2
    font.height,12
    font.color.r,84
    font.color.g,32
    font.color.b,27
    """

    let values = BalloonDescriptParser().parse(source)

    #expect(values["name"] == "Test Balloon")
    #expect(values["origin.x"] == "14")
    #expect(values["wordwrappoint.x"] == "-30")
    #expect(values["font.color.b"] == "27")
}

@Test
func `uses valid rect as the text inset when available`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("""
    charset,UTF-8
    type,balloon
    name,Inset Balloon
    origin.x,0
    origin.y,0
    validrect.left,28
    validrect.top,14
    wordwrappoint.x,-48
    """.utf8).write(to: directory.appending(path: "descript.txt"))

    let balloon = try BalloonLoader().load(from: directory)

    #expect(balloon.originX == 28)
    #expect(balloon.originY == 14)
    #expect(balloon.wordWrapPointX == -48)
}

@Test
func `explicit text origin takes precedence over valid rect`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("""
    charset,UTF-8
    type,balloon
    name,SSP Compatible Balloon
    origin.x,20
    origin.y,40
    validrect.left,0
    validrect.top,30
    wordwrappoint.x,-34
    """.utf8).write(to: directory.appending(path: "descript.txt"))

    let balloon = try BalloonLoader().load(from: directory)

    #expect(balloon.originX == 20)
    #expect(balloon.originY == 40)
}

@Test
func `loads vertical writing layout using right and bottom valid rect defaults`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("""
    type,balloon
    name,Vertical Balloon
    vertical,1
    origin.x,0
    origin.y,0
    validrect.left,18
    validrect.top,22
    validrect.right,280
    validrect.bottom,180
    """.utf8).write(to: directory.appending(path: "descript.txt"))

    let balloon = try BalloonLoader().load(from: directory)

    #expect(balloon.isVertical)
    #expect(balloon.originX == 280)
    #expect(balloon.originY == 22)
    #expect(balloon.wordWrapPointY == 180)
    #expect(balloon.validRectLeft == 18)
    #expect(balloon.validRectBottom == 180)
}

@Test
func `loads SSP choice and anchor appearances`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("""
    charset,UTF-8
    type,balloon
    name,Styled Balloon
    cursor.style,square
    cursor.font.color.r,10
    cursor.font.color.g,20
    cursor.font.color.b,30
    cursor.brush.color.r,40
    cursor.brush.color.g,50
    cursor.brush.color.b,60
    cursor.notselect.style,none
    anchor.style,underline
    anchor.pen.color.r,70
    anchor.pen.color.g,80
    anchor.pen.color.b,90
    """.utf8).write(to: directory.appending(path: "descript.txt"))

    let balloon = try BalloonLoader().load(from: directory)

    #expect(balloon.cursorStyle.shape == .square)
    #expect(balloon.cursorStyle.fontColor == BalloonColor(red: 10, green: 20, blue: 30))
    #expect(balloon.cursorStyle.brushColor == BalloonColor(red: 40, green: 50, blue: 60))
    #expect(balloon.cursorNotSelectedStyle.shape == .none)
    #expect(balloon.anchorStyle.shape == .underline)
    #expect(balloon.anchorStyle.penColor == BalloonColor(red: 70, green: 80, blue: 90))
}

@Test
func `loads default balloon font decoration`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("""
    type,balloon
    name,Decorated Balloon
    font.name,Helvetica
    font.shadowcolor.r,10
    font.shadowcolor.g,20
    font.shadowcolor.b,30
    font.shadowstyle,outline
    font.bold,1
    font.italic,true
    font.underline,on
    font.strike,1
    font.outline,1
    """.utf8).write(to: directory.appending(path: "descript.txt"))

    let balloon = try BalloonLoader().load(from: directory)

    #expect(balloon.fontName == "Helvetica")
    #expect(balloon.fontShadowColor == BalloonColor(red: 10, green: 20, blue: 30))
    #expect(balloon.fontShadowStyle == "outline")
    #expect(balloon.fontBold)
    #expect(balloon.fontItalic)
    #expect(balloon.fontUnderline)
    #expect(balloon.fontStrike)
    #expect(balloon.fontOutline)
}

@Test
func `uses scope specific marker and falls back to common marker`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 0,
        originY: 0,
        wordWrapPointX: 0,
        wordWrapPointY: 0,
        fontHeight: 12,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )
    let loader = BalloonLoader()
    let common = directory.appending(path: "marker.png")
    try Data().write(to: common)
    #expect(loader.markerImageURL(speaker: .sakura, in: balloon) == common)

    let sakura = directory.appending(path: "markers.png")
    try Data().write(to: sakura)
    #expect(loader.markerImageURL(speaker: .sakura, in: balloon) == sakura)
}

@Test
func `uses scope specific balloon image and falls back for additional characters`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let balloon = BalloonDefinition(
        directory: directory,
        name: "test",
        originX: 0,
        originY: 0,
        wordWrapPointX: 0,
        wordWrapPointY: 0,
        fontHeight: 12,
        fontColor: BalloonColor(red: 0, green: 0, blue: 0)
    )
    let loader = BalloonLoader()
    let kero = directory.appending(path: "balloonk0.png")
    try Data().write(to: kero)
    #expect(try loader.imageURL(speaker: .character(scope: 2), in: balloon) == kero)

    let scope2 = directory.appending(path: "balloonp2def0.png")
    try Data().write(to: scope2)
    #expect(try loader.imageURL(speaker: .character(scope: 2), in: balloon) == scope2)
}

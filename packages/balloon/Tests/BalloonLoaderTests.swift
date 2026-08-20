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

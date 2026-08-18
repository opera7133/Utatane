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

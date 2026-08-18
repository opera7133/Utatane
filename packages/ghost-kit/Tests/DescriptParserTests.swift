import Testing
@testable import UtataneGhostKit

@Test
func `parses descript values and keeps commas in values`() {
    let source = """
    charset,UTF-8
    name,めもりーな
    menu.example,one,two
    """

    let values = DescriptParser().parse(source)

    #expect(values["charset"] == "UTF-8")
    #expect(values["name"] == "めもりーな")
    #expect(values["menu.example"] == "one,two")
}

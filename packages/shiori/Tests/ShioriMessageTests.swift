import Testing
@testable import UtataneShiori

@Test func `parses and serializes yaya request`() throws {
    let source = "GET SHIORI/3.0\r\nID: charset\r\nSender: ninix-aya\r\nSecurityLevel: local\r\n\r\n"
    let request = try ShioriMessageParser.parseRequest(source)

    #expect(request.method == "GET")
    #expect(request.version == "SHIORI/3.0")
    #expect(request.id == "charset")
    #expect(request.headers["sender"] == "ninix-aya")
    #expect(request.serialized() == source)
}

@Test
func `extracts numbered response references`() throws {
    let response = try ShioriMessageParser.parseResponse(
        "SHIORI/3.0 200 OK\r\nReference0: Emily\r\nreference1: hello\r\nX-Test: ignored\r\n\r\n"
    )

    #expect(response.referenceValues == [0: "Emily", 1: "hello"])
}

@Test func `parses response value and reason phrase`() throws {
    let source = "SHIORI/3.0 200 OK\r\nSender: YAYA\r\nValue: hello\r\n\r\n"
    let response = try ShioriMessageParser.parseResponse(source)

    #expect(response.statusCode == 200)
    #expect(response.reasonPhrase == "OK")
    #expect(response.value == "hello")
    #expect(response.serialized() == source)
}

@Test func `references are case insensitive and keep wire order`() throws {
    let source = "GET SHIORI/3.0\nReference1: second\nReference0: first\nX-Test: a\nX-Test: b\n\n"
    let request = try ShioriMessageParser.parseRequest(source)

    #expect(request.reference(0) == "first")
    #expect(request.headers.values(named: "x-test") == ["a", "b"])
    #expect(request.headers.entries.map(\.name) == ["Reference1", "Reference0", "X-Test", "X-Test"])
}

@Test func `rejects malformed header`() {
    #expect(throws: ShioriParseError.invalidHeader("ID OnBoot")) {
        try ShioriMessageParser.parseRequest("GET SHIORI/3.0\r\nID OnBoot\r\n\r\n")
    }
}

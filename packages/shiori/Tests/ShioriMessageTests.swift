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

@Test
func `converts SHIORI 3 event request to SHIORI 2 event request`() {
    let request = ShioriRequest(method: "GET", headers: ShioriHeaders([
        ShioriHeader(name: "Charset", value: "EUC-KR"),
        ShioriHeader(name: "Sender", value: "Utatane"),
        ShioriHeader(name: "ID", value: "OnBoot"),
        ShioriHeader(name: "Reference0", value: "0")
    ]))

    let converted = Shiori2Compatibility.eventRequest(from: request)

    #expect(converted?.serialized() == """
    GET Sentence SHIORI/2.6\r
    Charset: EUC-KR\r
    Sender: Utatane\r
    Reference0: 0\r
    Event: OnBoot\r
    \r

    """)
}

@Test
func `reads legacy SHIORI 2 sentence as script`() throws {
    let response = try ShioriMessageParser.parseResponse(
        "SHIORI/2.0 200 OK\r\nSentence: \\0hello\\e\r\nCharset: EUC-KR\r\n\r\n"
    )

    #expect(response.scriptValue == "\\0hello\\e")
    #expect(Shiori2Compatibility.shouldRetry(response) == false)
    #expect(Shiori2Compatibility.shouldRetry(ShioriResponse(
        version: "SHIORI/2.0",
        statusCode: 400,
        reasonPhrase: "Bad Request"
    )))
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

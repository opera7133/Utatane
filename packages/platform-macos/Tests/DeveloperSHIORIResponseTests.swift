import Testing
@testable import UtatanePlatformMacOS

@Test func `developer SHIORI response formats script and sorted references`() {
    let response = DeveloperSHIORIResponse.response(
        script: #"\0こんにちは\e"#,
        references: [2: "two", 0: "zero"]
    )

    #expect(response.script == #"\0こんにちは\e"#)
    #expect(
        response.formattedText
            == """
            Value: \\0こんにちは\\e
            Reference0: zero
            Reference2: two
            """
    )
}

@Test func `developer SHIORI response represents no content and errors`() {
    #expect(DeveloperSHIORIResponse.response(script: nil, references: [:]).formattedText == "No Content")
    #expect(DeveloperSHIORIResponse.failure("broken").formattedText == "Error: broken")
    #expect(DeveloperSHIORIResponse.failure("broken").script == nil)
}

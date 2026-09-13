import Foundation
import Testing
import UtataneCore
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

@Test func `developer palette reconstructs a logged SHIORI request for replay`() throws {
    let entry = LogEntry(
        level: .debug,
        category: "SHIORI",
        message: "SHIORI request: OnBoot",
        details: "Reference2: old\nReference0: zero\nReference2: two"
    )

    let request = try #require(DeveloperSHIORILogRequest(entry: entry))

    #expect(request.eventID == "OnBoot")
    #expect(request.references == [0: "zero", 2: "two"])
}

@Test func `developer virtual clock applies a moving offset`() {
    let realDate = Date(timeIntervalSince1970: 1000)
    let targetDate = Date(timeIntervalSince1970: 10000)
    let offset = DeveloperVirtualClock.offset(targetDate: targetDate, realDate: realDate)

    #expect(offset == 9000)
    #expect(
        DeveloperVirtualClock.date(
            realDate: realDate.addingTimeInterval(30),
            offset: offset
        ) == targetDate.addingTimeInterval(30)
    )
    #expect(DeveloperVirtualClock.date(realDate: realDate, offset: nil) == realDate)
}

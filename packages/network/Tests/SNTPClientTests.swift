import Foundation
import Testing
@testable import UtataneNetwork

@Test func `SNTP comparison formats extended and legacy references`() async throws {
    let serverDate = Date(timeIntervalSince1970: 1_735_732_800.125)
    let localDate = Date(timeIntervalSince1970: 1_735_732_798.625)
    let client = SNTPClient(fetchDate: { _ in serverDate })

    let comparison = try await client.compare(
        server: #require(URL(string: "https://time.example")),
        now: { localDate }
    )

    #expect(comparison.extendedReferences[0] == "https://time.example")
    #expect(comparison.extendedReferences[3] == "1.500")
    #expect(comparison.extendedReferences[4] == "1500")
    #expect(comparison.legacyReferences[3] == "1")
    #expect(comparison.legacyReferences[4] == "1500")
}

@Test func `corrected legacy references preserve offset sign`() {
    let comparison = SNTPComparison(
        server: "https://time.example",
        serverDate: Date(timeIntervalSince1970: 100),
        localDate: Date(timeIntervalSince1970: 101.25)
    )

    #expect(comparison.correctedLegacyReferences[3] == "-1")
    #expect(comparison.correctedLegacyReferences[4] == "-1250")
}

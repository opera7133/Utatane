import Testing
@testable import UtataneCore

@Test func `parses SSP recommendation resource rows`() {
    let value = [
        ["Site A", "https://example.test/a", "banner.png", #"\0Selected A\e"#].joined(separator: "\u{1}"),
        ["Site B", "script:\\![raise,OnSiteB]"].joined(separator: "\u{1}")
    ].joined(separator: "\u{2}")

    #expect(GhostSiteMenuParser().parse(value) == [
        GhostSiteMenuEntry(
            title: "Site A",
            target: "https://example.test/a",
            banner: "banner.png",
            selectionScript: #"\0Selected A\e"#
        ),
        GhostSiteMenuEntry(title: "Site B", target: "script:\\![raise,OnSiteB]")
    ])
}

@Test func `ignores incomplete SSP recommendation resource rows`() {
    let value = [
        "",
        "Title only",
        ["", "https://example.test/empty-title"].joined(separator: "\u{1}"),
        ["Valid", "https://example.test/valid"].joined(separator: "\u{1}")
    ].joined(separator: "\u{2}")

    #expect(GhostSiteMenuParser().parse(value) == [
        GhostSiteMenuEntry(title: "Valid", target: "https://example.test/valid")
    ])
}

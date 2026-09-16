import Foundation
import Testing
@testable import UtataneNetwork

@Test func `parses RSS and Atom entries`() throws {
    let rss = Data("""
    <rss><channel><title>News</title><link>https://example.test/</link>
    <item><title>First</title><link>https://example.test/1</link><description>Hello</description></item>
    </channel></rss>
    """.utf8)
    let rssFeed = try RSSFeedClient.parse(rss)
    #expect(rssFeed.title == "News")
    #expect(rssFeed.items.first?.title == "First")

    let atom = Data("""
    <feed><title>Atom</title><link href="https://example.test/"/>
    <entry><title>Entry</title><link href="https://example.test/e"/><summary>Text</summary></entry>
    </feed>
    """.utf8)
    let atomFeed = try RSSFeedClient.parse(atom)
    #expect(atomFeed.link == "https://example.test/")
    #expect(atomFeed.items.first?.link == "https://example.test/e")
}

@Test func `formats RSS dates for SHIORI references`() {
    #expect(RSSFeedClient.sspTimestamp("2026-09-16T12:30:45Z") == "2026,9,16,12,30,45")
    #expect(RSSFeedClient.sspTimestamp("Wed, 16 Sep 2026 12:30:45 +0000") == "2026,9,16,12,30,45")
    #expect(RSSFeedClient.sspTimestamp("not a date").isEmpty)
}

@Test func `RSS update fingerprint is stable and changes with feed content`() {
    let first = RSSFeed(
        title: "News",
        link: "https://example.test/",
        items: [.init(title: "First", link: "https://example.test/1", published: "2026-09-16")]
    )
    let same = RSSFeed(
        title: "News",
        link: "https://example.test/",
        items: [.init(title: "First", link: "https://example.test/1", published: "2026-09-16")]
    )
    let changed = RSSFeed(
        title: "News",
        link: "https://example.test/",
        items: [.init(title: "Second", link: "https://example.test/2", published: "2026-09-17")]
    )
    #expect(RSSFeedClient.updateFingerprint(first) == RSSFeedClient.updateFingerprint(same))
    #expect(RSSFeedClient.updateFingerprint(first) != RSSFeedClient.updateFingerprint(changed))
}

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

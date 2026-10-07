import Foundation
import Testing
@testable import UtataneNetwork

@Test func `URL payload detection and persistent sensor registration preserve feed URLs`() throws {
    let url = try #require(URL(string: "https://example.invalid/feed?a=1&b=2"))
    #expect(URLInstallPayload.detect(data: Data("<rss></rss>".utf8), url: url) == .feed)
    #expect(URLInstallPayload.detect(data: Data("BEGIN:VCALENDAR".utf8), url: url) == .ical)
    #expect(URLInstallPayload.detect(data: Data([0x50, 0x4B, 0x03, 0x04]), url: url) == .nar)
    #expect(URLInstallPayload.detect(data: Data("type,sakura_script_file\nscript,test".utf8), url: url) == .ssf)
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = try NetworkSensorStore().register(url: url, name: "Feed\nunsafe,metadata", type: .feed, root: root)
    #expect(try NetworkSensorStore().register(url: url, name: "Updated", type: .feed, root: root) == directory)
    let feeds = try HeadlineCatalog().load(from: root)
    #expect(feeds.count == 1)
    #expect(feeds[0].kind == .rss(feedURL: url))
    #expect(feeds[0].name == "Updated")
}

@Test func `SSF preserves commas script order and concurrent instructions`() throws {
    let file = try SakuraScriptFile(data: Data(#"""
    version,1.0
    type,sakura_script_file
    charset,UTF-8
    ghost,Test
    script,\![raise,OnTest,a,b]\e
    script_nowait,\0Hello\e
    wait,2000
    """#.utf8))
    #expect(file.steps == [.ghost("Test"), .script(#"\![raise,OnTest,a,b]\e"#, waitsForPrevious: true), .script(#"\0Hello\e"#, waitsForPrevious: false), .wait(milliseconds: 2000)])
    #expect(throws: (any Error).self) { try SakuraScriptFile(data: Data("type,wrong".utf8)) }
}

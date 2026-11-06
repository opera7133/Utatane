import Foundation
import Testing
@testable import UtataneNetwork

@Test(arguments: ["webcal", "webcals", "WEBCAL", "WebCals"])
func `calendar links normalize to HTTPS and preserve encoded feed parameters`(scheme: String) throws {
    let source = try #require(URL(string: "\(scheme)://example.invalid:8443/private/a%2Fb.ics?token=a%2Bb&x=1#view"))
    #expect(CalendarSubscriptionURL.matches(source))
    let url = try CalendarSubscriptionURL.normalized(source)
    #expect(url.absoluteString == "https://example.invalid:8443/private/a%2Fb.ics?token=a%2Bb&x=1")
}

@Test(arguments: ["https://example.invalid/a.ics", "http://example.invalid/a.nar", "file:///tmp/a.ics", "ftp://example.invalid/a", "webcal:relative", "webcals:///a.ics"])
func `calendar normalization rejects unrelated schemes and missing hosts`(value: String) throws {
    let source = try #require(URL(string: value))
    #expect(throws: NetworkFetchError.unsupportedURL) { try CalendarSubscriptionURL.normalized(source) }
}

@Test func `calendar scheme variants register a single persistent HTTPS subscription`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = NetworkSensorStore()
    let first = try CalendarSubscriptionURL.normalized(#require(URL(string: "webcal://example.invalid/feed?token=abc")))
    let second = try CalendarSubscriptionURL.normalized(#require(URL(string: "webcals://example.invalid/feed?token=abc")))
    let directory = try store.register(url: first, name: "Calendar", type: .ical, root: root)
    #expect(try store.register(url: second, name: "Updated", type: .ical, root: root) == directory)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    #expect(try String(contentsOf: directory.appending(path: "descript.txt"), encoding: .utf8)
        == "type,ical\nname,Updated\nurl,https://example.invalid/feed?token=abc\n")
}

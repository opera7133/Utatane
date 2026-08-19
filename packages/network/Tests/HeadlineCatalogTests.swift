import Foundation
import Testing
@testable import UtataneNetwork

@Test func `loads RSS and legacy DLL headline descriptors`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let rss = root.appending(path: "rss")
    let legacy = root.appending(path: "legacy")
    try FileManager.default.createDirectory(at: rss, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("type,rss\nname,News\nfeed,https://example.test/feed.xml\n".utf8).write(to: rss.appending(path: "descript.txt"))
    try Data("name,Legacy\ndllname,headline.dll\n".utf8).write(to: legacy.appending(path: "descript.txt"))

    let entries = try HeadlineCatalog().load(from: root)
    #expect(entries.count == 2)
    #expect(entries.contains { if case .rss = $0.kind { true } else { false } })
    #expect(entries.contains { if case .legacyDLL = $0.kind { true } else { false } })
}

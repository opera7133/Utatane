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
    try Data("name,Legacy\ncharset,UTF-8\ndllname,headline.dll\nopenurl,https://example.test/\nalwaysdisplay,1\n".utf8)
        .write(to: legacy.appending(path: "descript.txt"))

    let entries = try HeadlineCatalog().load(from: root)
    #expect(entries.count == 2)
    #expect(entries.contains {
        if case .rss = $0.kind {
            true
        } else {
            false
        }
    })
    #expect(entries.contains {
        if case .legacyDLL = $0.kind {
            true
        } else {
            false
        }
    })
    let legacyEntry = try #require(entries.first {
        if case .legacyDLL = $0.kind {
            true
        } else {
            false
        }
    })
    #expect(legacyEntry.charset == "UTF-8")
    #expect(legacyEntry.openURL?.absoluteString == "https://example.test/")
    #expect(legacyEntry.alwaysDisplay)
}

@Test func `a missing headline directory is an empty catalog`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: "Headline")

    #expect(try HeadlineCatalog().load(from: root).isEmpty)
}

import Foundation
import Testing
@testable import UtataneNetwork

@Test func `extracts configured elements links entities and differences without Wine`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString,
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("""
    parse.start,<main>
    parse.end,</main>
    element.start,<article>
    element.end,</article>
    headline.head,▼
    charset,UTF-8
    """.utf8).write(to: root.appending(path: "config.txt"))

    let headline = InstalledHeadline(
        id: root,
        name: "Test",
        siteURL: URL(string: "https://example.test/news/"),
        kind: .legacyDLL(fileName: "headline.dll")
    )
    let old = Data("""
    <main><article><a href="old">古い &amp; 記事</a></article></main>
    """.utf8)
    let new = Data("""
    <header>対象外</header><main>
      <article><a href="old">古い &amp; 記事</a></article>
      <article>
        <a href="new?id=1&amp;page=2">新しい&#32;記事</a>
      </article>
    </main><footer>対象外</footer>
    """.utf8)

    #expect(try ConfigHeadlineSensor().analyze(
        headline: headline,
        oldData: old,
        newData: new
    ) == [
        HeadlineSensorItem(
            title: "▼新しい 記事",
            url: "https://example.test/news/new?id=1&page=2"
        )
    ])
}

@Test func `installed recall config parses a downloaded fixture without Wine`() throws {
    guard let fixturePath = ProcessInfo.processInfo.environment["UTATANE_HEADLINE_FIXTURE"] else {
        return
    }
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let headlines = try HeadlineCatalog().load(
        from: repositoryRoot.appending(path: "Content/Local/Headline", directoryHint: .isDirectory)
    )
    guard let recall = headlines.first(where: { $0.id.lastPathComponent == "recall" }) else {
        return
    }
    let data = try Data(contentsOf: URL(filePath: fixturePath))
    let items = try ConfigHeadlineSensor().analyze(
        headline: recall,
        oldData: nil,
        newData: data
    )
    #expect(items.count == 15)
    #expect(items.allSatisfy { !$0.title.contains("繧") })
}

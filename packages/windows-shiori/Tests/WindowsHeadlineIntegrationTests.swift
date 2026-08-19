import Foundation
import Testing
import UtataneNetwork
@testable import UtataneWindowsShiori

@Test func `installed recall sensor parses a local HTML fixture through Wine`() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let winePath = environment["UTATANE_WINE_EXECUTABLE"],
          let prefixPath = environment["UTATANE_WINE_PREFIX"],
          let hostPath = environment["UTATANE_WINDOWS_DLL_HOST"],
          let fixturePath = environment["UTATANE_HEADLINE_FIXTURE"]
    else { return }

    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let headlines = try HeadlineCatalog().load(
        from: repositoryRoot.appending(path: "Content/Local/Headline", directoryHint: .isDirectory)
    )
    let recall = try #require(headlines.first { $0.id.lastPathComponent == "recall" })
    let result = try WindowsHeadlineSensor(configuration: .init(
        wineExecutableURL: URL(filePath: winePath),
        winePrefixURL: URL(filePath: prefixPath),
        hostExecutableURL: URL(filePath: hostPath)
    )).analyze(
        headline: recall,
        oldFileURL: nil,
        newFileURL: URL(filePath: fixturePath)
    )

    #expect(!result.items.isEmpty)
    #expect(result.items.allSatisfy { !$0.title.contains("繧") })
}

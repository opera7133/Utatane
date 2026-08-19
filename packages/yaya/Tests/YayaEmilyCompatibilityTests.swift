import Foundation
import Testing
@testable import UtataneYaya

@Test func `loads Emily dictionaries and evaluates OnBoot to SakuraScript`() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let masterDirectory = repositoryRoot
        .appendingPathComponent("Content/Local/Ghosts/emily4/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: masterDirectory.path) else { return }

    let configuration = try YayaConfigurationLoader().load(masterDirectory: masterDirectory)
    let program = try YayaProgramLoader().load(configuration: configuration)
    let saveFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("utatane-emily-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: saveFileURL) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let date = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 19,
        hour: 12
    )))
    let environment = YayaNativeRuntimeEnvironment(
        rootDirectory: configuration.rootDirectory,
        saveFileURL: saveFileURL,
        settings: configuration.settings.compactMapValues { $0.last }.mapValues(YayaValue.string),
        calendar: calendar,
        dateProvider: { date }
    )
    var evaluator = YayaEvaluator(
        program: program,
        globals: ["reference": .array(Array(repeating: .void, count: 8))],
        environment: environment,
        randomIndex: { _ in 0 }
    )

    _ = try evaluator.call("load", arguments: [.string(masterDirectory.path)])
    let result = try evaluator.call("OnBoot")

    guard case let .string(script) = result else {
        Issue.record("Emily OnBoot did not return a string")
        return
    }
    #expect(script.contains("\\h"))
    #expect(script.hasSuffix("\\e"))
}

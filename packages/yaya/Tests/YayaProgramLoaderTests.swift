import Foundation
import Testing
@testable import UtataneYaya

@Test func `program loader combines dictionaries and duplicate function choices`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let first = root.appendingPathComponent("first.dic")
    let second = root.appendingPathComponent("second.dic")
    try "Talk { 'first' }".write(to: first, atomically: true, encoding: .utf8)
    try "Talk { 'second' }\nOnBoot { Talk() }".write(to: second, atomically: true, encoding: .utf8)
    let configuration = YayaConfiguration(
        rootDirectory: root,
        dictionaries: [first, second].map {
            YayaDictionarySource(url: $0, encoding: .utf8, isOptional: false)
        },
        includedConfigurationURLs: [],
        settings: [:],
        diagnostics: []
    )

    let program = try YayaProgramLoader().load(configuration: configuration)
    var firstEvaluator = YayaEvaluator(program: program, randomIndex: { _ in 0 })
    var secondEvaluator = YayaEvaluator(program: program, randomIndex: { $0 - 1 })

    #expect(try firstEvaluator.call("OnBoot") == .string("first"))
    #expect(try secondEvaluator.call("OnBoot") == .string("second"))
}

import Foundation
import Testing
@testable import UtataneYaya

@Test func `auditor reports every incompatible dictionary without stopping at the first`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let valid = root.appendingPathComponent("valid.dic")
    let firstInvalid = root.appendingPathComponent("first-invalid.dic")
    let secondInvalid = root.appendingPathComponent("second-invalid.dic")
    try "OnBoot { 'hello' }".write(to: valid, atomically: true, encoding: .utf8)
    try "OnBoot { unknown syntax }".write(to: firstInvalid, atomically: true, encoding: .utf8)
    try "OnClose { if { 'missing condition' } }".write(to: secondInvalid, atomically: true, encoding: .utf8)

    let sources = [valid, firstInvalid, secondInvalid].map {
        YayaDictionarySource(url: $0, encoding: .utf8, isOptional: false)
    }
    let configuration = YayaConfiguration(
        rootDirectory: root,
        dictionaries: sources,
        includedConfigurationURLs: [],
        settings: [:],
        diagnostics: []
    )

    let report = YayaCompatibilityAuditor().audit(configuration: configuration)

    #expect(report.dictionaryCount == 3)
    #expect(report.parsedDictionaryCount == 1)
    #expect(report.issues.map(\.sourceURL.lastPathComponent).sorted() == [
        "first-invalid.dic", "second-invalid.dic"
    ])
}

@Test func `auditor expands local and cross dictionary global definitions`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let definitions = root.appendingPathComponent("definitions.dic")
    let usage = root.appendingPathComponent("usage.dic")
    try """
    #globaldefine {{START { case _argv[0] {
    #globaldefine }}END } }
    #define LOCAL_VALUE 2
    Local { switch LOCAL_VALUE { 'zero'; 'one'; 'two' } }
    """.write(to: definitions, atomically: true, encoding: .utf8)
    try """
    Event
    {{START
        when 0 { 'closed' }
        others 'unknown'
    }}END
    """.write(to: usage, atomically: true, encoding: .utf8)

    let configuration = YayaConfiguration(
        rootDirectory: root,
        dictionaries: [definitions, usage].map {
            YayaDictionarySource(url: $0, encoding: .utf8, isOptional: false)
        },
        includedConfigurationURLs: [],
        settings: [:],
        diagnostics: []
    )

    let report = YayaCompatibilityAuditor().audit(configuration: configuration)

    #expect(report.parsedDictionaryCount == 2)
    #expect(report.issues.isEmpty)
}

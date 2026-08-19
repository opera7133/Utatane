import Foundation
import Testing
@testable import UtataneYaya

@Test func `runtime auditor aggregates unsupported calls across every branch`() throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/runtime-audit.dic")
    let program = try YayaDictionaryParser.parse(source: """
    Later { 'implemented' }
    OnBoot {
        STRLEN('builtin')
        Later()
        if 1 { SYSTEMTIME() } else { SYSTEMTIME() }
        RANDOM_UNSUPPORTED()
    }
    """)

    let report = YayaRuntimeCompatibilityAuditor().audit(programs: [(sourceURL, program)])

    #expect(report.declaredFunctionCount == 2)
    #expect(report.functionCallCount == 5)
    #expect(report.unsupportedFunctions.map(\.name) == ["SYSTEMTIME", "RANDOM_UNSUPPORTED"])
    #expect(report.unsupportedFunctions[0].referenceCount == 2)
    #expect(report.unsupportedFunctions[0].locations.allSatisfy { $0.functionName == "OnBoot" })
}

@Test func `compatibility auditor includes runtime dependency results from all dictionaries`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let caller = root.appendingPathComponent("caller.dic")
    let callee = root.appendingPathComponent("callee.dic")
    try "OnBoot { DefinedLater(); NOT_IMPLEMENTED() }".write(to: caller, atomically: true, encoding: .utf8)
    try "DefinedLater { 'ok' }".write(to: callee, atomically: true, encoding: .utf8)
    let configuration = YayaConfiguration(
        rootDirectory: root,
        dictionaries: [caller, callee].map {
            YayaDictionarySource(url: $0, encoding: .utf8, isOptional: false)
        },
        includedConfigurationURLs: [],
        settings: [:],
        diagnostics: []
    )

    let report = YayaCompatibilityAuditor().audit(configuration: configuration)

    #expect(report.issues.isEmpty)
    #expect(report.runtime.unsupportedFunctions.map(\.name) == ["NOT_IMPLEMENTED"])
}

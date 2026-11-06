import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Test func `module dependency diagnosis stays visible when the SHIORI path cannot be resolved`() async {
    let target = SHIORIDiagnosticTarget(id: "/ghost", name: "probe", selectedFilename: "unknown.dll", macOSOverride: nil, moduleURL: nil,
                                        runtimeResult: "not started", moduleRequirementsReport: "SAORI httpc: catalog not checked")
    let report = await SHIORIModuleInspector.inspect(target)
    #expect(report.contains("SAORI httpc: catalog not checked"))
    #expect(report.contains("not started"))
    #expect(report.contains("No external module path resolved"))
}

@Test func `additional preflight inspection is refreshed even without a resolved module`() async {
    let target = SHIORIDiagnosticTarget(id: "/ghost", name: "DNProxy", selectedFilename: "shiori.dll", macOSOverride: nil,
                                        moduleURL: nil, runtimeResult: "not started", additionalInspection: { "DNProxy: module not installed" })
    let report = await SHIORIModuleInspector.inspect(target)
    #expect(report.contains("DNProxy: module not installed"))
    #expect(report.contains("No external module path resolved"))
}

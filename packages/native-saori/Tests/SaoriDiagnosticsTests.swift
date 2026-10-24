import Foundation
import Testing
import UtataneCore
@testable import UtataneNativeSaori

private final class DiagnosticModule: ExternalSaoriStatusReporting, @unchecked Sendable {
    func call(arguments: [String]) -> String {
        callReport(arguments: arguments).output
    }

    func callReport(arguments: [String]) -> NativeSaoriCallReport {
        .init(output: "secret-output", status: 503, responseBytes: 123)
    }
}

@Test func `ordinary SAORI diagnostics distinguish native Wine and unresolved calls without payloads`() {
    let store = AppLogStore(), diagnostics = SaoriDiagnostics(store: store)
    let root = URL(filePath: "/ghost/master")
    let module = DiagnosticModule()
    let registry = NativeSaoriRegistry(baseDirectoryURL: root, diagnostics: diagnostics, externalModuleFactory: { _, _, _ in module })
    registry.load("test.dylib")
    #expect(store.snapshot().isEmpty)
    diagnostics.isEnabled = true
    #expect(registry.call("test.dylib", arguments: ["secret-argument"]) == "secret-output")
    registry.unload("test.dylib")
    _ = registry.call("missing.dylib", arguments: [])
    let wine = NativeSaoriRegistry(baseDirectoryURL: root, diagnostics: diagnostics, prefersExternalWindowsDLL: true, externalModuleFactory: { _, _, _ in module })
    wine.load("test.dll")
    let entries = store.snapshot()
    #expect(entries.contains { $0.message.contains("backend=dylib status=503") })
    #expect(entries.contains { $0.message.contains("backend=Wine DLL status=1") })
    #expect(entries.contains { $0.message.contains("backend=unresolved status=0") })
    #expect(entries.allSatisfy { !$0.message.contains("secret-") && $0.category == "SAORI" })
}

@Test func `helper diagnostic frames accept bounded metadata and ignore malformed fields`() {
    let store = AppLogStore(), diagnostics = SaoriDiagnostics(store: store)
    let source = URL(filePath: "/ghost/master")
    var frame = Data()
    for (number, count) in [(UInt64(2), 4), (UInt64(200), 4), (UInt64(42), 8), (UInt64(123), 8)] {
        frame.append(contentsOf: (0 ..< count).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) })
    }
    frame.append(Data("/日本語/libecho.dylib".utf8))
    diagnostics.receive(frame, source: source)
    #expect(store.snapshot().isEmpty)
    diagnostics.isEnabled = true
    diagnostics.receive(frame, source: source)
    #expect(store.snapshot().last?.message.contains("status=200 elapsed_us=42 response_bytes=123") == true)
    #expect(store.snapshot().last?.message.contains("/日本語/libecho.dylib") == true)
    diagnostics.receive(Data(), source: source)
    diagnostics.receive(frame + Data(repeating: 0, count: 5000), source: source)
    var invalid = frame; invalid[0] = 99
    diagnostics.receive(invalid, source: source)
    #expect(store.snapshot().count == 1)
}

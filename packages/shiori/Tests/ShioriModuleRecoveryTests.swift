import Foundation
import Testing
import UtataneShiori

struct ShioriModuleRecoveryTests {
    private enum Failure: Error { case library, dictionary }
    private let bundled = URL(fileURLWithPath: "/ghost/bundled.dylib")
    private let installed = URL(fileURLWithPath: "/shared/module.dylib")

    @Test func `healthy bundled module does not load fallback`() throws {
        var attempts: [URL] = []
        let selected = try ShioriModuleRecovery.load(preferred: bundled, fallback: installed, canRecover: { _ in true }) {
            attempts.append($0)
            return $0
        }
        #expect(selected == bundled)
        #expect(attempts == [bundled])
    }

    @Test func `dictionary failure does not retry or touch another module`() {
        var attempts: [URL] = []
        #expect(throws: Failure.dictionary) {
            try ShioriModuleRecovery.load(preferred: bundled, fallback: installed, canRecover: {
                if case Failure.library = $0 {
                    return true
                }
                return false
            }) { url -> URL in
                attempts.append(url)
                throw Failure.dictionary
            }
        }
        #expect(attempts == [bundled])
    }

    @Test func `both failures remain in diagnostic`() {
        var attempts: [URL] = []
        do {
            let _: URL = try ShioriModuleRecovery.load(preferred: bundled, fallback: installed, canRecover: { _ in true }) {
                attempts.append($0)
                throw Failure.library
            }
            Issue.record("Expected both loads to fail")
        } catch {
            #expect(error.localizedDescription.contains(bundled.path))
            #expect(error.localizedDescription.contains(installed.path))
        }
        #expect(attempts == [bundled, installed])
    }
}

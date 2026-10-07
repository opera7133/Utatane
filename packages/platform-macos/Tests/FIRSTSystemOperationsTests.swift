import Testing
@testable import UtatanePlatformMacOS

@Test func `FIRST power operations use fixed scripts and cleanup uses no script`() {
    #expect(FIRSTSystemOperation.shutdown.appleScriptSource == "tell application \"System Events\" to shut down")
    #expect(FIRSTSystemOperation.restart.appleScriptSource == "tell application \"System Events\" to restart")
    #expect(FIRSTSystemOperation.clearRecentDocuments.appleScriptSource == nil)
    #expect(FIRSTSystemOperation.refreshMemory.appleScriptSource == nil)
    #expect(FIRSTSystemOperation(rawValue: "arbitrary") == nil)
}

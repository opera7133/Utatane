import Testing
@testable import UtatanePlatformMacOS

@Test
func `window level behavior resolves foreground state`() {
    #expect(GhostWindowLevelBehavior.always.staysOnTop(isTalking: false))
    #expect(GhostWindowLevelBehavior.always.staysOnTop(isTalking: true))
    #expect(!GhostWindowLevelBehavior.whileTalking.staysOnTop(isTalking: false))
    #expect(GhostWindowLevelBehavior.whileTalking.staysOnTop(isTalking: true))
    #expect(!GhostWindowLevelBehavior.normal.staysOnTop(isTalking: false))
    #expect(!GhostWindowLevelBehavior.normal.staysOnTop(isTalking: true))
}

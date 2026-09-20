import Testing
@testable import UtatanePlatformMacOS

@Test @MainActor func `sound completion distinguishes loop stop and error`() {
    #expect(SakuraScriptSoundPlayer.completionAction(isLooping: true, successfully: true) == .loop)
    #expect(SakuraScriptSoundPlayer.completionAction(isLooping: false, successfully: true) == .stop)
    #expect(SakuraScriptSoundPlayer.completionAction(isLooping: true, successfully: false) == .error)
}

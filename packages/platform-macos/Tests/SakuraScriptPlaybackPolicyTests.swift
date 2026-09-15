import Testing
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

@Test
func `external message policy keeps dialogue commands and rejects side effects`() {
    let allowed: [SakuraScriptToken] = [
        .scope(1),
        .surface(4),
        .text("受信した発話"),
        .lineBreak(scale: nil),
        .font(name: "bold", arguments: ["true"]),
        .wait(milliseconds: 250),
        .end
    ]
    let rejected: [SakuraScriptToken] = [
        .open("https://example.invalid"),
        .contentAction(.updateGhost),
        .raisedEvent(id: "OnDangerousEvent", arguments: []),
        .sound(.play(file: "/tmp/untrusted.wav", loop: false, options: [])),
        .moveSurface(x: 0, y: 0, time: 0, isAsync: false, options: []),
        .http(SakuraScriptHTTPRequest(
            method: "GET",
            url: "https://example.invalid",
            eventID: nil,
            waitsForCompletion: false
        )),
        .systemDialog(SakuraScriptSystemDialogCommand(kind: .open, id: "external"))
    ]

    #expect(filteredSakuraScriptTokens(allowed + rejected, policy: .externalMessage) == allowed)
    #expect(filteredSakuraScriptTokens(allowed + rejected, policy: .trusted) == allowed + rejected)
}

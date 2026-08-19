import Testing
import UtataneCore
@testable import UtataneShiori

@Test func `maps lifecycle events to shiori I ds`() {
    let adapter = GhostEventShioriAdapter()

    #expect(adapter.request(for: .boot).id == "OnBoot")
    #expect(adapter.request(for: .close).id == "OnClose")
    #expect(adapter.request(for: .randomTalk).id == "OnAITalk")

    let changing = adapter.request(for: .ghostChanging(name: "Emily"))
    #expect(changing.id == "OnGhostChanging")
    #expect(changing.reference(0) == "Emily")
}

@Test func `maps mouse context to canonical references`() {
    let request = GhostEventShioriAdapter().request(
        for: .mouseClick(scope: 1, region: "Head"),
        context: ShioriEventContext(scope: 2, mouseX: 120, mouseY: 80, mouseButton: 0)
    )

    #expect(request.id == "OnMouseClick")
    #expect(request.reference(0) == "120")
    #expect(request.reference(1) == "80")
    #expect(request.reference(3) == "1")
    #expect(request.reference(4) == "Head")
    #expect(request.reference(5) == "0")
}

@Test func `maps choice ID and arguments directly`() {
    let request = GhostEventShioriAdapter().request(
        for: .choice(id: "OnChoiceSelect_MAINMENU", arguments: ["one", "two"])
    )

    #expect(request.id == "OnChoiceSelect_MAINMENU")
    #expect(request.reference(0) == "one")
    #expect(request.reference(1) == "two")
    #expect(request.headers.entries.prefix(4).map(\.name) == ["Charset", "Sender", "SecurityLevel", "ID"])
}

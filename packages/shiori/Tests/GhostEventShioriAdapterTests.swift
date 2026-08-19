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

@Test func `maps native pointer events with coordinates and wheel delta`() {
    let adapter = GhostEventShioriAdapter()
    let move = adapter.request(for: .mouse(GhostMouseEvent(
        kind: .move,
        scope: 2,
        region: "Head",
        x: 44,
        y: 55
    )))

    #expect(move.id == "OnMouseMove")
    #expect(move.reference(0) == "44")
    #expect(move.reference(1) == "55")
    #expect(move.reference(3) == "2")
    #expect(move.reference(4) == "Head")
    #expect(move.reference(5) == "0")

    let wheel = adapter.request(for: .mouse(GhostMouseEvent(
        kind: .wheel(delta: -3),
        scope: 0,
        region: "Face",
        x: 10,
        y: 20
    )))
    #expect(wheel.id == "OnMouseWheel")
    #expect(wheel.reference(2) == "-3")
}

@Test func `maps double click separately from click`() {
    let request = GhostEventShioriAdapter().request(for: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 1,
        region: "Bust",
        x: 30,
        y: 40
    )))

    #expect(request.id == "OnMouseDoubleClick")
    #expect(request.reference(3) == "1")
    #expect(request.reference(4) == "Bust")
}

@Test func `maps a baseware event directly to SHIORI`() {
    let request = GhostEventShioriAdapter().request(for: .shiori(
        id: "OnInstallCompleteEx",
        references: [0: "ghost", 1: "Emily", 2: "emily4"]
    ))

    #expect(request.id == "OnInstallCompleteEx")
    #expect(request.reference(0) == "ghost")
    #expect(request.reference(1) == "Emily")
    #expect(request.reference(2) == "emily4")
}

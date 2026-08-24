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

@Test func `maps a named SakuraScript choice directly`() {
    let request = GhostEventShioriAdapter().request(
        for: .choice(id: "OnChoiceSelect_MAINMENU", arguments: ["one", "two"])
    )

    #expect(request.id == "OnChoiceSelect_MAINMENU")
    #expect(request.reference(0) == "one")
    #expect(request.reference(1) == "two")
    #expect(request.headers.entries.prefix(4).map(\.name) == ["Charset", "Sender", "SecurityLevel", "ID"])
}

@Test func `maps a plain choice through OnChoiceSelect`() {
    let request = GhostEventShioriAdapter().request(
        for: .choice(id: "ランダムトーク", arguments: ["one", "two"])
    )

    #expect(request.id == "OnChoiceSelect")
    #expect(request.reference(0) == "ランダムトーク")
    #expect(request.reference(1) == "one")
    #expect(request.reference(2) == "two")
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

@Test func `maps mouse boundary events with SSP input references`() {
    let adapter = GhostEventShioriAdapter()
    let cases: [(GhostMouseEvent.Kind, String)] = [
        (.enterAll, "OnMouseEnterAll"),
        (.leaveAll, "OnMouseLeaveAll"),
        (.enter, "OnMouseEnter"),
        (.leave, "OnMouseLeave")
    ]

    for (kind, eventID) in cases {
        let request = adapter.request(for: .mouse(GhostMouseEvent(
            kind: kind,
            scope: 1,
            region: "Head",
            x: 12,
            y: 34
        )))
        #expect(request.id == eventID)
        #expect(request.reference(0) == "12")
        #expect(request.reference(1) == "34")
        #expect(request.reference(2) == "0")
        #expect(request.reference(3) == "1")
        #expect(request.reference(4) == "Head")
        #expect(request.reference(5) == "0")
        #expect(request.reference(6) == "mouse")
    }
}

@Test func `maps mouse button drag and hover event families`() {
    let adapter = GhostEventShioriAdapter()
    let cases: [(GhostMouseEvent.Kind, Int, String)] = [
        (.down, 0, "OnMouseDown"),
        (.down, 2, "OnMouseDownEx"),
        (.up, 0, "OnMouseUp"),
        (.up, 2, "OnMouseUpEx"),
        (.click, 2, "OnMouseClickEx"),
        (.doubleClick, 2, "OnMouseDoubleClickEx"),
        (.multipleClick(count: 3), 0, "OnMouseMultipleClick"),
        (.multipleClick(count: 4), 3, "OnMouseMultipleClickEx"),
        (.dragStart, 0, "OnMouseDragStart"),
        (.dragEnd, 0, "OnMouseDragEnd"),
        (.hover, 0, "OnMouseHover")
    ]

    for (kind, button, eventID) in cases {
        let request = adapter.request(for: .mouse(.init(
            kind: kind,
            scope: 0,
            region: "Bust",
            x: 20,
            y: 30,
            button: button
        )))
        #expect(request.id == eventID)
        #expect(request.reference(2) == "0")
        #expect(request.reference(6) == "mouse")
    }

    let middleClick = adapter.request(for: .mouse(.init(
        kind: .click,
        scope: 0,
        region: nil,
        x: 0,
        y: 0,
        button: 2
    )))
    #expect(middleClick.reference(5) == "middle")

    let multipleClick = adapter.request(for: .mouse(.init(
        kind: .multipleClick(count: 4),
        scope: 0,
        region: nil,
        x: 0,
        y: 0
    )))
    #expect(multipleClick.reference(7) == "4")
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

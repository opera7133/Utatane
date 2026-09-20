import Testing
import UtataneCore
@testable import UtataneRuntime

@Suite(.serialized)
struct MouseEventResponseCoordinatorTests {
    @Test
    @MainActor
    func `mouse up response suppresses the following click`() async {
        for (button, upID) in [(0, "OnMouseUp"), (2, "OnMouseUpEx")] {
            let coordinator = MouseEventResponseCoordinator()
            let recorder = MouseRequestRecorder(responses: [upID: PersonalityResponse(script: nil)])

            coordinator.submit(mouse(.up, button: button), request: recorder.request, receive: recorder.receive)
            coordinator.submit(mouse(.click, button: button), request: recorder.request, receive: recorder.receive)
            await recorder.waitForRequestCount(1)

            #expect(recorder.requestIDs == [upID])
            #expect(recorder.receivedCount == 1)
        }
    }

    @Test
    @MainActor
    func `unhandled mouse up falls through to click`() async {
        let coordinator = MouseEventResponseCoordinator()
        let recorder = MouseRequestRecorder(responses: ["OnMouseClick": PersonalityResponse(script: nil)])

        coordinator.submit(mouse(.up), request: recorder.request, receive: recorder.receive)
        coordinator.submit(mouse(.click), request: recorder.request, receive: recorder.receive)
        await recorder.waitForRequestCount(2)

        #expect(recorder.requestIDs == ["OnMouseUp", "OnMouseClick"])
        #expect(recorder.receivedCount == 1)
    }

    @Test
    @MainActor
    func `mouse up response does not suppress double click`() async {
        let coordinator = MouseEventResponseCoordinator()
        let recorder = MouseRequestRecorder(responses: [
            "OnMouseUp": PersonalityResponse(script: nil),
            "OnMouseDoubleClick": PersonalityResponse(script: nil)
        ])

        coordinator.submit(mouse(.up), request: recorder.request, receive: recorder.receive)
        coordinator.submit(mouse(.doubleClick), request: recorder.request, receive: recorder.receive)
        await recorder.waitForRequestCount(2)

        #expect(recorder.requestIDs == ["OnMouseUp", "OnMouseDoubleClick"])
        #expect(recorder.receivedCount == 2)
    }

    @Test
    @MainActor
    func `unhandled multiple click returns to the ordinary click sequence`() async {
        let cases = [
            (3, 0, "OnMouseMultipleClick", "OnMouseClick"),
            (4, 0, "OnMouseMultipleClick", "OnMouseDoubleClick"),
            (3, 2, "OnMouseMultipleClickEx", "OnMouseClickEx"),
            (4, 2, "OnMouseMultipleClickEx", "OnMouseDoubleClickEx")
        ]
        for (count, button, multipleID, fallbackID) in cases {
            let coordinator = MouseEventResponseCoordinator()
            let recorder = MouseRequestRecorder(responses: [fallbackID: PersonalityResponse(script: nil)])

            coordinator.submit(mouse(.up, button: button), request: recorder.request, receive: recorder.receive)
            coordinator.submit(
                mouse(.multipleClick(count: count), button: button),
                request: recorder.request,
                receive: recorder.receive
            )
            await recorder.waitForRequestCount(3)

            let upID = button <= 1 ? "OnMouseUp" : "OnMouseUpEx"
            #expect(recorder.requestIDs == [upID, multipleID, fallbackID])
            #expect(recorder.receivedCount == 1)
        }
    }

    @Test
    @MainActor
    func `handled mouse up only suppresses an odd multiple click fallback`() async {
        let cases = [
            (3, ["OnMouseUp", "OnMouseMultipleClick"]),
            (4, ["OnMouseUp", "OnMouseMultipleClick", "OnMouseDoubleClick"])
        ]
        for (count, expectedIDs) in cases {
            let coordinator = MouseEventResponseCoordinator()
            let recorder = MouseRequestRecorder(responses: [
                "OnMouseUp": PersonalityResponse(script: nil),
                "OnMouseDoubleClick": PersonalityResponse(script: nil)
            ])

            coordinator.submit(mouse(.up), request: recorder.request, receive: recorder.receive)
            coordinator.submit(
                mouse(.multipleClick(count: count)),
                request: recorder.request,
                receive: recorder.receive
            )
            await recorder.waitForRequestCount(expectedIDs.count)

            #expect(recorder.requestIDs == expectedIDs)
            #expect(recorder.receivedCount == (count.isMultiple(of: 2) ? 2 : 1))
        }
    }

    private func mouse(_ kind: GhostMouseEvent.Kind, button: Int = 0) -> GhostMouseEvent {
        GhostMouseEvent(kind: kind, scope: 0, region: "Bust", x: 10, y: 20, button: button)
    }
}

@MainActor
private final class MouseRequestRecorder {
    private let responses: [String: PersonalityResponse]
    private(set) var requestIDs: [String] = []
    private(set) var receivedCount = 0

    init(responses: [String: PersonalityResponse]) {
        self.responses = responses
    }

    func request(_ event: GhostEvent) async -> PersonalityResponse? {
        let id = eventID(event)
        requestIDs.append(id)
        return responses[id]
    }

    func receive(_: PersonalityResponse) {
        receivedCount += 1
    }

    func waitForRequestCount(_ count: Int) async {
        while requestIDs.count < count {
            await Task.yield()
        }
    }

    private func eventID(_ event: GhostEvent) -> String {
        guard case let .mouse(mouseEvent) = event else { return "" }
        let suffix = mouseEvent.button <= 1 ? "" : "Ex"
        return switch mouseEvent.kind {
        case .up: "OnMouseUp\(suffix)"
        case .click: "OnMouseClick\(suffix)"
        case .doubleClick: "OnMouseDoubleClick\(suffix)"
        case .multipleClick: "OnMouseMultipleClick\(suffix)"
        default: "Other"
        }
    }
}

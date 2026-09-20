import Testing
import UtataneCore
@testable import UtatanePlatformMacOS

@Test func `mouse gesture maps eight directions from right counterclockwise`() {
    let vectors = [
        (10, 0, 0, "right"),
        (10, 10, 45, "right_up"),
        (0, 10, 90, "up"),
        (-10, 10, 135, "left_up"),
        (-10, 0, 180, "left"),
        (-10, -10, 225, "left_down"),
        (0, -10, 270, "down"),
        (10, -10, 315, "right_down")
    ]
    for (deltaX, deltaY, angle, direction) in vectors {
        let actualAngle = SurfaceMouseGesturePolicy.angle(deltaX: deltaX, deltaY: deltaY)
        #expect(actualAngle == angle)
        #expect(SurfaceMouseGesturePolicy.direction(angle: actualAngle) == direction)
    }
}

@Test func `mouse gesture builds SSP references`() {
    let event = GhostMouseGestureEvent(
        scope: 1,
        x: 32,
        y: 48,
        region: "Bust",
        startX: 12,
        startY: 18,
        startRegion: "Head",
        direction: "right_down",
        angle: 315
    )
    #expect(event.references == [
        0: "1",
        1: "32\u{01}48",
        2: "Bust",
        3: "12\u{01}18",
        4: "Head",
        5: "right_down",
        6: "315"
    ])
}

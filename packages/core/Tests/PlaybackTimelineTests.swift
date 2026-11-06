import Testing
@testable import UtataneCore

@Test func `frame deadlines absorb rendering and wakeup overhead without accumulating drift`() {
    var timeline = PlaybackTimeline(startedAt: .zero)
    var now = Duration.zero
    for frame in 1 ... 1000 {
        now += .milliseconds(3) // rendering
        let deadline = timeline.advance(by: .milliseconds(20), now: now)
        #expect(deadline == .milliseconds(frame * 20))
        now = deadline + .milliseconds(2) // timer overshoot
    }
}

@Test func `overdue frames discard timing debt after slow rendering or machine sleep`() {
    var timeline = PlaybackTimeline(startedAt: .zero)
    #expect(timeline.advance(by: .milliseconds(20), now: .milliseconds(35)) == .milliseconds(35))
    #expect(timeline.advance(by: .milliseconds(20), now: .milliseconds(40)) == .milliseconds(55))
    #expect(timeline.advance(by: .milliseconds(20), now: .seconds(86400)) == .seconds(86400))
    #expect(timeline.advance(by: .milliseconds(20), now: .seconds(86400)) == .seconds(86400) + .milliseconds(20))
}

@Test func `frame timeline accepts variable intervals and never schedules negative delays`() {
    var timeline = PlaybackTimeline(startedAt: .seconds(10))
    #expect(timeline.advance(by: .milliseconds(10), now: .seconds(10)) == .seconds(10) + .milliseconds(10))
    #expect(timeline.advance(by: .milliseconds(40), now: .seconds(10)) == .seconds(10) + .milliseconds(50))
    #expect(timeline.advance(by: .milliseconds(-1), now: .seconds(10)) == .seconds(10) + .milliseconds(50))
}

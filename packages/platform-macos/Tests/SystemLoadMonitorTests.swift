import Testing
@testable import UtatanePlatformMacOS

@Test func `load transitions require sustained high values and use a lower recovery threshold`() {
    var detector = SystemLoadTransitionDetector()

    #expect(detector.consume(.init(cpu: 80, memory: 81)) == .init())
    #expect(detector.consume(.init(cpu: 85, memory: 90)) == .init())
    let high = detector.consume(.init(cpu: 90, memory: 95))
    #expect(high.cpuBecameHigh)
    #expect(high.memoryBecameHigh)

    #expect(detector.consume(.init(cpu: 70, memory: 60)) == .init())
    let low = detector.consume(.init(cpu: 59, memory: 40))
    #expect(low.cpuBecameLow)
    #expect(low.memoryBecameLow)
}

@Test func `a broken high streak does not trigger an event`() {
    var detector = SystemLoadTransitionDetector()
    _ = detector.consume(.init(cpu: 90, memory: 10))
    _ = detector.consume(.init(cpu: 70, memory: 10))
    _ = detector.consume(.init(cpu: 90, memory: 10))
    let result = detector.consume(.init(cpu: 90, memory: 10))
    #expect(!result.cpuBecameHigh)
}

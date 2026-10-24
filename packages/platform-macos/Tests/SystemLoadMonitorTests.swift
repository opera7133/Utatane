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

@Test func `available memory and usage share one physical memory measurement`() throws {
    let memory = try #require(SystemMemoryUsage(totalBytes: 100 * 4096, activePages: 30, wiredPages: 10, compressedPages: 20, pageSize: 4096))
    #expect(memory.load == 60)
    #expect(memory.availableBytes == 40 * 4096)
    #expect(SystemMemoryUsage(totalBytes: 0, activePages: 0, wiredPages: 0, compressedPages: 0, pageSize: 4096) == nil)
    let full = try #require(SystemMemoryUsage(totalBytes: 4096, activePages: 2, wiredPages: 0, compressedPages: 0, pageSize: 4096))
    #expect(full.load == 100 && full.availableBytes == 0)
}

import Foundation
import Testing
@testable import UtatanePlatformMacOS

@MainActor
@Test func `identical HTTP URLs retain independent requests and selective cancellation`() async throws {
    let tracker = HTTPRequestTracker()
    let first = HTTPGate(), second = HTTPGate(), other = HTTPGate(), replacement = HTTPGate()
    var leases: [HTTPRequestTracker.Lease] = []
    let a = tracker.start(url: "same") { lease in leases.append(lease); await first.wait(); return 1 }
    let b = tracker.start(url: "same") { lease in leases.append(lease); await second.wait(); return 2 }
    let c = tracker.start(url: "other") { lease in leases.append(lease); await other.wait(); return 3 }
    try await requireEventually { leases.count == 3 }
    #expect(Set(leases.map(\.id)).count == 3)
    let allActive = leases.allSatisfy(\.isActive)
    #expect(allActive)
    first.release()
    #expect(await a.value == 1)
    #expect(tracker.count == 2)
    let d = tracker.start(url: "same") { lease in leases.append(lease); await replacement.wait(); return 4 }
    try await requireEventually { leases.count == 4 }
    tracker.cancel(url: "same")
    #expect(!leases[1].isActive && leases[1].mayReportFailure)
    #expect(leases[2].isActive)
    #expect(!leases[3].isActive)
    second.release()
    #expect(await b.value == 2)
    #expect(tracker.count == 2) // The newer same-URL task was not removed.
    tracker.cancel(reportFailure: false)
    #expect(!leases[2].mayReportFailure && !leases[3].mayReportFailure)
    other.release(); replacement.release()
    #expect(await c.value == 3)
    #expect(await d.value == 4)
    #expect(tracker.count == 0)
    #expect(leases.allSatisfy { !$0.mayReportFailure })
}

@MainActor
private final class HTTPGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume(); continuation = nil
    }
}

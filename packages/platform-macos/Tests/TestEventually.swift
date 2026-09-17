import Foundation
import Testing

/// Waits for asynchronous test state without assuming that a loaded CI host
/// will schedule the producing task within a fixed sleep interval.
@MainActor
func requireEventually(
    timeout: Duration = .seconds(30),
    pollInterval: Duration = .milliseconds(10),
    file: StaticString = #fileID,
    line: UInt = #line,
    _ condition: @MainActor () throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while try !condition(), clock.now < deadline {
        try await Task.sleep(for: pollInterval)
    }
    if try !condition() {
        Issue.record("Condition was not satisfied before the timeout at \(file):\(line)")
    }
}

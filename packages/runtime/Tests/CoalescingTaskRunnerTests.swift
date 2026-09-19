import Testing
@testable import UtataneRuntime

@Suite(.serialized)
struct CoalescingTaskRunnerTests {
    @Test
    @MainActor
    func `duplicate submission is dropped until the operation finishes`() async {
        let runner = CoalescingTaskRunner()
        let operation = SuspendedOperation()

        #expect(runner.submit {
            await operation.run()
        })
        await operation.waitUntilStarted()
        #expect(runner.isRunning)
        #expect(!runner.submit {})

        operation.resume()
        await waitUntil { !runner.isRunning }

        #expect(runner.submit {})
        await waitUntil { !runner.isRunning }
    }

    @Test
    @MainActor
    func `cancelled operation cannot clear a replacement operation`() async {
        let runner = CoalescingTaskRunner()
        let first = SuspendedOperation()
        let replacement = SuspendedOperation()

        #expect(runner.submit { await first.run() })
        await first.waitUntilStarted()
        runner.cancel()
        #expect(runner.submit { await replacement.run() })
        await replacement.waitUntilStarted()

        first.resume()
        await Task.yield()
        #expect(runner.isRunning)

        replacement.resume()
        await waitUntil { !runner.isRunning }
    }
}

@MainActor
private final class SuspendedOperation {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    func run() async {
        hasStarted = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        await waitUntil { hasStarted }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func waitUntil(_ predicate: () -> Bool) async {
    while !predicate() {
        await Task.yield()
    }
}

// Compare legacy post-render sleeps with the production active-time timeline.
// Synthetic 2ms MainActor work per frame; no AppKit or real ghost rendering.
import Darwin
import Foundation

@main
struct BenchmarkPlaybackTiming {
    @MainActor static func main() async throws {
        let streams = Int(CommandLine.arguments[1])!
        let milliseconds = Int(CommandLine.arguments[2])!
        let frames = 30
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        let jobs = (0 ..< streams).map { _ in
            Task { @MainActor in
                let clock = SuspensionClock()
                let start = ContinuousClock.now
                var timeline = PlaybackTimeline(startedAt: clock.elapsed)
                var worst = 0.0
                var checksum = 0.0
                var waitCalls = 0
                for frame in 1 ... frames {
                    let workEnd = ContinuousClock.now + .milliseconds(2)
                    while ContinuousClock.now < workEnd {
                        checksum += 1
                    }
                    #if BASELINE
                        // Original waitForAnimationFrame: render, then wait in 20ms slices.
                        var remaining = milliseconds
                        while remaining > 0 {
                            let interval = min(remaining, 20)
                            guard await clock.sleep(for: .milliseconds(interval)) else { return (0.0, 0.0, 0) }
                            remaining -= interval
                            waitCalls += 1
                        }
                    #else
                        let deadline = timeline.advance(by: .milliseconds(milliseconds), now: clock.elapsed)
                        guard await clock.sleep(until: deadline) else { return (0.0, 0.0, 0) }
                        waitCalls += 1
                    #endif
                    let drift = (start.duration(to: .now) - .milliseconds(frame * milliseconds)).components
                    worst = max(worst, Double(drift.seconds) * 1000 + Double(drift.attoseconds) / 1e15)
                }
                clock.finish()
                return (worst, checksum, waitCalls)
            }
        }
        var drift = 0.0, checksum = 0.0
        var waitCalls = 0
        for job in jobs {
            let result = await job.value
            drift = max(drift, result.0)
            checksum += result.1
            waitCalls += result.2
        }
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        func cpu(_ usage: rusage) -> Double {
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        let result: [String: Any] = ["streams": streams, "intervalMilliseconds": milliseconds, "framesPerStream": frames,
                                     "maximumDriftMilliseconds": drift, "cpuSeconds": cpu(after) - cpu(before),
                                     "waitCalls": waitCalls, "workIterations": checksum]
        try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }
}

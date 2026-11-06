// Used by benchmark-shell-load.py with identical before/after shell targets.
import Foundation
#if BASELINE
    import BeforeShell
#else
    import AfterShell
#endif

@main
struct BenchmarkShellLoad {
    static func main() throws {
        let directory = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let iterations = 10
        let loader = ShellLoader()
        _ = try loader.load(from: directory)
        let initialCount = ShellDirectoryBenchmarkMetrics.enumerationCount
        let started = ContinuousClock.now
        var checksum = 0
        for _ in 0 ..< iterations {
            let shell = try loader.load(from: directory)
            checksum += shell.surfaces.count + shell.surfaceAliases.count + shell.bindGroups.count
        }
        let duration = started.duration(to: .now).components
        let result: [String: Any] = ["iterations": iterations, "checksum": checksum,
                                     "directoryEnumerations": ShellDirectoryBenchmarkMetrics.enumerationCount - initialCount,
                                     "loadSeconds": Double(duration.seconds) + Double(duration.attoseconds) / 1e18]
        try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }
}

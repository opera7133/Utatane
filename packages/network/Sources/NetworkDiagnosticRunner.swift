import Foundation

public struct NetworkDiagnosticResult: Sendable {
    public let output: String
    public let succeeded: Bool
}

public enum NetworkDiagnosticRunner {
    public static func ping(
        host: String,
        count: Int,
        size: Int,
        timeoutMilliseconds: Int,
        ttl: Int?
    ) async -> NetworkDiagnosticResult {
        await run(
            executable: "/sbin/ping",
            arguments: ["-n", "-c", String(max(1, min(count, 20))), "-s", String(max(0, min(size, 65507))),
                        "-W", String(max(1, timeoutMilliseconds))]
                + (ttl.map { ["-m", String(max(1, min($0, 255)))] } ?? [])
                + [host]
        )
    }

    public static func nslookup(host: String) async -> NetworkDiagnosticResult {
        let reverse = host.contains(":") || host.split(separator: ".").count == 4
        return await run(
            executable: "/usr/bin/dscacheutil",
            arguments: ["-q", "host", "-a", reverse ? "ip_address" : "name", host]
        )
    }

    private static func run(executable: String, arguments: [String]) async -> NetworkDiagnosticResult {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return NetworkDiagnosticResult(
                    output: String(data: data, encoding: .utf8) ?? "",
                    succeeded: process.terminationStatus == 0
                )
            } catch {
                return NetworkDiagnosticResult(output: error.localizedDescription, succeeded: false)
            }
        }.value
    }
}

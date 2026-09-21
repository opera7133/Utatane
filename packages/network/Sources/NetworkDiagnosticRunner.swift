import Foundation

public struct NetworkDiagnosticResult: Sendable {
    public let output: String
    public let succeeded: Bool
}

public struct NetworkPingProgress: Sendable, Equatable {
    public let address: String
    public let sequence: Int
    public let roundTripMilliseconds: String

    public init(address: String, sequence: Int, roundTripMilliseconds: String) {
        self.address = address
        self.sequence = sequence
        self.roundTripMilliseconds = roundTripMilliseconds
    }
}

public enum NetworkDiagnosticRunner {
    public static func ping(
        host: String,
        count: Int,
        size: Int,
        timeoutMilliseconds: Int,
        ttl: Int?,
        dontFragment: Bool = false,
        data: String? = nil,
        progress: (@Sendable (NetworkPingProgress) async -> Void)? = nil
    ) async -> NetworkDiagnosticResult {
        await run(
            executable: "/sbin/ping",
            arguments: pingArguments(
                host: host,
                count: count,
                size: size,
                timeoutMilliseconds: timeoutMilliseconds,
                ttl: ttl,
                dontFragment: dontFragment,
                data: data
            ),
            lineHandler: { line in
                guard let value = pingProgress(from: line) else { return }
                await progress?(value)
            }
        )
    }

    static func pingArguments(
        host: String,
        count: Int,
        size: Int,
        timeoutMilliseconds: Int,
        ttl: Int?,
        dontFragment: Bool,
        data: String?
    ) -> [String] {
        let payloadSize = data.map { Data($0.utf8).count }
        var arguments = [
            "-n", "-c", String(max(1, min(count, 20))),
            "-s", String(max(0, min(payloadSize ?? size, 65507))),
            "-W", String(max(1, timeoutMilliseconds))
        ]
        if let ttl {
            arguments += ["-m", String(max(1, min(ttl, 255)))]
        }
        if dontFragment {
            arguments.append("-D")
        }
        if let data, !data.isEmpty {
            let pattern = Data(data.utf8.prefix(16)).map { String(format: "%02x", $0) }.joined()
            if !pattern.isEmpty {
                arguments += ["-p", pattern]
            }
        }
        arguments.append(host)
        return arguments
    }

    public static func nslookup(host: String) async -> NetworkDiagnosticResult {
        let reverse = host.contains(":") || host.split(separator: ".").count == 4
        return await run(
            executable: "/usr/bin/dscacheutil",
            arguments: ["-q", "host", "-a", reverse ? "ip_address" : "name", host]
        )
    }

    private static func run(
        executable: String,
        arguments: [String],
        lineHandler: (@Sendable (String) async -> Void)? = nil
    ) async -> NetworkDiagnosticResult {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                var lines: [String] = []
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    lines.append(line)
                    await lineHandler?(line)
                }
                process.waitUntilExit()
                return NetworkDiagnosticResult(
                    output: lines.joined(separator: "\n"),
                    succeeded: process.terminationStatus == 0
                )
            } catch {
                return NetworkDiagnosticResult(output: error.localizedDescription, succeeded: false)
            }
        }.value
    }

    private static func pingProgress(from line: String) -> NetworkPingProgress? {
        guard line.contains("bytes from "),
              let fromRange = line.range(of: "from "),
              let addressEnd = line[fromRange.upperBound...].firstIndex(of: ":")
        else { return nil }
        let address = String(line[fromRange.upperBound ..< addressEnd])
        let fields = line.split(whereSeparator: { $0 == " " })
        let sequence = fields.first(where: { $0.hasPrefix("icmp_seq=") })
            .flatMap { Int($0.dropFirst("icmp_seq=".count)) } ?? 0
        let roundTrip = fields.first(where: { $0.hasPrefix("time=") })
            .map { String($0.dropFirst("time=".count)) } ?? ""
        return NetworkPingProgress(address: address, sequence: sequence, roundTripMilliseconds: roundTrip)
    }
}

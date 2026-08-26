import Foundation

public struct WindowsPluginDLLProcessConfiguration: Sendable, Equatable {
    public let wineExecutableURL: URL
    public let winePrefixURL: URL
    public let hostExecutableURL: URL
    public let dllURL: URL
    public var environment: [String: String]

    public init(
        wineExecutableURL: URL,
        winePrefixURL: URL,
        hostExecutableURL: URL,
        dllURL: URL,
        environment: [String: String] = [:]
    ) {
        self.wineExecutableURL = wineExecutableURL
        self.winePrefixURL = winePrefixURL
        self.hostExecutableURL = hostExecutableURL
        self.dllURL = dllURL
        self.environment = environment
    }
}

/// Runs a conventional load/request/unload Windows DLL through the generic Wine host.
public final class WindowsPluginDLLProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var isClosed = false

    public init(configuration: WindowsPluginDLLProcessConfiguration) throws {
        for url in [
            configuration.wineExecutableURL,
            configuration.hostExecutableURL,
            configuration.dllURL
        ] where !FileManager.default.fileExists(atPath: url.path) {
            throw WindowsShioriProcessError.missingFile(url)
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = configuration.wineExecutableURL
        process.arguments = Self.processArguments(configuration: configuration)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment.merge(configuration.environment) { _, override in override }
        environment["WINEPREFIX"] = configuration.winePrefixURL.path
        environment["WINEDEBUG"] = "-all"
        environment["WINEMSYNC"] = "1"
        environment["WINEESYNC"] = "1"
        process.environment = environment
        try process.run()

        let input = inputPipe.fileHandleForWriting
        let output = outputPipe.fileHandleForReading
        do {
            let readyLength = try WindowsShioriFrameCodec.decodeLength(
                Self.readExact(count: MemoryLayout<UInt32>.size, from: output),
                allowsReadyFrame: true
            )
            guard readyLength == 0 else {
                throw WindowsShioriProcessError.invalidHostReadyFrame(readyLength)
            }
        } catch {
            try? input.close()
            try? output.close()
            if process.isRunning {
                process.terminate()
            }
            throw error
        }

        self.process = process
        self.input = input
        self.output = output
    }

    deinit {
        close()
    }

    public func close() {
        lock.withLock {
            guard !isClosed else { return }
            isClosed = true
            try? input.close()
            try? output.close()
            if process.isRunning {
                process.terminate()
            }
        }
    }

    public func request(_ request: String) throws -> String {
        try lock.withLock {
            guard !isClosed else { throw WindowsShioriProcessError.processEnded }
            guard let payload = request.data(using: .shiftJIS) else {
                throw WindowsShioriProcessError.requestEncodingFailed
            }
            try input.write(contentsOf: WindowsShioriFrameCodec.encode(payload))
            let length = try WindowsShioriFrameCodec.decodeLength(
                Self.readExact(count: MemoryLayout<UInt32>.size, from: output)
            )
            let response = try Self.readExact(count: length, from: output)
            if let text = String(data: response, encoding: .shiftJIS) {
                return text
            }
            if let text = String(data: response, encoding: .utf8) {
                return text
            }
            throw WindowsShioriProcessError.responseDecodingFailed
        }
    }

    public static func processArguments(configuration: WindowsPluginDLLProcessConfiguration) -> [String] {
        [
            configuration.hostExecutableURL.path,
            WindowsShioriProcessSession.windowsPath(for: configuration.dllURL)
        ]
    }

    private static func readExact(count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw WindowsShioriProcessError.processEnded
            }
            result.append(chunk)
        }
        return result
    }
}

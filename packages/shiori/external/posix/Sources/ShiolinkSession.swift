import Darwin
import Foundation

/// All process/pipe state is confined to a dedicated serial queue. Blocking pipe work never runs on the UI actor.
public final class ShiolinkSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.utatane.shiolink")
    private let configuration: ShiolinkConfiguration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence: UInt64 = 0
    private var closed = false
    private static let maximumFrame = 8 * 1024 * 1024

    public init(configuration: ShiolinkConfiguration) {
        self.configuration = configuration
    }

    deinit {
        let process = process
        let input = input
        let output = output
        queue.async { Self.dispose(process: process, input: input, output: output, gracefully: true) }
    }

    public func request(_ request: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { try continuation.resume(returning: self.exchange(request)) } catch {
                    self.stop(gracefully: false)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stop(gracefully: true)
                continuation.resume()
            }
        }
    }

    private func start(deadline: TimeInterval) throws {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: configuration.executable.path) else {
            throw ShiolinkError.configuration("executable not found or not executable")
        }
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = configuration.executable
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.directory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        // Inherit stderr, not stdout: diagnostics cannot fill a second undrained pipe.
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        try? inputPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForWriting.close()
        for handle in [input!, output!] {
            let fd = handle.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
                throw ShiolinkError.protocolFailure("cannot configure pipe")
            }
        }
        guard fcntl(input!.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ShiolinkError.protocolFailure("cannot configure pipe signals")
        }
        let path = configuration.directory.path + "/"
        guard !path.contains("\r"), !path.contains("\n") else {
            throw ShiolinkError.configuration("invalid master path")
        }
        try write("*L:\(path)\r\n", deadline: deadline)
    }

    private func exchange(_ request: String) throws -> String {
        guard !closed else { throw ShiolinkError.closed }
        let deadline = ProcessInfo.processInfo.systemUptime + configuration.timeout
        try start(deadline: deadline)
        sequence &+= 1
        let marker = "*S:\(sequence)"
        guard request.hasSuffix("\r\n\r\n") else {
            throw ShiolinkError.protocolFailure("request must end with CRLF CRLF")
        }
        // SHIOLINK synchronizes before sending the request body.
        try write(marker + "\r\n", deadline: deadline)
        guard try readLine(deadline: deadline) == marker else {
            throw ShiolinkError.protocolFailure("transaction ID mismatch (stdout must contain only protocol data)")
        }
        try write(request, deadline: deadline)
        var response = ""
        var size = 0
        while true {
            let line = try readLine(deadline: deadline)
            size += line.utf8.count + 2
            guard size <= Self.maximumFrame else { throw ShiolinkError.protocolFailure("response too large") }
            response += line + "\r\n"
            if line.isEmpty {
                return response
            }
        }
    }

    private func write(_ text: String, deadline: TimeInterval) throws {
        guard let input, let data = text.data(using: configuration.encoding), data.count <= Self.maximumFrame else {
            throw ShiolinkError.protocolFailure("request too large or not encodable")
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Self.ready(input.fileDescriptor, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(input.fileDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR || errno == EAGAIN {
                    continue
                } else {
                    throw ShiolinkError.closed
                }
            }
        }
    }

    private func readLine(deadline: TimeInterval) throws -> String {
        guard let output else { throw ShiolinkError.closed }
        while true {
            if let end = buffer.range(of: Data([13, 10])) {
                let line = buffer[..<end.lowerBound]
                guard let text = String(data: line, encoding: configuration.encoding) else {
                    throw ShiolinkError.protocolFailure("response encoding mismatch")
                }
                buffer.removeSubrange(..<end.upperBound)
                return text
            }
            guard buffer.count <= Self.maximumFrame else { throw ShiolinkError.protocolFailure("response line too large") }
            try Self.ready(output.fileDescriptor, events: Int16(POLLIN), deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
            } else if count < 0, errno == EINTR || errno == EAGAIN {
                continue
            } else {
                throw ShiolinkError.closed
            }
        }
    }

    private static func ready(_ fd: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ShiolinkError.timeout }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, 1000)))
            if result < 0, errno == EINTR {
                continue
            }
            if result < 0 {
                throw ShiolinkError.closed
            }
            if result == 0 {
                continue
            }
            // Drain available output even when the child has already exited.
            if descriptor.revents & events != 0 {
                return
            }
            throw ShiolinkError.closed
        }
    }

    private func stop(gracefully: Bool) {
        guard !closed else { return }
        closed = true
        Self.dispose(process: process, input: input, output: output, gracefully: gracefully)
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
    }

    private static func dispose(process: Process?, input: FileHandle?, output: FileHandle?, gracefully: Bool) {
        if gracefully, let process, process.isRunning, let input {
            let frame = Array("*U:\r\n".utf8)
            _ = frame.withUnsafeBytes { Darwin.write(input.fileDescriptor, $0.baseAddress, $0.count) }
        }
        try? input?.close()
        if let process, process.isRunning {
            if gracefully {
                let deadline = ProcessInfo.processInfo.systemUptime + 1
                while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                    usleep(10000)
                }
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        try? output?.close()
    }
}

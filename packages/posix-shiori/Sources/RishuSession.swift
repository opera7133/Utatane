import Darwin
import Foundation

public enum RishuError: LocalizedError {
    case configuration(String)
    case protocolFailure(String)
    case timeout
    case closed

    public var errorDescription: String? {
        switch self {
        case let .configuration(detail): "里珠: \(detail)"
        case let .protocolFailure(detail): "里珠 protocol: \(detail)"
        case .timeout: "里珠 response timed out"
        case .closed: "里珠 process is closed"
        }
    }
}

public final class RishuSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.utatane.rishu")
    private let masterDirectoryURL: URL
    private let scriptURL: URL
    private let perlExecutableURL: URL
    private let timeout: TimeInterval
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var closed = false
    private static let maximumFrame = 8 * 1024 * 1024

    public init(
        masterDirectoryURL: URL,
        perlExecutableURL: URL? = nil,
        timeout: TimeInterval = 10
    ) throws {
        guard timeout.isFinite, timeout > 0 else { throw RishuError.configuration("invalid timeout") }
        guard let scriptURL = Self.remoteScriptURL(in: masterDirectoryURL) else {
            throw RishuError.configuration("rishu_remote.pl not found")
        }
        self.masterDirectoryURL = masterDirectoryURL.standardizedFileURL
        self.scriptURL = scriptURL
        self.perlExecutableURL = perlExecutableURL
            ?? ProcessInfo.processInfo.environment["UTATANE_RISHU_PERL_EXECUTABLE"].map { URL(filePath: $0) }
            ?? URL(filePath: "/usr/bin/perl")
        self.timeout = timeout
    }

    public static func remoteScriptURL(in directory: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.lastPathComponent.caseInsensitiveCompare("rishu_remote.pl") == .orderedSame }
    }

    deinit {
        let process = process
        let input = input
        let output = output
        queue.async { Self.dispose(process: process, input: input, output: output) }
    }

    public func request(_ request: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let response = try self.exchange(request)
                    continuation.resume(returning: response)
                } catch {
                    self.stop()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.closed {
                    let deadline = ProcessInfo.processInfo.systemUptime + min(self.timeout, 1)
                    try? self.write("PROXY UNLOAD RISHU/1.1\r\n\r\n", deadline: deadline)
                    _ = try? self.readFrame(deadline: deadline)
                }
                self.stop()
                continuation.resume()
            }
        }
    }

    private func exchange(_ request: String) throws -> String {
        guard !closed else { throw RishuError.closed }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try start(deadline: deadline)
        guard request.hasSuffix("\r\n\r\n") else {
            throw RishuError.protocolFailure("request must end with CRLF CRLF")
        }
        try write("PROXY REQUEST RISHU/1.1\r\nCommand: " + request, deadline: deadline)
        let wrapper = try readFrame(deadline: deadline)
        guard let marker = wrapper.range(of: "Original-Response: ", options: [.caseInsensitive]) else {
            throw RishuError.protocolFailure("Original-Response missing")
        }
        return String(wrapper[marker.upperBound...])
    }

    private func start(deadline: TimeInterval) throws {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: perlExecutableURL.path) else {
            throw RishuError.configuration("Perl executable not found")
        }
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = perlExecutableURL
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = masterDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
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
                throw RishuError.protocolFailure("cannot configure pipe")
            }
        }
        guard fcntl(input!.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw RishuError.protocolFailure("cannot configure pipe signals")
        }
        let path = masterDirectoryURL.path + "/"
        guard !path.contains("\r"), !path.contains("\n"), path.canBeConverted(to: .shiftJIS) else {
            throw RishuError.configuration("master path is not Shift_JIS compatible")
        }
        try write("PROXY LOAD RISHU/1.1\r\nDirectory: \(path)\r\n\r\n", deadline: deadline)
        let response = try readFrame(deadline: deadline)
        guard response.range(of: #"^RISHU/\d+\.\d+ 2\d\d "#, options: .regularExpression) != nil else {
            throw RishuError.protocolFailure("load failed")
        }
    }

    private func readFrame(deadline: TimeInterval) throws -> String {
        while true {
            if let end = buffer.range(of: Data([13, 10, 13, 10])) {
                let header = buffer[..<end.upperBound]
                guard let headerText = String(data: header, encoding: .shiftJIS) else {
                    throw RishuError.protocolFailure("response encoding mismatch")
                }
                let contentLength = Self.contentLength(in: headerText)
                let frameEnd = end.upperBound + contentLength
                if buffer.count >= frameEnd {
                    let frame = buffer[..<frameEnd]
                    buffer.removeSubrange(..<frameEnd)
                    guard let text = String(data: frame, encoding: .shiftJIS) else {
                        throw RishuError.protocolFailure("response encoding mismatch")
                    }
                    return text
                }
            }
            guard buffer.count <= Self.maximumFrame else { throw RishuError.protocolFailure("response too large") }
            guard let output else { throw RishuError.closed }
            try Self.ready(output.fileDescriptor, events: Int16(POLLIN), deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
            } else if count < 0, errno == EINTR || errno == EAGAIN {
                continue
            } else {
                throw RishuError.closed
            }
        }
    }

    private static func contentLength(in header: String) -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let fields = line.split(separator: ":", maxSplits: 1)
            if fields.count == 2, fields[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                return Int(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func write(_ text: String, deadline: TimeInterval) throws {
        guard let input, let data = text.data(using: .shiftJIS), data.count <= Self.maximumFrame else {
            throw RishuError.protocolFailure("request too large or not Shift_JIS encodable")
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
                    throw RishuError.closed
                }
            }
        }
    }

    private static func ready(_ fd: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw RishuError.timeout }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, 1000)))
            if result < 0, errno == EINTR {
                continue
            }
            if result < 0 {
                throw RishuError.closed
            }
            if result == 0 {
                continue
            }
            if descriptor.revents & events != 0 {
                return
            }
            throw RishuError.closed
        }
    }

    private func stop() {
        guard !closed else { return }
        closed = true
        Self.dispose(process: process, input: input, output: output)
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
    }

    private static func dispose(process: Process?, input: FileHandle?, output: FileHandle?) {
        try? input?.close()
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        try? output?.close()
    }
}

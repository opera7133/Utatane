import Darwin
import Foundation
import UtataneNativeSaori

public enum NativeShioriProcessError: LocalizedError, Sendable {
    case missingHost(URL)
    case hostFailure(UInt8, String)
    case ended
    case timeout
    case invalidFrame
    case busy

    public var canRecoverByLoadingAnotherModule: Bool {
        if case let .hostFailure(status, _) = self {
            return status == 1 || status == 2
        }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case let .missingHost(url): "SHIORIホストが見つかりません: \(url.path)"
        case let .hostFailure(_, reason): "SHIORIホスト: \(reason)"
        case .ended: "SHIORIの実行プロセスが終了しました。"
        case .timeout: "SHIORIの応答が時間内に返りませんでした。"
        case .invalidFrame: "SHIORIホストから不正な応答を受け取りました。"
        case .busy: "SHIORIは処理中です。"
        }
    }
}

/// A conventional SHIORI image, its globals and native SAORI live in one child process.
/// Requests are never replayed after failure, since they can mutate persistent state.
public final class NativeShioriProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let timeout: TimeInterval
    private let windowController: (any NativeSaoriWindowControlling)?
    private var closed = false
    private static let maximumBytes = 8 * 1024 * 1024

    public static var defaultHostURL: URL {
        if let path = ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL.appending(path: "Contents/Helpers/utatane-shiori-host")
    }

    public init(directoryURL: URL, moduleURL: URL, hostURL: URL = NativeShioriProcessSession.defaultHostURL,
                timeout: TimeInterval = 30, startupTimeout: TimeInterval = 30,
                windowController: (any NativeSaoriWindowControlling)? = nil,
                additionalEnvironment: [String: String] = [:]) throws
    {
        guard timeout.isFinite, timeout > 0, startupTimeout.isFinite, startupTimeout > 0 else {
            throw NativeShioriProcessError.invalidFrame
        }
        guard FileManager.default.isExecutableFile(atPath: hostURL.path) else {
            throw NativeShioriProcessError.missingHost(hostURL)
        }
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = hostURL
        process.arguments = [moduleURL.standardizedFileURL.path, directoryURL.standardizedFileURL.path]
        process.currentDirectoryURL = directoryURL
        if !additionalEnvironment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(additionalEnvironment) { _, override in override }
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        self.timeout = timeout
        self.windowController = windowController
        do {
            try process.run()
            try inputPipe.fileHandleForReading.close()
            try outputPipe.fileHandleForWriting.close()
            for handle in [input, output] {
                let fd = handle.fileDescriptor
                guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
                    throw NativeShioriProcessError.invalidFrame
                }
            }
            guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw NativeShioriProcessError.invalidFrame
            }
            let ready = try receive(deadline: ProcessInfo.processInfo.systemUptime + startupTimeout)
            guard ready.isEmpty else { throw NativeShioriProcessError.invalidFrame }
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        // Normal shutdown calls close(). An abandoned live session gets a bounded
        // save attempt off the UI thread before its process is reaped.
        if !closed {
            let process = process
            let input = input
            let output = output
            DispatchQueue.global(qos: .utility).async {
                defer {
                    try? input.close()
                    try? output.close()
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                do {
                    let deadline = ProcessInfo.processInfo.systemUptime + 2
                    try Self.ready(input.fileDescriptor, events: Int16(POLLOUT), deadline: deadline)
                    let frame: [UInt8] = [1, 0, 0, 0, 2]
                    guard Darwin.write(input.fileDescriptor, frame, frame.count) == frame.count else { return }
                    var response = [UInt8](repeating: 0, count: 5)
                    var offset = 0
                    let responseSize = response.count
                    while offset < responseSize {
                        try Self.ready(output.fileDescriptor, events: Int16(POLLIN), deadline: deadline)
                        let count = response.withUnsafeMutableBytes {
                            Darwin.read(output.fileDescriptor, $0.baseAddress!.advanced(by: offset), responseSize - offset)
                        }
                        guard count > 0 else { return }
                        offset += count
                    }
                    if response != [1, 0, 0, 0, 0] {
                        NSLog("SHIORI save failed during cleanup")
                    }
                } catch { NSLog("SHIORI cleanup failed: %@", error.localizedDescription) }
            }
        }
    }

    public func request(_ message: String) throws -> String {
        guard lock.try() else { throw NativeShioriProcessError.busy }
        defer { lock.unlock() }
        guard !closed else { throw NativeShioriProcessError.ended }
        let payload = Data(message.utf8)
        guard payload.count <= Self.maximumBytes else { throw NativeShioriProcessError.invalidFrame }
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            try send(command: 1, payload: payload, deadline: deadline)
            let result = try receive(deadline: deadline)
            guard let text = String(data: result, encoding: .utf8) else { throw NativeShioriProcessError.invalidFrame }
            return text
        } catch {
            stop()
            throw error
        }
    }

    public func close() throws {
        guard lock.try() else { throw NativeShioriProcessError.busy }
        defer { lock.unlock() }
        guard !closed else { return }
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            try send(command: 2, payload: Data(), deadline: deadline)
            guard try receive(deadline: deadline).isEmpty else { throw NativeShioriProcessError.invalidFrame }
            stop()
        } catch {
            // Saving may be retried after the caller fixes the destination.
            if case NativeShioriProcessError.hostFailure(5, _) = error {
                throw error
            }
            stop()
            throw error
        }
    }

    private func stop() {
        guard !closed else { return }
        closed = true
        try? input.close()
        try? output.close()
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func send(command: UInt8, payload: Data, deadline: TimeInterval) throws {
        let length = UInt32(payload.count + 1)
        var frame = Data((0 ..< 4).map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) })
        frame.append(command)
        frame.append(payload)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Self.ready(input.fileDescriptor, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(input.fileDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR || errno == EAGAIN {
                    continue
                } else {
                    throw NativeShioriProcessError.ended
                }
            }
        }
    }

    private func receive(deadline: TimeInterval) throws -> Data {
        var callbackCount = 0
        while true {
            let header = try readExact(4, deadline: deadline)
            let size = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            guard size >= 1, size <= Self.maximumBytes + 1 else { throw NativeShioriProcessError.invalidFrame }
            let body = try readExact(Int(size), deadline: deadline)
            let status = body[0]
            let payload = body.dropFirst()
            if status != 6 {
                guard status == 0 else {
                    throw NativeShioriProcessError.hostFailure(status, String(data: payload, encoding: .utf8) ?? "Invalid error message")
                }
                return Data(payload)
            }
            callbackCount += 1
            guard callbackCount <= 1024 else { throw NativeShioriProcessError.invalidFrame }
            guard payload.count == 16 else { throw NativeShioriProcessError.invalidFrame }
            let values = (0 ..< 4).map { index -> Int32 in
                let start = payload.startIndex + index * 4
                let bits = (0 ..< 4).reduce(UInt32(0)) { result, offset in
                    result | UInt32(payload[start + offset]) << (offset * 8)
                }
                return Int32(bitPattern: bits)
            }
            var result = [Int32](repeating: 0, count: 5)
            switch values[0] {
            case 1:
                if let frame = windowController?.frame(scope: Int(values[1])) {
                    result = [1, Int32(clamping: frame.x), Int32(clamping: frame.y),
                              Int32(clamping: frame.width), Int32(clamping: frame.height)]
                }
            case 2:
                if let size = windowController?.desktopSize() {
                    result = [1, Int32(clamping: size.width), Int32(clamping: size.height), 0, 0]
                }
            case 3:
                if let windowController {
                    windowController.move(scope: Int(values[1]), x: Int(values[2]), speed: Int(values[3]))
                    result[0] = 1
                }
            default: break
            }
            let reply = Data(result.flatMap { value in
                let bits = UInt32(bitPattern: value)
                return (0 ..< 4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
            })
            try send(command: 3, payload: reply, deadline: deadline)
        }
    }

    private func readExact(_ size: Int, deadline: TimeInterval) throws -> Data {
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: min(size, 8192))
        while data.count < size {
            try Self.ready(output.fileDescriptor, events: Int16(POLLIN), deadline: deadline)
            let count = Darwin.read(output.fileDescriptor, &bytes, min(bytes.count, size - data.count))
            if count > 0 {
                data.append(contentsOf: bytes.prefix(count))
            } else if count < 0, errno == EINTR || errno == EAGAIN {
                continue
            } else {
                throw NativeShioriProcessError.ended
            }
        }
        return data
    }

    private static func ready(_ fd: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw NativeShioriProcessError.timeout }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
            if result > 0 {
                if descriptor.revents & events != 0 {
                    return
                }
                throw NativeShioriProcessError.ended
            }
            if result == 0 {
                throw NativeShioriProcessError.timeout
            }
            if errno != EINTR {
                throw NativeShioriProcessError.ended
            }
        }
    }
}

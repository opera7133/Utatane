import Foundation
import UtataneShiori

public struct WindowsShioriProcessConfiguration: Sendable, Equatable {
    public let wineExecutableURL: URL
    public let winePrefixURL: URL
    public let hostExecutableURL: URL
    public let materiaExecutableURL: URL
    public let shioriDLLURL: URL
    public var environment: [String: String]

    public init(
        wineExecutableURL: URL,
        winePrefixURL: URL,
        hostExecutableURL: URL,
        materiaExecutableURL: URL,
        shioriDLLURL: URL,
        environment: [String: String] = [:]
    ) {
        self.wineExecutableURL = wineExecutableURL
        self.winePrefixURL = winePrefixURL
        self.hostExecutableURL = hostExecutableURL
        self.materiaExecutableURL = materiaExecutableURL
        self.shioriDLLURL = shioriDLLURL
        self.environment = environment
    }
}

public enum WindowsShioriProcessError: LocalizedError, Equatable, Sendable {
    case missingFile(URL)
    case invalidHostReadyFrame(Int)
    case processEnded
    case invalidFrameLength(Int)
    case requestEncodingFailed
    case responseDecodingFailed

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            "Windows SHIORIの実行に必要なファイルがない: \(url.path)"
        case let .invalidHostReadyFrame(length):
            "Windows SHIORIホストの起動応答が不正: \(length)"
        case .processEnded:
            "Windows SHIORIホストが終了した"
        case let .invalidFrameLength(length):
            "Windows SHIORIホストの応答サイズが不正: \(length)"
        case .requestEncodingFailed:
            "SHIORI要求をShift_JISへ変換できない"
        case .responseDecodingFailed:
            "Windows SHIORIの応答を文字列へ変換できない"
        }
    }
}

public enum WindowsShioriFrameCodec {
    public static let maximumPayloadSize = 16 * 1024 * 1024

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximumPayloadSize else {
            throw WindowsShioriProcessError.invalidFrameLength(payload.count)
        }
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    public static func decodeLength(_ data: Data, allowsReadyFrame: Bool = false) throws -> Int {
        guard data.count == MemoryLayout<UInt32>.size else {
            throw WindowsShioriProcessError.processEnded
        }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let length = Int(UInt32(littleEndian: raw))
        guard (allowsReadyFrame && length == 0) || (length > 0 && length <= maximumPayloadSize) else {
            throw WindowsShioriProcessError.invalidFrameLength(length)
        }
        return length
    }
}

public final class WindowsShioriProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var isClosed = false

    public init(configuration: WindowsShioriProcessConfiguration) throws {
        for url in [
            configuration.wineExecutableURL,
            configuration.hostExecutableURL,
            configuration.materiaExecutableURL,
            configuration.shioriDLLURL
        ] where !FileManager.default.fileExists(atPath: url.path) {
            throw WindowsShioriProcessError.missingFile(url)
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = configuration.wineExecutableURL
        process.arguments = [
            configuration.hostExecutableURL.path,
            "serve",
            Self.windowsPath(for: configuration.materiaExecutableURL),
            Self.windowsPath(for: configuration.shioriDLLURL)
        ]
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

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading

        let readyLength = try WindowsShioriFrameCodec.decodeLength(
            Self.readExact(count: MemoryLayout<UInt32>.size, from: output),
            allowsReadyFrame: true
        )
        guard readyLength == 0 else {
            throw WindowsShioriProcessError.invalidHostReadyFrame(readyLength)
        }
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

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        try ShioriMessageParser.parseResponse(self.request(request.serialized()))
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

    public static func windowsPath(for url: URL) -> String {
        "Z:" + url.standardizedFileURL.path.replacingOccurrences(of: "/", with: "\\")
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

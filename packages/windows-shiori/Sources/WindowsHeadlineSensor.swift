import Foundation
import UtataneNetwork
import UtataneShiori

public struct WindowsHeadlineHostConfiguration: Sendable, Equatable {
    public let wineExecutableURL: URL
    public let winePrefixURL: URL
    public let hostExecutableURL: URL

    public init(wineExecutableURL: URL, winePrefixURL: URL, hostExecutableURL: URL) {
        self.wineExecutableURL = wineExecutableURL
        self.winePrefixURL = winePrefixURL
        self.hostExecutableURL = hostExecutableURL
    }
}

public typealias WindowsHeadlineItem = HeadlineSensorItem

public struct WindowsHeadlineResult: Sendable, Equatable {
    public let version: String?
    public let items: [WindowsHeadlineItem]

    public init(version: String?, items: [WindowsHeadlineItem]) {
        self.version = version
        self.items = items
    }
}

public enum WindowsHeadlineError: LocalizedError, Equatable, Sendable {
    case missingURL
    case missingDLL(URL)
    case unsuccessfulResponse(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            "ヘッドラインの取得URLが設定されていない"
        case let .missingDLL(url):
            "HEADLINE DLLが見つからない: \(url.path)"
        case let .unsuccessfulResponse(code, reason):
            "HEADLINE DLLがエラーを返した: \(code) \(reason)"
        case .invalidResponse:
            "HEADLINE DLLの応答を解析できない"
        }
    }
}

public struct WindowsHeadlineSensor: Sendable {
    private let configuration: WindowsHeadlineHostConfiguration

    public init(configuration: WindowsHeadlineHostConfiguration) {
        self.configuration = configuration
    }

    public func analyze(
        headline: InstalledHeadline,
        oldFileURL: URL?,
        newFileURL: URL
    ) throws -> WindowsHeadlineResult {
        guard case let .legacyDLL(fileName) = headline.kind else {
            throw WindowsHeadlineError.invalidResponse
        }
        let dllURL = headline.id.appending(path: fileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: dllURL.path) else {
            throw WindowsHeadlineError.missingDLL(dllURL)
        }

        let session = try WindowsDLLProcessSession(configuration: configuration, dllURL: dllURL)
        defer { session.close() }
        let versionResponse = try session.request(
            Self.versionRequest(charset: headline.charset),
            requestEncoding: Self.encoding(named: headline.charset)
        )
        let version = try Self.parsedResponse(versionResponse).headers["Value"]

        let oldItems: [WindowsHeadlineItem]
        if let oldFileURL, FileManager.default.fileExists(atPath: oldFileURL.path) {
            oldItems = try Self.items(
                from: session.request(
                    Self.headlineRequest(path: oldFileURL, charset: headline.charset),
                    requestEncoding: Self.encoding(named: headline.charset)
                )
            )
        } else {
            oldItems = []
        }
        let newItems = try Self.items(
            from: session.request(
                Self.headlineRequest(path: newFileURL, charset: headline.charset),
                requestEncoding: Self.encoding(named: headline.charset)
            )
        )
        let oldSet = Set(oldItems)
        let changed = headline.alwaysDisplay ? newItems : newItems.filter { !oldSet.contains($0) }
        return WindowsHeadlineResult(version: version, items: changed)
    }

    public static func items(from responseData: Data) throws -> [WindowsHeadlineItem] {
        let response = try parsedResponse(responseData)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw WindowsHeadlineError.unsuccessfulResponse(response.statusCode, response.reasonPhrase)
        }
        return response.headers.values(named: "Headline").compactMap { value in
            let fields = value.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            let title = String(fields[0])
                .replacingOccurrences(of: "\u{FFFD}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let url = fields.count > 1 ? String(fields[1]) : nil
            return WindowsHeadlineItem(title: title, url: url?.isEmpty == false ? url : nil)
        }
    }

    private static func parsedResponse(_ data: Data) throws -> ShioriResponse {
        let headerProbe = String(data: data, encoding: .isoLatin1) ?? ""
        let charset = headerProbe.components(separatedBy: .newlines).first { line in
            line.lowercased().hasPrefix("charset:")
        }?.split(separator: ":", maxSplits: 1).last.map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let text: String?
        if charset?.lowercased().replacingOccurrences(of: "-", with: "") == "utf8" {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .utf8)
        }
        guard let text else { throw WindowsHeadlineError.invalidResponse }
        return try ShioriMessageParser.parseResponse(text)
    }

    private static func versionRequest(charset: String) -> String {
        "GET Version HEADLINE/2.0\r\nCharset: \(charset)\r\nSender: Utatane\r\n\r\n"
    }

    private static func headlineRequest(path: URL, charset: String) -> String {
        "GET Headline HEADLINE/2.0\r\nCharset: \(charset)\r\nSender: Utatane\r\nOption: url\r\nPath: \(WindowsShioriProcessSession.windowsPath(for: path))\r\n\r\n"
    }

    private static func encoding(named charset: String) -> String.Encoding {
        charset.lowercased().replacingOccurrences(of: "-", with: "") == "utf8" ? .utf8 : .shiftJIS
    }
}

private final class WindowsDLLProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var isClosed = false

    init(configuration: WindowsHeadlineHostConfiguration, dllURL: URL) throws {
        for url in [configuration.wineExecutableURL, configuration.hostExecutableURL, dllURL]
        where !FileManager.default.fileExists(atPath: url.path) {
            throw WindowsShioriProcessError.missingFile(url)
        }
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = configuration.wineExecutableURL
        process.arguments = [
            configuration.hostExecutableURL.path,
            WindowsShioriProcessSession.windowsPath(for: dllURL)
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = configuration.winePrefixURL.path
        environment["WINEDEBUG"] = "-all"
        environment["WINEMSYNC"] = "1"
        environment["WINEESYNC"] = "1"
        process.environment = environment
        try process.run()

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        let ready = try WindowsShioriFrameCodec.decodeLength(
            Self.readExact(count: MemoryLayout<UInt32>.size, from: output),
            allowsReadyFrame: true
        )
        guard ready == 0 else { throw WindowsShioriProcessError.invalidHostReadyFrame(ready) }
    }

    deinit { close() }

    func request(_ request: String, requestEncoding: String.Encoding) throws -> Data {
        try lock.withLock {
            guard !isClosed else { throw WindowsShioriProcessError.processEnded }
            guard let payload = request.data(using: requestEncoding) else {
                throw WindowsShioriProcessError.requestEncodingFailed
            }
            try input.write(contentsOf: WindowsShioriFrameCodec.encode(payload))
            let length = try WindowsShioriFrameCodec.decodeLength(
                Self.readExact(count: MemoryLayout<UInt32>.size, from: output)
            )
            return try Self.readExact(count: length, from: output)
        }
    }

    func close() {
        lock.withLock {
            guard !isClosed else { return }
            isClosed = true
            try? input.close()
            try? output.close()
            if process.isRunning { process.terminate() }
        }
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

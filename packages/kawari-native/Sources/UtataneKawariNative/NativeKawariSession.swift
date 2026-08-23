import AppKit
import CKawariNative
import Foundation
import UtataneShiori

public enum NativeKawariError: LocalizedError, Equatable, Sendable {
    case loadFailed
    case requestFailed
    case undecodableResponse

    public var errorDescription: String? {
        switch self {
        case .loadFailed:
            "KAWARIがゴーストの読み込みに失敗した。"
        case .requestFailed:
            "KAWARIへのリクエストに失敗した。"
        case .undecodableResponse:
            "KAWARIの応答をShift_JISとして読み取れなかった。"
        }
    }
}

public final class NativeKawariSession: @unchecked Sendable {
    private let handle: UInt32
    private let compatibilityDirectoryURL: URL?
    private let usesLegacyCompatibility: Bool

    public init(masterDirectoryURL: URL) throws {
        Self.installNativeSaoriCallback()
        let preparation = try Self.prepareDirectoryIfNeeded(masterDirectoryURL)
        let preparedDirectory = preparation.directory
        compatibilityDirectoryURL = preparation.isLegacy ? preparedDirectory : nil
        usesLegacyCompatibility = preparation.isLegacy
        let path = preparedDirectory.standardizedFileURL.path + "/"
        guard let data = path.data(using: .shiftJIS) else {
            throw NativeKawariError.loadFailed
        }
        handle = data.withUnsafeBytes { bytes in
            utatane_kawari_create(
                bytes.bindMemory(to: CChar.self).baseAddress,
                Int64(data.count)
            )
        }
        guard handle != 0 else {
            throw NativeKawariError.loadFailed
        }
    }

    private static func installNativeSaoriCallback() {
        utatane_kawari_set_saori_request_callback(utataneKawariSaoriRequest)
    }

    deinit {
        _ = utatane_kawari_dispose(handle)
        if let compatibilityDirectoryURL {
            try? FileManager.default.removeItem(at: compatibilityDirectoryURL)
        }
    }

    private static func prepareDirectoryIfNeeded(_ masterDirectoryURL: URL) throws -> (directory: URL, isLegacy: Bool) {
        let currentConfig = masterDirectoryURL.appending(path: "kawarirc.kis")
        guard !FileManager.default.fileExists(atPath: currentConfig.path) else {
            return (masterDirectoryURL, false)
        }

        let legacyConfig = masterDirectoryURL.appending(path: "kawari.ini")
        guard FileManager.default.fileExists(atPath: legacyConfig.path) else {
            return (masterDirectoryURL, false)
        }
        let data = try Data(contentsOf: legacyConfig)
        guard let source = String(data: data, encoding: .shiftJIS) else {
            throw NativeKawariError.loadFailed
        }

        var startupCommands: [String] = []
        var dictionaryFilenames: [String] = []
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"),
                  let colon = line.firstIndex(of: ":")
            else { continue }
            let command = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let argument = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch command {
            case "set": startupCommands.append("set \(argument);")
            case "dict", "include":
                dictionaryFilenames.append(argument)
            default: continue
            }
        }

        var eventIDs = Set<String>()
        var generatedDictionaries: [(filename: String, data: Data)] = []
        for (dictionaryIndex, filename) in dictionaryFilenames.enumerated() {
            let dictionaryURL = masterDirectoryURL.appending(path: filename)
            guard let data = try? Data(contentsOf: dictionaryURL),
                  var dictionary = String(data: data, encoding: .shiftJIS)
            else { continue }
            for index in (0 ... 7).reversed() {
                dictionary = dictionary.replacingOccurrences(
                    of: "system.Reference\(index)",
                    with: "System.Request.Reference\(index + 1)"
                )
            }
            for rawLine in dictionary.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("event."), let colon = line.firstIndex(of: ":") else {
                    continue
                }
                let name = line[line.index(line.startIndex, offsetBy: 6) ..< colon]
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    eventIDs.insert(name)
                }
            }
            for (lineIndex, rawLine) in dictionary.components(separatedBy: .newlines).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), line.contains(":") else {
                    continue
                }
                let generatedFilename = "legacy-\(dictionaryIndex)-\(lineIndex).dat"
                guard let lineData = (line + "\r\n").data(using: .shiftJIS) else {
                    continue
                }
                generatedDictionaries.append((generatedFilename, lineData))
                startupCommands.append("load \(generatedFilename);")
            }
        }
        var compatibilityEntries: [String] = []
        if !eventIDs.contains("OnAITalk") {
            compatibilityEntries.append("event.OnAITalk : ${talk}")
        }
        var commands = compatibilityEntries + ["=kis", "debugger on;"]
        commands.append(contentsOf: startupCommands)
        commands.append("=end")

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Utatane-KAWARI-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for item in try FileManager.default.contentsOfDirectory(at: masterDirectoryURL, includingPropertiesForKeys: nil) {
                let destination = directory.appending(path: item.lastPathComponent)
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: item)
            }
            for generated in generatedDictionaries {
                try generated.data.write(
                    to: directory.appending(path: generated.filename),
                    options: .atomic
                )
            }
            guard let configData = commands.joined(separator: "\r\n").data(using: .shiftJIS) else {
                throw NativeKawariError.loadFailed
            }
            try configData.write(to: directory.appending(path: "kawarirc.kis"), options: .atomic)
            return (directory, true)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        guard usesLegacyCompatibility, let id = request.id else {
            return try ShioriMessageParser.parseResponse(self.request(request.serialized()))
        }
        let effectiveRequest = legacyEchoRequest(
            expression: "${event.\(id)}",
            originalRequest: request
        )
        return try ShioriMessageParser.parseResponse(self.request(effectiveRequest.serialized()))
    }

    private func legacyEchoRequest(expression: String, originalRequest request: ShioriRequest) -> ShioriRequest {
        var headers = ShioriHeaders([
            ShioriHeader(name: "Charset", value: "Shift_JIS"),
            ShioriHeader(name: "Sender", value: request.headers["Sender"] ?? "Utatane"),
            ShioriHeader(name: "SecurityLevel", value: request.headers["SecurityLevel"] ?? "local"),
            ShioriHeader(name: "ID", value: "ShioriEcho"),
            ShioriHeader(name: "Reference0", value: expression)
        ])
        for index in 0 ... 7 {
            if let value = request.reference(index) {
                headers.append(name: "Reference\(index + 1)", value: value)
            }
        }
        return ShioriRequest(method: "GET", headers: headers)
    }

    public func request(_ request: String) throws -> String {
        guard let data = request.data(using: .shiftJIS) else {
            throw NativeKawariError.undecodableResponse
        }
        var responseLength = Int64(data.count)
        let responsePointer = data.withUnsafeBytes { bytes in
            utatane_kawari_request(
                handle,
                bytes.bindMemory(to: CChar.self).baseAddress,
                &responseLength
            )
        }
        guard let responsePointer, responseLength >= 0 else {
            throw NativeKawariError.requestFailed
        }
        defer { utatane_kawari_free(responsePointer) }
        let responseData = Data(bytes: responsePointer, count: Int(responseLength))
        guard let response = String(data: responseData, encoding: .shiftJIS) else {
            throw NativeKawariError.undecodableResponse
        }
        return response
    }
}

private func utataneKawariSaoriRequest(
    _ request: UnsafePointer<CChar>?,
    _ length: UnsafeMutablePointer<Int64>?
) -> UnsafeMutablePointer<CChar>? {
    guard let request, let length, length.pointee >= 0 else { return nil }
    let data = Data(bytes: request, count: Int(length.pointee))
    guard let message = String(data: data, encoding: .shiftJIS) else { return nil }

    let response = nativeTextCopySaoriResponse(for: message)
    guard let responseData = response.data(using: .shiftJIS),
          let allocation = malloc(max(responseData.count, 1))
    else { return nil }
    responseData.copyBytes(to: allocation.assumingMemoryBound(to: UInt8.self), count: responseData.count)
    length.pointee = Int64(responseData.count)
    return allocation.assumingMemoryBound(to: CChar.self)
}

func nativeTextCopySaoriResponse(for message: String) -> String {
    if message.hasPrefix("GET Version SAORI/1.") {
        return "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\r\n"
    } else if message.hasPrefix("EXECUTE SAORI/1."),
              let text = header("Argument0", in: message)
    {
        writeToPasteboard(text)
        let result = header("Argument1", in: message) == "1" ? "Result: \(text)\r\n" : ""
        return "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\(result)\r\n"
    }
    return "SAORI/1.0 400 Bad Request\r\nCharset: Shift_JIS\r\n\r\n"
}

private func writeToPasteboard(_ text: String) {
    let operation = { @MainActor in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    if Thread.isMainThread {
        MainActor.assumeIsolated(operation)
    } else {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated(operation)
        }
    }
}

private func header(_ name: String, in message: String) -> String? {
    let prefix = name.lowercased() + ":"
    return message.split(whereSeparator: \ .isNewline).first { line in
        line.lowercased().hasPrefix(prefix)
    }.map { line in
        line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}

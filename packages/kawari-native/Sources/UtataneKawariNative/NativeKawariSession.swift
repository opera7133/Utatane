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

    public init(masterDirectoryURL: URL) throws {
        Self.installNativeSaoriCallback()
        let path = masterDirectoryURL.standardizedFileURL.path + "/"
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
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        try ShioriMessageParser.parseResponse(self.request(request.serialized()))
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

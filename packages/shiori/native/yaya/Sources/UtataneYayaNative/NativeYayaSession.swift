import CYayaNative
import Foundation
import UtataneNativeSaori
import UtataneShiori

private let activeYayaSaori = YayaSaoriSlot()
private let yayaRuntimeLock = NSLock()

private final class YayaSaoriSlot: @unchecked Sendable {
    var registry: NativeSaoriRegistry?
}

public enum NativeYayaError: LocalizedError, Equatable, Sendable {
    case loadFailed(URL)
    case requestFailed
    case undecodableResponse

    public var errorDescription: String? {
        switch self {
        case let .loadFailed(url):
            "YAYAがゴーストを読み込めなかった: \(url.path)"
        case .requestFailed:
            "YAYAから応答が返らなかった"
        case .undecodableResponse:
            "YAYAの応答をUTF-8またはShift_JISとして読み取れなかった"
        }
    }
}

/// A macOS-native instance of the upstream YAYA evaluator.
///
/// Access is serialized because the original VM keeps some process-global state.
public final class NativeYayaSession: @unchecked Sendable {
    private var instanceID: Int
    private let saoriRegistry: NativeSaoriRegistry

    public init(masterDirectoryURL: URL, saoriRegistry: NativeSaoriRegistry? = nil) throws {
        self.saoriRegistry = saoriRegistry ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        let path = masterDirectoryURL.standardizedFileURL.path
        instanceID = yayaRuntimeLock.withLock {
            utatane_yaya_set_saori_request_callback(utataneYayaSaoriRequest)
            return path.withCString { utatane_yaya_create_utf8($0) }
        }
        guard instanceID > 0 else {
            throw NativeYayaError.loadFailed(masterDirectoryURL)
        }
    }

    deinit {
        yayaRuntimeLock.withLock {
            if instanceID > 0 {
                _ = utatane_yaya_destroy(instanceID)
                instanceID = 0
            }
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        let responseText = try self.request(request.serialized())
        return try ShioriMessageParser.parseResponse(responseText)
    }

    public func request(_ request: String) throws -> String {
        try yayaRuntimeLock.withLock {
            activeYayaSaori.registry = saoriRegistry
            defer { activeYayaSaori.registry = nil }
            var responseLength = 0
            let responseBuffer = request.withCString {
                utatane_yaya_request(instanceID, $0, &responseLength)
            }
            guard let responseBuffer else {
                throw NativeYayaError.requestFailed
            }
            defer { utatane_yaya_free(responseBuffer) }

            let data = Data(bytes: responseBuffer, count: responseLength)
            if let response = String(data: data, encoding: .utf8) {
                return response
            }
            if let response = String(data: data, encoding: .shiftJIS) {
                return response
            }
            throw NativeYayaError.undecodableResponse
        }
    }
}

private func utataneYayaSaoriRequest(
    _ path: UnsafePointer<CChar>?,
    _ request: UnsafePointer<CChar>?,
    _ length: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<CChar>? {
    guard let path, let request, let length, length.pointee >= 0,
          let registry = activeYayaSaori.registry else { return nil }
    let data = Data(bytes: request, count: length.pointee)
    let encoding: String.Encoding = String(data: data, encoding: .utf8) == nil ? .shiftJIS : .utf8
    guard let message = String(data: data, encoding: encoding) else { return nil }
    let modulePath = String(cString: path)
    registry.load(modulePath)
    let response = registry.response(path: modulePath, request: message)
    guard let responseData = response.data(using: encoding), let allocation = malloc(max(responseData.count, 1))
    else { return nil }
    responseData.copyBytes(to: allocation.assumingMemoryBound(to: UInt8.self), count: responseData.count)
    length.pointee = responseData.count
    return allocation.assumingMemoryBound(to: CChar.self)
}

import CYayaNative
import Foundation
import UtataneShiori

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
    private let lock = NSLock()
    private var instanceID: Int

    public init(masterDirectoryURL: URL) throws {
        let path = masterDirectoryURL.standardizedFileURL.path
        instanceID = path.withCString { utatane_yaya_create_utf8($0) }
        guard instanceID > 0 else {
            throw NativeYayaError.loadFailed(masterDirectoryURL)
        }
    }

    deinit {
        lock.withLock {
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
        try lock.withLock {
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

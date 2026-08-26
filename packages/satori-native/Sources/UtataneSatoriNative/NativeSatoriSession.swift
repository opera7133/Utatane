import CSatoriNative
import Foundation
import UtataneNativeSaori
import UtataneShiori

private let activeSatoriSaori = SatoriSaoriSlot()

private final class SatoriSaoriSlot: @unchecked Sendable {
    var registry: NativeSaoriRegistry?
}

public enum NativeSatoriError: LocalizedError, Equatable, Sendable {
    case loadFailed(URL)
    case requestFailed
    case undecodableResponse

    public var errorDescription: String? {
        switch self {
        case let .loadFailed(url):
            "SATORIがゴーストを読み込めなかった: \(url.path)"
        case .requestFailed:
            "SATORIから応答が返らなかった"
        case .undecodableResponse:
            "SATORIの応答をUTF-8またはShift_JISとして読み取れなかった"
        }
    }
}

/// A macOS-native instance of the upstream SATORI evaluator.
///
/// The bridge serializes access because the upstream POSIX host keeps the
/// currently selected instance in process-global state.
public final class NativeSatoriSession: @unchecked Sendable {
    private let lock = NSLock()
    private var instanceID: Int
    private let saoriRegistry: NativeSaoriRegistry

    public init(masterDirectoryURL: URL, saoriRegistry: NativeSaoriRegistry? = nil) throws {
        self.saoriRegistry = saoriRegistry ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        utatane_satori_set_saori_request_callback(utataneSatoriSaoriRequest)
        let path = masterDirectoryURL.standardizedFileURL.path
        instanceID = path.withCString { Int(utatane_satori_create($0)) }
        guard instanceID > 0 else { throw NativeSatoriError.loadFailed(masterDirectoryURL) }
    }

    deinit {
        lock.withLock {
            if instanceID > 0 {
                _ = utatane_satori_destroy(instanceID)
                instanceID = 0
            }
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        var request = request
        if request.id == "OnSurfaceChange" {
            for index in 0 ... 1 where request.reference(index) == nil {
                request.headers.append(name: "Reference\(index)", value: "-1")
            }
        }
        return try ShioriMessageParser.parseResponse(self.request(request.serialized()))
    }

    public func request(_ request: String) throws -> String {
        try lock.withLock {
            activeSatoriSaori.registry = saoriRegistry
            defer { activeSatoriSaori.registry = nil }
            let encoding: String.Encoding = request.localizedCaseInsensitiveContains("Charset: Shift_JIS")
                ? .shiftJIS
                : .utf8
            var requestBytes = Array(request.data(using: encoding) ?? Data(request.utf8))
            requestBytes.append(0)
            var responseLength = 0
            let responseBuffer = requestBytes.withUnsafeBufferPointer {
                utatane_satori_request(instanceID, $0.baseAddress, &responseLength)
            }
            guard let responseBuffer else { throw NativeSatoriError.requestFailed }
            defer { utatane_satori_free(responseBuffer) }
            let data = Data(bytes: responseBuffer, count: responseLength)
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
            if let text = String(data: data, encoding: .shiftJIS) {
                return text
            }
            return decodeMixedJapanese(data)
        }
    }
}

private func utataneSatoriSaoriRequest(
    _ path: UnsafePointer<CChar>?,
    _ request: UnsafePointer<CChar>?,
    _ length: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<CChar>? {
    guard let path, let request, let length, length.pointee >= 0,
          let registry = activeSatoriSaori.registry else { return nil }
    let data = Data(bytes: request, count: length.pointee)
    guard let message = String(data: data, encoding: .shiftJIS) else { return nil }
    let modulePath = String(cString: path)
    registry.load(modulePath)
    let response = registry.response(path: modulePath, request: message)
    guard let responseData = response.data(using: .shiftJIS), let allocation = malloc(max(responseData.count, 1))
    else { return nil }
    responseData.copyBytes(to: allocation.assumingMemoryBound(to: UInt8.self), count: responseData.count)
    length.pointee = responseData.count
    return allocation.assumingMemoryBound(to: CChar.self)
}

private func decodeMixedJapanese(_ data: Data) -> String {
    let bytes = Array(data)
    var result = ""
    var index = 0
    while index < bytes.count {
        let byte = bytes[index]
        if byte < 0x80 {
            result.append(Character(UnicodeScalar(byte)))
            index += 1
            continue
        }

        let utf8Length: Int? = if byte >= 0xC2 && byte <= 0xDF {
            2
        } else if byte >= 0xE0 && byte <= 0xEF {
            3
        } else if byte >= 0xF0 && byte <= 0xF4 {
            4
        } else {
            nil
        }
        if let utf8Length, index + utf8Length <= bytes.count {
            let candidate = Data(bytes[index ..< index + utf8Length])
            if let decoded = String(data: candidate, encoding: .utf8) {
                result += decoded
                index += utf8Length
                continue
            }
        }

        let isLead = (0x81 ... 0x9F).contains(byte) || (0xE0 ... 0xFC).contains(byte)
        if isLead, index + 1 < bytes.count {
            let trail = bytes[index + 1]
            let isTrail = (0x40 ... 0x7E).contains(trail) || (0x80 ... 0xFC).contains(trail)
            if isTrail,
               let decoded = String(data: Data(bytes[index ... index + 1]), encoding: .shiftJIS)
            {
                result += decoded
                index += 2
                continue
            }
        }
        if (0xA1 ... 0xDF).contains(byte),
           let decoded = String(data: Data([byte]), encoding: .shiftJIS)
        {
            result += decoded
        } else {
            result.append("�")
        }
        index += 1
    }
    return result
}

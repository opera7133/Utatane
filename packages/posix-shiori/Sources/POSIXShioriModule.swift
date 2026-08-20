import Darwin
import Foundation
import UtataneShiori

public enum POSIXShioriKind: String, Sendable {
    case aosora

    public var charset: String {
        "UTF-8"
    }
}

public enum POSIXShioriError: LocalizedError, Equatable, Sendable {
    case unsupportedGhost
    case moduleUnavailable(POSIXShioriKind)
    case moduleLoadFailed(URL, String)
    case missingSymbol(String)
    case shioriLoadFailed
    case requestFailed
    case undecodableResponse

    public var errorDescription: String? {
        switch self {
        case .unsupportedGhost:
            "対応するネイティブSHIORIを判別できなかった。"
        case let .moduleUnavailable(kind):
            "\(kind.rawValue)用のネイティブSHIORIが見つからない。"
        case let .moduleLoadFailed(url, reason):
            "ネイティブSHIORIを読み込めなかった: \(url.lastPathComponent) (\(reason))"
        case let .missingSymbol(symbol):
            "ネイティブSHIORIに必要な関数がない: \(symbol)"
        case .shioriLoadFailed:
            "ネイティブSHIORIがゴーストの読み込みに失敗した。"
        case .requestFailed:
            "ネイティブSHIORIへのリクエストに失敗した。"
        case .undecodableResponse:
            "ネイティブSHIORIの応答を文字列へ変換できなかった。"
        }
    }
}

public struct POSIXShioriModuleResolver: Sendable {
    public init() {}

    public func kind(for masterDirectoryURL: URL) -> POSIXShioriKind? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "aosora.dll").path)
            || fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "ghost.asproj").path)
        {
            return .aosora
        }
        return nil
    }

    public func moduleURL(
        for kind: POSIXShioriKind,
        masterDirectoryURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let path = environment["UTATANE_AOSORA_MODULE"], !path.isEmpty {
            let url = URL(filePath: path, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        for url in candidateURLs(for: kind, masterDirectoryURL: masterDirectoryURL) {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func candidateURLs(for kind: POSIXShioriKind, masterDirectoryURL: URL) -> [URL] {
        let names = ["libaosora.dylib", "libaosora.so", "libaosora.bundle"]
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Utatane/NativeShiori/\(kind.rawValue)", directoryHint: .isDirectory)
        var directories = [masterDirectoryURL, applicationSupport]
        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appending(path: "NativeShiori/\(kind.rawValue)", directoryHint: .isDirectory))
        }
        return directories.flatMap { directory in
            names.map { directory.appending(path: $0, directoryHint: .notDirectory) }
        }
    }
}

public final class POSIXShioriSession: @unchecked Sendable {
    private typealias InstanceLoad = @convention(c) (UnsafeMutablePointer<CChar>?, Int) -> Int
    private typealias InstanceUnload = @convention(c) (Int) -> Int32
    private typealias InstanceRequest = @convention(c) (
        Int,
        UnsafeMutablePointer<CChar>?,
        UnsafeMutablePointer<Int>?
    ) -> UnsafeMutablePointer<CChar>?

    private static let globalLock = NSLock()
    private let moduleHandle: UnsafeMutableRawPointer
    private let instanceID: Int
    private let unload: InstanceUnload
    private let requestFunction: InstanceRequest

    public init(masterDirectoryURL: URL, moduleURL: URL, kind _: POSIXShioriKind) throws {
        guard let handle = dlopen(moduleURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw POSIXShioriError.moduleLoadFailed(moduleURL, reason)
        }
        moduleHandle = handle

        do {
            let symbols = try Self.globalLock.withLock {
                let load: InstanceLoad = try Self.symbol("aosora_load", in: handle)
                let unload: InstanceUnload = try Self.symbol("aosora_unload", in: handle)
                let request: InstanceRequest = try Self.symbol("aosora_request", in: handle)
                let path = masterDirectoryURL.standardizedFileURL.path + "/"
                let instanceID = try Self.withOwnedCString(path) { pointer, length in
                    load(pointer, length)
                }
                guard instanceID > 0 else { throw POSIXShioriError.shioriLoadFailed }
                return (instanceID, unload, request)
            }
            instanceID = symbols.0
            unload = symbols.1
            requestFunction = symbols.2
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit {
        Self.globalLock.withLock {
            _ = unload(instanceID)
            dlclose(moduleHandle)
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        try ShioriMessageParser.parseResponse(self.request(request.serialized()))
    }

    public func request(_ request: String) throws -> String {
        try Self.globalLock.withLock {
            var responseLength = 0
            let responseBuffer = try Self.withOwnedCString(request) { pointer, length in
                responseLength = length
                return requestFunction(instanceID, pointer, &responseLength)
            }
            guard let responseBuffer else { throw POSIXShioriError.requestFailed }
            defer { free(responseBuffer) }
            let data = Data(bytes: responseBuffer, count: responseLength)
            guard let response = String(data: data, encoding: .utf8) else {
                throw POSIXShioriError.undecodableResponse
            }
            return response
        }
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(handle, name) else { throw POSIXShioriError.missingSymbol(name) }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func withOwnedCString<T>(
        _ string: String,
        body: (UnsafeMutablePointer<CChar>, Int) throws -> T
    ) throws -> T {
        guard let data = string.data(using: .utf8),
              let raw = calloc(max(data.count + 1, 1), 1)
        else { throw POSIXShioriError.undecodableResponse }
        data.copyBytes(to: raw.assumingMemoryBound(to: UInt8.self), count: data.count)
        return try body(raw.assumingMemoryBound(to: CChar.self), data.count)
    }
}

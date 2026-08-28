import Darwin
import Foundation
import UtataneShiori

public enum POSIXShioriKind: String, Sendable {
    case aosora
    case kagari

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
        // Do not classify index.lua alone: tkytk and other engines also use it.
        let descriptor = (try? String(contentsOf: masterDirectoryURL.appending(path: "descript.txt"), encoding: .utf8))
            ?? (try? String(contentsOf: masterDirectoryURL.appending(path: "descript.txt"), encoding: .shiftJIS)) ?? ""
        let declaresKagari = descriptor.components(separatedBy: .newlines).contains { line in
            let pair = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            return pair.count == 2 && pair[0] == "shiori" && ["kagari.dll", "libkagari.dylib", "libkagari.so"].contains(pair[1])
        }
        if declaresKagari || fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "kagari.dll").path) {
            return .kagari
        }
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
        if let path = environment["UTATANE_\(kind.rawValue.uppercased())_MODULE"], !path.isEmpty {
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
        let names = ["lib\(kind.rawValue).dylib", "lib\(kind.rawValue).so", "lib\(kind.rawValue).bundle"]
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
    private let unload: (Int) -> Int32
    private let requestFunction: (Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?) -> UnsafeMutablePointer<CChar>?
    private var closed = false

    private typealias KagariLoad = @convention(c) (UnsafeMutablePointer<CChar>?, Int) -> Int32
    private typealias KagariUnload = @convention(c) (Int32) -> Int32
    private typealias KagariRequest = @convention(c) (Int32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?) -> UnsafeMutablePointer<CChar>?

    public init(masterDirectoryURL: URL, moduleURL: URL, kind: POSIXShioriKind) throws {
        guard let handle = dlopen(moduleURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw POSIXShioriError.moduleLoadFailed(moduleURL, reason)
        }
        moduleHandle = handle

        do {
            let symbols = try Self.globalLock.withLock {
                let load: (UnsafeMutablePointer<CChar>?, Int) -> Int
                let unload: (Int) -> Int32
                let request: (Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?) -> UnsafeMutablePointer<CChar>?
                switch kind {
                case .aosora:
                    let loader: InstanceLoad = try Self.symbol("aosora_load", in: handle)
                    let unloader: InstanceUnload = try Self.symbol("aosora_unload", in: handle)
                    let requester: InstanceRequest = try Self.symbol("aosora_request", in: handle)
                    load = { loader($0, $1) }
                    unload = { unloader($0) }
                    request = { requester($0, $1, $2) }
                case .kagari:
                    let loader: KagariLoad = try Self.symbol("kagari_load", in: handle)
                    let unloader: KagariUnload = try Self.symbol("kagari_unload", in: handle)
                    let requester: KagariRequest = try Self.symbol("kagari_request", in: handle)
                    load = { Int(loader($0, $1)) }
                    unload = { unloader(Int32($0)) }
                    request = { requester(Int32($0), $1, $2) }
                }
                let path = masterDirectoryURL.standardizedFileURL.path + "/"
                let instanceID = try Self.withOwnedCString(path) { pointer, length in
                    load(pointer, length)
                }
                guard kind == .kagari ? instanceID >= 0 : instanceID > 0 else { throw POSIXShioriError.shioriLoadFailed }
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
            if !closed {
                _ = unload(instanceID)
            }
            dlclose(moduleHandle)
        }
    }

    public func close() {
        Self.globalLock.withLock {
            guard !closed else { return }
            closed = true
            _ = unload(instanceID)
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        try ShioriMessageParser.parseResponse(self.request(request.serialized()))
    }

    public func request(_ request: String) throws -> String {
        try Self.globalLock.withLock {
            guard !closed else { throw POSIXShioriError.requestFailed }
            var responseLength = 0
            let responseBuffer = try Self.withOwnedCString(request) { pointer, length in
                responseLength = length
                return requestFunction(instanceID, pointer, &responseLength)
            }
            guard let responseBuffer else { throw POSIXShioriError.requestFailed }
            defer { free(responseBuffer) }
            guard responseLength >= 0, responseLength <= 8 * 1024 * 1024 else { throw POSIXShioriError.requestFailed }
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

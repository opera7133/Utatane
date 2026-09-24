import CUtataneModuleABI
import Darwin
import Foundation
import UtataneNativeSaori
import UtataneShiori

public enum UtataneModuleError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case loadFailed(String)
    case missingSymbol(String)
    case unsupportedVersion(UInt32)
    case callFailed(Int32, String)
    case invalidResponse
    case closed
    case busy

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(reason): "モジュールの設定が不正です: \(reason)"
        case let .loadFailed(reason): "モジュールを読み込めません: \(reason)"
        case let .missingSymbol(name): "モジュールの公開関数が見つかりません: \(name)"
        case let .unsupportedVersion(version): "未対応のモジュールAPIです: \(version)"
        case let .callFailed(code, reason): "モジュールの処理が失敗しました (\(code)): \(reason)"
        case .invalidResponse: "モジュールから不正な応答を受け取りました。"
        case .closed: "モジュールのセッションは終了しています。"
        case .busy: "モジュールのセッションは処理中です。"
        }
    }
}

private final class ModuleLibrary {
    typealias Version = @convention(c) () -> UInt32
    typealias Create = @convention(c) (UnsafePointer<UMConfig>?, UnsafePointer<UMHostV1>?, UnsafeMutablePointer<UInt64>?, UnsafeMutablePointer<UMBuffer>?) -> Int32
    typealias Request = @convention(c) (UInt64, UnsafePointer<UInt8>?, UInt32, UnsafeMutablePointer<UMBuffer>?) -> Int32
    typealias Destroy = @convention(c) (UInt64, UnsafeMutablePointer<UMBuffer>?) -> Int32
    typealias Discard = @convention(c) (UInt64) -> Int32
    typealias Release = @convention(c) (UnsafeMutablePointer<UMBuffer>?) -> Void

    let handle: UnsafeMutableRawPointer
    let create: Create
    let request: Request
    let destroy: Destroy
    let discard: Discard
    let release: Release

    init(url: URL) throws {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            throw UtataneModuleError.loadFailed(dlerror().map { String(cString: $0) } ?? url.path)
        }
        do {
            func symbol<T>(_ name: String, as _: T.Type) throws -> T {
                guard let pointer = dlsym(handle, name) else { throw UtataneModuleError.missingSymbol(name) }
                return unsafeBitCast(pointer, to: T.self)
            }
            let version = try symbol("um_api_version", as: Version.self)()
            guard version == UM_ABI_VERSION else { throw UtataneModuleError.unsupportedVersion(version) }
            create = try symbol("um_create", as: Create.self)
            request = try symbol("um_request", as: Request.self)
            destroy = try symbol("um_destroy", as: Destroy.self)
            discard = try symbol("um_discard", as: Discard.self)
            release = try symbol("um_release", as: Release.self)
            self.handle = handle
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit { dlclose(handle) }

    func take(_ buffer: inout UMBuffer, status: Int32) throws -> String {
        defer { release(&buffer) }
        guard buffer.length <= UM_MAX_BYTES, buffer.length == 0 || buffer.data != nil else {
            throw UtataneModuleError.invalidResponse
        }
        let value: String
        if buffer.length == 0 {
            value = ""
        } else if let decoded = String(bytes: UnsafeBufferPointer(start: buffer.data, count: Int(buffer.length)), encoding: .utf8),
                  !decoded.contains("\0")
        {
            value = decoded
        } else {
            throw UtataneModuleError.invalidResponse
        }
        guard status == UM_OK else { throw UtataneModuleError.callFailed(status, value) }
        return value
    }
}

/// A module violating the cleanup contract must not leave callbacks pointing at freed memory.
/// Retain only such failed foreign resources until process exit; ordinary closes never enter here.
private final class QuarantinedModules: @unchecked Sendable {
    static let shared = QuarantinedModules()
    private let lock = NSLock()
    private var entries: [(ModuleLibrary, UtataneModuleHostServices)] = []

    func retain(_ library: ModuleLibrary, _ host: UtataneModuleHostServices) {
        lock.withLock { entries.append((library, host)) }
    }
}

public final class UtataneModuleSession: @unchecked Sendable {
    private let lock = NSLock()
    private let library: ModuleLibrary
    private let host: UtataneModuleHostServices
    private var id: UInt64 = 0

    public init(moduleURL: URL, masterDirectoryURL: URL, variableStoreURL: URL,
                saoriCaller: any NativeSaoriCalling) throws
    {
        let paths = [masterDirectoryURL, variableStoreURL].map(\.standardizedFileURL.path)
        guard paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") && $0.utf8.count <= UM_MAX_BYTES }) else {
            throw UtataneModuleError.invalidConfiguration("Invalid master or state path")
        }
        library = try ModuleLibrary(url: moduleURL)
        host = UtataneModuleHostServices(caller: saoriCaller)
        var callbacks = UMHostV1(abi_version: UM_ABI_VERSION, struct_size: UInt32(MemoryLayout<UMHostV1>.size),
                                 context: Unmanaged.passUnretained(host).toOpaque(),
                                 saori: utataneModuleSaoriCallback, release: utataneModuleHostRelease)
        var error = UMBuffer()
        let status = Array(paths[0].utf8).withUnsafeBufferPointer { master in
            Array(paths[1].utf8).withUnsafeBufferPointer { state in
                var config = UMConfig(abi_version: UM_ABI_VERSION, struct_size: UInt32(MemoryLayout<UMConfig>.size),
                                      master_path: UMBytes(data: master.baseAddress, length: UInt32(master.count)),
                                      state_path: UMBytes(data: state.baseAddress, length: UInt32(state.count)))
                return library.create(&config, &callbacks, &id, &error)
            }
        }
        do {
            _ = try library.take(&error, status: status)
            guard id != 0 else { throw UtataneModuleError.invalidResponse }
        } catch {
            if id != 0 {
                let cleanup = library.discard(id)
                if cleanup != UM_OK, cleanup != UM_NOT_FOUND {
                    QuarantinedModules.shared.retain(library, host)
                }
                id = 0
            }
            host.unloadAll()
            throw error
        }
    }

    deinit {
        do { try close() }
        catch {
            NSLog("Utatane module save failed during cleanup: %@", error.localizedDescription)
            do { try discard() }
            catch {
                QuarantinedModules.shared.retain(library, host)
                NSLog("Utatane module refused cleanup: %@", error.localizedDescription)
            }
        }
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        guard lock.try() else { throw UtataneModuleError.busy }
        defer { lock.unlock() }
        guard id != 0 else { throw UtataneModuleError.closed }
        var headers = request.headers.entries.filter { $0.name.caseInsensitiveCompare("Charset") != .orderedSame }
        headers.append(ShioriHeader(name: "Charset", value: "UTF-8"))
        let wire = ShioriRequest(method: request.method, version: request.version, headers: ShioriHeaders(headers)).serialized()
        let bytes = Array(wire.utf8)
        guard bytes.count <= UM_MAX_BYTES else { throw UtataneModuleError.invalidConfiguration("Request too large") }
        var buffer = UMBuffer()
        let status = bytes.withUnsafeBufferPointer { library.request(id, $0.baseAddress, UInt32($0.count), &buffer) }
        let response = try ShioriMessageParser.parseResponse(library.take(&buffer, status: status))
        guard response.version == request.version,
              (response.headers["Charset"] ?? "UTF-8").uppercased() == "UTF-8"
        else {
            throw UtataneModuleError.invalidResponse
        }
        return response
    }

    /// Failure preserves the session so the caller can repair the state path and retry.
    public func close() throws {
        guard lock.try() else { throw UtataneModuleError.busy }
        defer { lock.unlock() }
        guard id != 0 else { return }
        var error = UMBuffer()
        let status = library.destroy(id, &error)
        // A successful destroy invalidates the ID even if its optional output is malformed.
        if status == UM_OK {
            id = 0; host.unloadAll()
        }
        _ = try library.take(&error, status: status)
    }

    /// Release the session without saving; used only after saving cannot be retried.
    public func discard() throws {
        guard lock.try() else { throw UtataneModuleError.busy }
        defer { lock.unlock() }
        guard id != 0 else { return }
        let status = library.discard(id)
        guard status == UM_OK || status == UM_NOT_FOUND else {
            throw UtataneModuleError.callFailed(status, "Session cleanup failed")
        }
        id = 0
        host.unloadAll()
    }
}

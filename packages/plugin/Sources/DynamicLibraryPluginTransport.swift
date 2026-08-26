#if canImport(Darwin)
    import Darwin
    import Foundation

    public enum DynamicLibraryPluginError: LocalizedError, Sendable {
        case loadFailed(URL, String)
        case missingEntryPoints
        case pluginLoadFailed
        case requestFailed
        case undecodableResponse

        public var errorDescription: String? {
            switch self {
            case let .loadFailed(url, reason): "プラグインdylibを読み込めませんでした: \(url.path): \(reason)"
            case .missingEntryPoints: "プラグインdylibにloadu/load、unload、requestがありません。"
            case .pluginLoadFailed: "プラグインdylibの初期化に失敗しました。"
            case .requestFailed: "プラグインdylibのrequest呼び出しに失敗しました。"
            case .undecodableResponse: "プラグインdylibの応答をUTF-8として読めませんでした。"
            }
        }
    }

    /// Loads the portable form of the conventional Ukagaka load/unload/request ABI.
    public final class DynamicLibraryPluginTransport: PluginTransport, @unchecked Sendable {
        private typealias StandardLoad = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        private typealias StandardUnload = @convention(c) () -> Int32
        private typealias StandardRequest = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?

        private let lock = NSLock()
        private let handle: UnsafeMutableRawPointer
        private let unloadImplementation: () -> Void
        private let requestImplementation: (String) throws -> String

        public init(plugin: InstalledPlugin) throws {
            guard case let .dynamicLibrary(moduleURL) = plugin.runtime else {
                throw DynamicLibraryPluginError.loadFailed(plugin.moduleURL, "dynamic libraryではありません")
            }
            guard let handle = dlopen(moduleURL.path, RTLD_NOW | RTLD_LOCAL) else {
                let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
                throw DynamicLibraryPluginError.loadFailed(moduleURL, reason)
            }
            do {
                guard let requestPointer = dlsym(handle, "request"),
                      let unloadPointer = dlsym(handle, "unload"),
                      let loadPointer = dlsym(handle, "loadu") ?? dlsym(handle, "load")
                else {
                    throw DynamicLibraryPluginError.missingEntryPoints
                }
                let load = unsafeBitCast(loadPointer, to: StandardLoad.self)
                let unload = unsafeBitCast(unloadPointer, to: StandardUnload.self)
                let request = unsafeBitCast(requestPointer, to: StandardRequest.self)
                let directory = try Self.transferredBuffer(plugin.directory.path)
                guard load(directory.pointer, directory.length) != 0 else {
                    throw DynamicLibraryPluginError.pluginLoadFailed
                }
                self.handle = handle
                unloadImplementation = { _ = unload() }
                requestImplementation = { message in
                    let input = try Self.transferredBuffer(message)
                    var length = input.length
                    guard let response = request(input.pointer, &length), length >= 0 else {
                        throw DynamicLibraryPluginError.requestFailed
                    }
                    defer { Darwin.free(response) }
                    let data = Data(bytes: response, count: Int(length))
                    guard let message = String(data: data, encoding: .utf8) else {
                        throw DynamicLibraryPluginError.undecodableResponse
                    }
                    return message
                }
            } catch {
                dlclose(handle)
                throw error
            }
        }

        deinit {
            lock.withLock {
                unloadImplementation()
                dlclose(handle)
            }
        }

        public func request(_ request: PluginRequest) async throws -> PluginResponse {
            try lock.withLock {
                try PluginResponse.parse(requestImplementation(request.serialized()))
            }
        }

        /// The conventional ABI transfers ownership of each input buffer to the module.
        private static func transferredBuffer(_ string: String) throws -> (pointer: UnsafeMutableRawPointer, length: Int32) {
            let bytes = Array(string.utf8)
            guard bytes.count <= Int(Int32.max), let pointer = malloc(max(bytes.count, 1)) else {
                throw DynamicLibraryPluginError.requestFailed
            }
            if !bytes.isEmpty {
                _ = bytes.withUnsafeBytes { source in
                    memcpy(pointer, source.baseAddress, bytes.count)
                }
            }
            return (pointer, Int32(bytes.count))
        }
    }
#endif

#if canImport(Darwin)
    import Darwin
    import Foundation

    public enum DynamicLibraryModuleError: LocalizedError, Sendable {
        case loadFailed(URL, String)
        case missingEntryPoints
        case pluginLoadFailed
        case requestFailed
        case undecodableResponse

        public var errorDescription: String? {
            switch self {
            case let .loadFailed(url, reason): "dylibを読み込めませんでした: \(url.path): \(reason)"
            case .missingEntryPoints: "dylibにloadu/load、unload、requestがありません。"
            case .pluginLoadFailed: "dylibの初期化に失敗しました。"
            case .requestFailed: "dylibのrequest呼び出しに失敗しました。"
            case .undecodableResponse: "dylibの応答をUTF-8として読めませんでした。"
            }
        }
    }

    /// Loads the portable form of the conventional Ukagaka load/unload/request ABI.
    public final class DynamicLibraryModuleSession: @unchecked Sendable {
        private typealias StandardLoad = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        private typealias StandardUnload = @convention(c) () -> Int32
        private typealias StandardRequest = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?

        private let lock = NSLock()
        private let handle: UnsafeMutableRawPointer
        private let unloadImplementation: () -> Void
        private let requestImplementation: (String) throws -> String

        public init(directoryURL: URL, moduleURL: URL) throws {
            guard let handle = dlopen(moduleURL.path, RTLD_NOW | RTLD_LOCAL) else {
                let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
                throw DynamicLibraryModuleError.loadFailed(moduleURL, reason)
            }
            do {
                guard let requestPointer = dlsym(handle, "request"),
                      let unloadPointer = dlsym(handle, "unload"),
                      let loadPointer = dlsym(handle, "loadu") ?? dlsym(handle, "load")
                else {
                    throw DynamicLibraryModuleError.missingEntryPoints
                }
                let load = unsafeBitCast(loadPointer, to: StandardLoad.self)
                let unload = unsafeBitCast(unloadPointer, to: StandardUnload.self)
                let request = unsafeBitCast(requestPointer, to: StandardRequest.self)
                let directory = try Self.transferredBuffer(directoryURL.path)
                guard load(directory.pointer, directory.length) != 0 else {
                    throw DynamicLibraryModuleError.pluginLoadFailed
                }
                self.handle = handle
                unloadImplementation = { _ = unload() }
                requestImplementation = { message in
                    let input = try Self.transferredBuffer(message)
                    var length = input.length
                    guard let response = request(input.pointer, &length), length >= 0 else {
                        throw DynamicLibraryModuleError.requestFailed
                    }
                    defer { Darwin.free(response) }
                    let data = Data(bytes: response, count: Int(length))
                    guard let message = String(data: data, encoding: .utf8) else {
                        throw DynamicLibraryModuleError.undecodableResponse
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

        public func request(_ request: String) throws -> String {
            try lock.withLock {
                try requestImplementation(request)
            }
        }

        /// The conventional ABI transfers ownership of each input buffer to the module.
        private static func transferredBuffer(_ string: String) throws -> (pointer: UnsafeMutableRawPointer, length: Int32) {
            let bytes = Array(string.utf8)
            guard bytes.count <= Int(Int32.max), let pointer = malloc(max(bytes.count, 1)) else {
                throw DynamicLibraryModuleError.requestFailed
            }
            if !bytes.isEmpty {
                _ = bytes.withUnsafeBytes { source in
                    memcpy(pointer, source.baseAddress, bytes.count)
                }
            }
            return (pointer, Int32(bytes.count))
        }
    }

    public final class DynamicLibraryPluginTransport: PluginTransport, @unchecked Sendable {
        private let session: DynamicLibraryModuleSession

        public init(plugin: InstalledPlugin) throws {
            guard case let .dynamicLibrary(moduleURL) = plugin.runtime else {
                throw DynamicLibraryModuleError.loadFailed(plugin.moduleURL, "dynamic libraryではありません")
            }
            session = try DynamicLibraryModuleSession(directoryURL: plugin.directory, moduleURL: moduleURL)
        }

        public func request(_ request: PluginRequest) async throws -> PluginResponse {
            try PluginResponse.parse(session.request(request.serialized()))
        }
    }
#endif

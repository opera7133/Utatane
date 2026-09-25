#if canImport(Darwin)
    import Darwin
    import Foundation
    import UtataneCore
    import UtataneNativeSaori
    import UtataneShiori

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
        private let directoryURL: URL
        private let image: UtataneModuleImage
        private let unloadImplementation: () throws -> Void
        private let requestImplementation: (String) throws -> String
        private var closed = false

        public static func open(directoryURL: URL, moduleURL: URL, variableStoreURL: URL? = nil,
                                saoriCaller: (any NativeSaoriCalling)? = nil,
                                moduleResolver: UtataneModuleResolver = .init()) throws -> DynamicLibraryModuleSession
        {
            // A renamed or unknown module cannot safely be identified by its dictionary alone.
            let isMisaka = moduleURL.lastPathComponent == "libmisaka.dylib"
                && FileManager.default.fileExists(atPath: directoryURL.appending(path: "misaka.ini").path)
            return try ShioriModuleRecovery.load(
                preferred: moduleURL,
                fallback: isMisaka ? moduleResolver.misakaFallbackURL(for: moduleURL, masterDirectoryURL: directoryURL) : nil,
                canRecover: { error in
                    if let error = error as? UtataneModuleError {
                        return error.canRecoverByLoadingAnotherModule
                    }
                    if case DynamicLibraryModuleError.missingEntryPoints = error {
                        return true
                    }
                    return false
                }
            ) { url in
                try DynamicLibraryModuleSession(directoryURL: directoryURL, moduleURL: url,
                                                variableStoreURL: variableStoreURL, saoriCaller: saoriCaller)
            }
        }

        public init(directoryURL: URL, moduleURL: URL, variableStoreURL: URL? = nil,
                    saoriCaller: (any NativeSaoriCalling)? = nil) throws
        {
            let image = try UtataneModuleImage.open(moduleURL)
            let handle = image.handle
            // Optional bridge for independent sessions and host services. Ordinary
            // SHIORI libraries only need the conventional entry points below.
            if let variableStoreURL, dlsym(handle, "um_api_version") != nil {
                let session = try UtataneModuleSession(
                    moduleURL: moduleURL, masterDirectoryURL: directoryURL,
                    variableStoreURL: variableStoreURL,
                    saoriCaller: saoriCaller ?? NativeSaoriRegistry(baseDirectoryURL: directoryURL)
                )
                self.directoryURL = directoryURL
                self.image = image
                unloadImplementation = { try session.close() }
                requestImplementation = { message in
                    try session.request(ShioriMessageParser.parseRequest(message)).serialized()
                }
                return
            }
            guard let requestPointer = dlsym(handle, "request"),
                  let unloadPointer = dlsym(handle, "unload"),
                  let loadPointer = dlsym(handle, "loadu") ?? dlsym(handle, "load")
            else {
                throw DynamicLibraryModuleError.missingEntryPoints
            }
            let load = unsafeBitCast(loadPointer, to: StandardLoad.self)
            let unload = unsafeBitCast(unloadPointer, to: StandardUnload.self)
            let request = unsafeBitCast(requestPointer, to: StandardRequest.self)
            try ProcessWorkingDirectory.withDirectory(directoryURL) {
                let directory = try Self.transferredBuffer(directoryURL.path)
                guard load(directory.pointer, directory.length) != 0 else {
                    throw DynamicLibraryModuleError.pluginLoadFailed
                }
            }
            self.directoryURL = directoryURL
            self.image = image
            unloadImplementation = {
                guard unload() != 0 else { throw DynamicLibraryModuleError.requestFailed }
            }
            requestImplementation = { message in
                let input = try Self.transferredBuffer(message)
                var length = input.length
                guard let response = request(input.pointer, &length) else {
                    throw DynamicLibraryModuleError.requestFailed
                }
                defer { Darwin.free(response) }
                guard length >= 0, length <= 8 * 1024 * 1024 else {
                    throw DynamicLibraryModuleError.requestFailed
                }
                let data = Data(bytes: response, count: Int(length))
                guard let message = String(data: data, encoding: .utf8) else {
                    throw DynamicLibraryModuleError.undecodableResponse
                }
                return message
            }
        }

        deinit {
            try? close()
        }

        public func request(_ request: String) throws -> String {
            guard lock.try() else { throw DynamicLibraryModuleError.requestFailed }
            defer { lock.unlock() }
            guard !closed else { throw DynamicLibraryModuleError.requestFailed }
            return try ProcessWorkingDirectory.withDirectory(directoryURL) {
                try requestImplementation(request)
            }
        }

        public func close() throws {
            guard lock.try() else { throw DynamicLibraryModuleError.requestFailed }
            defer { lock.unlock() }
            guard !closed else { return }
            try ProcessWorkingDirectory.withDirectory(directoryURL) {
                try unloadImplementation()
            }
            closed = true
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

#endif

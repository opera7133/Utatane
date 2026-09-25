import CryptoKit
import Darwin
import Foundation

/// Swift dylibs register types for the lifetime of the process. Copies of the same
/// MISAKA build must share one image, while their sessions remain independent.
public final class UtataneModuleImage: @unchecked Sendable {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var digest: SHA256.Digest?
        var image: UtataneModuleImage?
    }

    private static let cache = Cache()
    public let handle: UnsafeMutableRawPointer

    public static func isMisakaLibrary(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return data.range(of: Data("\0_utatane_misaka_bridge\0".utf8)) != nil
    }

    public static func open(_ url: URL) throws -> UtataneModuleImage {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw UtataneModuleError.loadFailed(error.localizedDescription) }
        // dyld may return an already loaded image for a replaced path. Reject an
        // invalid on-disk file before consulting it, rather than running stale code.
        let magic = Array(data.prefix(4))
        let supported: [[UInt8]] = [
            [0xCF, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF],
            [0xCE, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCE],
            [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA],
            [0xCA, 0xFE, 0xBA, 0xBF], [0xBF, 0xBA, 0xFE, 0xCA]
        ]
        guard supported.contains(magic) else { throw UtataneModuleError.loadFailed("Invalid Mach-O library: \(url.path)") }
        let marker = Data("\0_utatane_misaka_bridge\0".utf8)
        guard data.range(of: marker) != nil else { return try UtataneModuleImage(url) }
        let digest = SHA256.hash(data: data)
        return try cache.lock.withLock {
            if let image = cache.image {
                guard cache.digest == digest else {
                    throw UtataneModuleError.loadFailed("異なる版の美坂が読み込まれています。Utataneを再起動してから切り替えてください。")
                }
                return image
            }
            let image = try UtataneModuleImage(url)
            guard dlsym(image.handle, "utatane_misaka_bridge") != nil else {
                throw UtataneModuleError.missingSymbol("utatane_misaka_bridge")
            }
            cache.digest = digest
            cache.image = image
            return image
        }
    }

    private init(_ url: URL) throws {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            throw UtataneModuleError.loadFailed(dlerror().map { String(cString: $0) } ?? url.path)
        }
        self.handle = handle
    }

    deinit { dlclose(handle) }
}

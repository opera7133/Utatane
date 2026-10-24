import CryptoKit
import Darwin
import Foundation

/// Incremental hashing keeps file contents out of the protocol and out of a
/// single large allocation. File paths are resolved by the owning service.
enum InternalSaoriCrypto {
    typealias Failure = InternalSaoriService.Failure
    enum Input {
        case bytes(Data)
        case file(URL)

        func consume(isCancelled: () -> Bool, _ update: (Data) -> Void) throws {
            switch self {
            case let .bytes(data):
                guard !isCancelled() else { throw Failure("ghost required") }
                update(data)
            case let .file(url):
                // Nonblocking open + fstat rejects FIFOs and directories without
                // hanging, even if the path changes after resolution.
                let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                guard descriptor >= 0 else {
                    if errno == ENOENT || errno == ENOTDIR {
                        throw Failure("file not found")
                    }
                    throw Failure("file read failed", status: 500)
                }
                defer { Darwin.close(descriptor) }
                var attributes = stat()
                guard fstat(descriptor, &attributes) == 0 else { throw Failure("file read failed", status: 500) }
                guard attributes.st_mode & S_IFMT == S_IFREG else { throw Failure("file not found") }
                var remaining = attributes.st_size
                var buffer = [UInt8](repeating: 0, count: 65536)
                while remaining > 0 {
                    guard !isCancelled() else { throw Failure("ghost required") }
                    let count = buffer.withUnsafeMutableBytes { bytes in
                        Darwin.read(descriptor, bytes.baseAddress, min(bytes.count, Int(min(remaining, 65536))))
                    }
                    if count < 0, errno == EINTR {
                        continue
                    }
                    guard count > 0 else { throw Failure("file read failed", status: 500) }
                    update(Data(buffer.prefix(count)))
                    remaining -= off_t(count)
                }
                guard !isCancelled() else { throw Failure("ghost required") }
                var final = stat()
                guard fstat(descriptor, &final) == 0, final.st_size == attributes.st_size,
                      final.st_mtimespec.tv_sec == attributes.st_mtimespec.tv_sec,
                      final.st_mtimespec.tv_nsec == attributes.st_mtimespec.tv_nsec
                else { throw Failure("file read failed", status: 500) }
            }
        }
    }

    static func calculate(function: String, algorithm: String, input: Input, key: Data, isCancelled: () -> Bool) throws -> Data {
        switch (function, algorithm) {
        case ("Digest", "md5"): try digest(Insecure.MD5.self, input: input, isCancelled: isCancelled)
        case ("Digest", "sha1"): try digest(Insecure.SHA1.self, input: input, isCancelled: isCancelled)
        case ("Digest", "sha256"): try digest(SHA256.self, input: input, isCancelled: isCancelled)
        case ("Digest", "sha384"): try digest(SHA384.self, input: input, isCancelled: isCancelled)
        case ("Digest", "sha512"): try digest(SHA512.self, input: input, isCancelled: isCancelled)
        case ("HMAC", "sha256"): try hmac(SHA256.self, input: input, key: key, isCancelled: isCancelled)
        case ("HMAC", "sha384"): try hmac(SHA384.self, input: input, key: key, isCancelled: isCancelled)
        case ("HMAC", "sha512"): try hmac(SHA512.self, input: input, key: key, isCancelled: isCancelled)
        default: throw Failure("unsupported algorithm")
        }
    }

    static func compare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        if a.isEmpty {
            return true
        }
        return a.withUnsafeBytes { first in
            b.withUnsafeBytes { second in
                timingsafe_bcmp(first.baseAddress, second.baseAddress, first.count) == 0
            }
        }
    }

    private static func digest<H: HashFunction>(_ type: H.Type, input: Input, isCancelled: () -> Bool) throws -> Data {
        var hash = H()
        try input.consume(isCancelled: isCancelled) { hash.update(data: $0) }
        return Data(hash.finalize())
    }

    private static func hmac<H: HashFunction>(_ type: H.Type, input: Input, key: Data, isCancelled: () -> Bool) throws -> Data {
        var mac = HMAC<H>(key: SymmetricKey(data: key))
        try input.consume(isCancelled: isCancelled) { mac.update(data: $0) }
        return Data(mac.finalize())
    }
}

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import Foundation

public enum ProcessWorkingDirectoryError: LocalizedError, Sendable {
    case cannotSave(Int32)
    case cannotChange(URL, Int32)
    case cannotRestore(Int32)

    public var errorDescription: String? {
        switch self {
        case let .cannotSave(code):
            "現在の作業ディレクトリを保持できなかった: errno \(code)"
        case let .cannotChange(url, code):
            "作業ディレクトリを変更できなかった: \(url.path) (errno \(code))"
        case let .cannotRestore(code):
            "元の作業ディレクトリへ戻せなかった: errno \(code)"
        }
    }
}

/// Serializes temporary changes to the process-wide current working directory.
public enum ProcessWorkingDirectory {
    private static let lock = NSRecursiveLock()

    public static func withDirectory<Result>(
        _ directoryURL: URL,
        body: () throws -> Result
    ) throws -> Result {
        try lock.withLock {
            let originalDirectory = open(".", O_RDONLY | O_CLOEXEC)
            guard originalDirectory >= 0 else {
                throw ProcessWorkingDirectoryError.cannotSave(errno)
            }

            let changed = directoryURL.withUnsafeFileSystemRepresentation { path in
                guard let path else { return false }
                return chdir(path) == 0
            }
            guard changed else {
                let code = errno
                close(originalDirectory)
                throw ProcessWorkingDirectoryError.cannotChange(directoryURL, code)
            }

            let result: Swift.Result<Result, any Error>
            do {
                result = try .success(body())
            } catch {
                result = .failure(error)
            }

            guard fchdir(originalDirectory) == 0 else {
                let code = errno
                close(originalDirectory)
                throw ProcessWorkingDirectoryError.cannotRestore(code)
            }
            close(originalDirectory)
            return try result.get()
        }
    }
}

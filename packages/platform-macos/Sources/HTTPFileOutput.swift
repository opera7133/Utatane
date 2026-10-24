import Darwin
import Foundation

/// A visible partial file with rollback. Reject overlapping writers to an
/// explicit output path; automatically named requests already have unique paths.
final class HTTPFileOutput {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var active: Set<String> = []
    private let destination: URL
    private let key: String
    private let backup: URL
    private let handle: FileHandle
    private let inode: UInt64
    private var finished = false
    init(_ destination: URL) throws {
        self.destination = destination
        let outputKey = destination.resolvingSymlinksInPath().standardizedFileURL.path
        key = outputKey
        backup = destination.deletingLastPathComponent().appending(path: ".http-backup-\(UUID())")
        guard Self.lock.withLock({ Self.active.insert(outputKey).inserted }) else { throw CocoaError(.fileWriteFileExists) }
        var moved = false
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileWriteInvalidFileName) }
                try FileManager.default.moveItem(at: destination, to: backup); moved = true
            }
            let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
            var information = stat()
            guard fstat(fd, &information) == 0 else {
                Darwin.close(fd)
                try? FileManager.default.removeItem(at: destination)
                throw CocoaError(.fileWriteUnknown)
            }
            inode = UInt64(information.st_ino)
            handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        } catch {
            if moved, !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            _ = Self.lock.withLock { Self.active.remove(outputKey) }
            throw error
        }
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func commit() throws {
        try handle.close()
        finished = true
        try? FileManager.default.removeItem(at: backup)
        _ = Self.lock.withLock { Self.active.remove(key) }
    }

    deinit {
        guard !finished else { return }
        try? handle.close()
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        if (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value == inode {
            try? FileManager.default.removeItem(at: destination)
        }
        if FileManager.default.fileExists(atPath: backup.path), !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.moveItem(at: backup, to: destination)
        }
        _ = Self.lock.withLock { Self.active.remove(key) }
    }
}

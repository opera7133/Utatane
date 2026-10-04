import Foundation

/// Preserve the existing variable files before this app first opens YAYA 6.
enum YayaSaveBackup {
    static func prepare(in directory: URL) throws {
        let manager = FileManager.default
        let backup = directory.appending(path: "Utatane-YAYA-backup", directoryHint: .isDirectory)
        if manager.fileExists(atPath: backup.path) {
            let values = try backup.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadInvalidFileName, userInfo: [NSFilePathErrorKey: backup.path])
            }
            return
        }
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.lastPathComponent.hasSuffix("_variable.cfg") }
        let temporary = directory.appending(path: ".utatane-yaya-backup-\(UUID())", directoryHint: .isDirectory)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: temporary) }
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadInvalidFileName, userInfo: [NSFilePathErrorKey: file.path])
            }
            try manager.copyItem(at: file, to: temporary.appending(path: file.lastPathComponent))
        }
        try manager.moveItem(at: temporary, to: backup)
    }
}

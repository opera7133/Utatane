import Foundation

public struct BundledContentInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func install(
        from bundledRoot: URL,
        ghostsDirectory: URL,
        balloonsDirectory: URL
    ) throws {
        try installDirectories(
            from: bundledRoot.appending(path: "Ghosts", directoryHint: .isDirectory),
            to: ghostsDirectory
        )
        try installDirectories(
            from: bundledRoot.appending(path: "Balloons", directoryHint: .isDirectory),
            to: balloonsDirectory
        )
    }

    private func installDirectories(from sourceRoot: URL, to destinationRoot: URL) throws {
        guard fileManager.fileExists(atPath: sourceRoot.path) else { return }
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sources = try fileManager.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for source in sources {
            guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            let destination = destinationRoot.appending(
                path: source.lastPathComponent,
                directoryHint: .isDirectory
            )
            guard !fileManager.fileExists(atPath: destination.path) else { continue }

            let staging = destinationRoot.appending(
                path: ".utatane-bundled-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            defer { try? fileManager.removeItem(at: staging) }
            try fileManager.copyItem(at: source, to: staging)
            try fileManager.moveItem(at: staging, to: destination)
        }
    }
}

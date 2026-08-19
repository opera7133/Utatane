import Foundation

public struct SSPImportResult: Sendable, Equatable {
    public let ghostDirectories: [URL]
    public let balloonDirectories: [URL]

    public var importedItemCount: Int {
        ghostDirectories.count + balloonDirectories.count
    }

    public init(ghostDirectories: [URL], balloonDirectories: [URL]) {
        self.ghostDirectories = ghostDirectories
        self.balloonDirectories = balloonDirectories
    }
}

public enum SSPContentImportError: LocalizedError, Equatable {
    case missingContentDirectories
    case noContent
    case unsafeItem(URL)
    case destinationExists(URL)

    public var errorDescription: String? {
        switch self {
        case .missingContentDirectories:
            "選択したフォルダにghostまたはballoonフォルダが見つからない"
        case .noContent:
            "取り込めるゴーストまたはバルーンが見つからない"
        case let .unsafeItem(url):
            "安全でないファイルが含まれている: \(url.lastPathComponent)"
        case let .destinationExists(url):
            "同名のコンテンツが既にある: \(url.lastPathComponent)"
        }
    }
}

public struct SSPContentImporter: Sendable {
    public init() {}

    public func importContents(
        from sspDirectory: URL,
        ghostsDirectory: URL,
        balloonsDirectory: URL
    ) throws -> SSPImportResult {
        let fileManager = FileManager.default
        let sourceRoot = try resolvedSourceRoot(at: sspDirectory)
        let ghostSource = child(named: "ghost", in: sourceRoot)
        let balloonSource = child(named: "balloon", in: sourceRoot)
        guard ghostSource != nil || balloonSource != nil else {
            throw SSPContentImportError.missingContentDirectories
        }

        let ghosts = try contentDirectories(in: ghostSource).filter(isGhostPackage)
        let balloons = try contentDirectories(in: balloonSource)
        guard !ghosts.isEmpty || !balloons.isEmpty else {
            throw SSPContentImportError.noContent
        }

        let operations = ghosts.map {
            ($0, ghostsDirectory.appending(path: $0.lastPathComponent, directoryHint: .isDirectory))
        } + balloons.map {
            ($0, balloonsDirectory.appending(path: $0.lastPathComponent, directoryHint: .isDirectory))
        }
        for (source, destination) in operations {
            try validateTree(at: source)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw SSPContentImportError.destinationExists(destination)
            }
        }

        var installed: [URL] = []
        do {
            for (source, destination) in operations {
                try installCopy(from: source, to: destination)
                installed.append(destination)
            }
        } catch {
            for url in installed {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }

        return SSPImportResult(
            ghostDirectories: Array(installed.prefix(ghosts.count)),
            balloonDirectories: Array(installed.dropFirst(ghosts.count))
        )
    }

    private func resolvedSourceRoot(at selectedDirectory: URL) throws -> URL {
        if child(named: "ghost", in: selectedDirectory) != nil
            || child(named: "balloon", in: selectedDirectory) != nil
        {
            return selectedDirectory
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: selectedDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if children.count == 1, let onlyChild = children.first,
           child(named: "ghost", in: onlyChild) != nil || child(named: "balloon", in: onlyChild) != nil
        {
            return onlyChild
        }
        return selectedDirectory
    }

    private func child(named name: String, in directory: URL) -> URL? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return children.first {
            $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func contentDirectories(in directory: URL?) throws -> [URL] {
        guard let directory else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw SSPContentImportError.unsafeItem(url)
            }
            return values.isDirectory == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func validateTree(at root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { throw SSPContentImportError.unsafeItem(root) }
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw SSPContentImportError.unsafeItem(url)
            }
        }
    }

    private func isGhostPackage(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(
            path: "ghost/master/descript.txt",
            directoryHint: .notDirectory
        ).path)
    }

    private func installCopy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(
            path: ".utatane-importing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: source, to: staging)
        try fileManager.moveItem(at: staging, to: destination)
    }
}

import Foundation

public enum NarContentType: String, Sendable, Equatable {
    case ghost
    case balloon
    case shell
    case headline
    case package
}

public struct NarInstallationRoots: Sendable, Equatable {
    public let ghostsDirectory: URL
    public let balloonsDirectory: URL
    public let headlinesDirectory: URL

    public init(ghostsDirectory: URL, balloonsDirectory: URL, headlinesDirectory: URL? = nil) {
        self.ghostsDirectory = ghostsDirectory
        self.balloonsDirectory = balloonsDirectory
        self.headlinesDirectory = headlinesDirectory ?? ghostsDirectory.deletingLastPathComponent().appending(
            path: "Headline", directoryHint: .isDirectory
        )
    }
}

public struct NarInstallResult: Sendable, Equatable {
    public let primaryType: NarContentType
    public let items: [NarInstalledItem]
    public let acceptedGhostName: String?
    public let bootGhostDirectory: String?

    public var installedURLs: [URL] {
        items.map(\.url)
    }

    public init(
        primaryType: NarContentType,
        items: [NarInstalledItem],
        acceptedGhostName: String? = nil,
        bootGhostDirectory: String? = nil
    ) {
        self.primaryType = primaryType
        self.items = items
        self.acceptedGhostName = acceptedGhostName
        self.bootGhostDirectory = bootGhostDirectory
    }
}

public struct NarInstalledItem: Sendable, Equatable {
    public let type: NarContentType
    public let name: String
    public let url: URL

    public init(type: NarContentType, name: String, url: URL) {
        self.type = type
        self.name = name
        self.url = url
    }
}

public enum NarInstallError: LocalizedError, Equatable {
    case missingArchive(URL)
    case archiveTooLarge
    case unreadableArchive
    case unsafeEntry(String)
    case tooManyEntries
    case extractedContentTooLarge
    case symbolicLink(URL)
    case missingInstallFile
    case ambiguousInstallFile
    case unsupportedTextEncoding(URL)
    case unsupportedType(String)
    case invalidDirectoryName(String)
    case missingSourceDirectory(String)
    case shellRequiresGhost
    case destinationExists(URL)
    case refused(accept: String, type: String, name: String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .missingArchive(url): "NARが見つからない: \(url.path)"
        case .archiveTooLarge: "NARの圧縮サイズが上限を超えている"
        case .unreadableArchive: "NARの内容を読み取れない"
        case let .unsafeEntry(name): "安全でないアーカイブ内パス: \(name)"
        case .tooManyEntries: "NAR内のファイル数が上限を超えている"
        case .extractedContentTooLarge: "展開後のサイズが上限を超えている"
        case let .symbolicLink(url): "シンボリックリンクはインストールできない: \(url.path)"
        case .missingInstallFile: "install.txtが見つからない"
        case .ambiguousInstallFile: "インストール元を一意に決められない"
        case let .unsupportedTextEncoding(url): "文字コードを判定できない: \(url.path)"
        case let .unsupportedType(type): "未対応のNAR種別: \(type)"
        case let .invalidDirectoryName(name): "不正なインストール先ディレクトリ名: \(name)"
        case let .missingSourceDirectory(name): "同梱コンテンツが見つからない: \(name)"
        case .shellRequiresGhost: "Shellのインストール先ゴーストが選択されていない"
        case let .destinationExists(url): "同名のコンテンツが既にある: \(url.path)"
        case let .refused(accept, _, _): "このNARは起動中の「\(accept)」用に指定されている"
        case let .commandFailed(message): "NARの展開に失敗した: \(message)"
        }
    }
}

public struct NarInstaller: Sendable {
    private struct InstallOperation {
        let source: URL
        let destination: URL
        let type: NarContentType
        let name: String
        let refreshes: Bool
        let undeleteMask: Set<String>
    }

    private let maximumArchiveBytes: Int
    private let maximumExtractedBytes: Int
    private let maximumEntryCount: Int

    public init(
        maximumArchiveBytes: Int = 512 * 1024 * 1024,
        maximumExtractedBytes: Int = 1024 * 1024 * 1024,
        maximumEntryCount: Int = 20000
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumExtractedBytes = maximumExtractedBytes
        self.maximumEntryCount = maximumEntryCount
    }

    public func install(
        archiveURL: URL,
        roots: NarInstallationRoots,
        selectedGhostDirectory: URL? = nil,
        activeGhostDirectories: [String: URL] = [:]
    ) throws -> NarInstallResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw NarInstallError.missingArchive(archiveURL)
        }
        let archiveSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard archiveSize <= maximumArchiveBytes else { throw NarInstallError.archiveTooLarge }

        let entries = try archiveEntries(at: archiveURL)
        try validate(entries: entries)
        try validateArchiveEntryTypes(at: archiveURL)

        let extractionRoot = fileManager.temporaryDirectory.appending(
            path: "utatane-nar-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionRoot) }

        try run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", "--norsrc", archiveURL.path, extractionRoot.path]
        )
        try validateExtractedTree(at: extractionRoot)

        let installURL = try primaryInstallFile(in: extractionRoot)
        let metadata = try readInstallMetadata(from: installURL)
        guard let rawType = metadata["type"], let contentType = NarContentType(rawValue: rawType.lowercased()) else {
            throw NarInstallError.unsupportedType(metadata["type"] ?? "")
        }
        let sourceRoot = installURL.deletingLastPathComponent()
        var operations: [InstallOperation] = []
        var acceptedGhostName: String?
        var bootGhostDirectory: String?
        if contentType == .package {
            if let bootGhost = metadata["bootghost"] {
                bootGhostDirectory = try validatedDirectoryName(bootGhost)
            }
            let childInstallFiles = try installFiles(in: sourceRoot).filter { $0 != installURL }
            guard !childInstallFiles.isEmpty else { throw NarInstallError.missingInstallFile }
            for childInstallURL in childInstallFiles.sorted(by: { $0.path < $1.path }) {
                let childMetadata = try readInstallMetadata(from: childInstallURL)
                let child = try installationOperations(
                    metadata: childMetadata,
                    sourceRoot: childInstallURL.deletingLastPathComponent(),
                    roots: roots,
                    selectedGhostDirectory: selectedGhostDirectory,
                    activeGhostDirectories: activeGhostDirectories
                )
                operations.append(contentsOf: child.operations)
                acceptedGhostName = acceptedGhostName ?? child.acceptedGhostName
            }
        } else {
            let primary = try installationOperations(
                metadata: metadata,
                sourceRoot: sourceRoot,
                roots: roots,
                selectedGhostDirectory: selectedGhostDirectory,
                activeGhostDirectories: activeGhostDirectories
            )
            operations = primary.operations
            acceptedGhostName = primary.acceptedGhostName
        }

        for operation in operations
            where fileManager.fileExists(atPath: operation.destination.path) && !operation.refreshes
        {
            throw NarInstallError.destinationExists(operation.destination)
        }

        var installedURLs: [URL] = []
        var backups: [(destination: URL, backup: URL)] = []
        do {
            for operation in operations {
                if let backup = try installCopy(
                    from: operation.source,
                    to: operation.destination,
                    refreshes: operation.refreshes,
                    undeleteMask: operation.undeleteMask
                ) {
                    backups.append((operation.destination, backup))
                }
                installedURLs.append(operation.destination)
            }
            for record in backups {
                try? fileManager.removeItem(at: record.backup)
            }
        } catch {
            for url in installedURLs.reversed() {
                try? fileManager.removeItem(at: url)
                if let record = backups.first(where: { $0.destination == url }) {
                    try? fileManager.moveItem(at: record.backup, to: record.destination)
                }
            }
            throw error
        }
        return NarInstallResult(
            primaryType: contentType,
            items: zip(operations, installedURLs).map { operation, url in
                NarInstalledItem(type: operation.type, name: operation.name, url: url)
            },
            acceptedGhostName: acceptedGhostName,
            bootGhostDirectory: bootGhostDirectory
        )
    }

    func validate(entries: [String]) throws {
        guard entries.count <= maximumEntryCount else { throw NarInstallError.tooManyEntries }
        for entry in entries {
            guard !entry.isEmpty,
                  entry.utf8.count <= 1024,
                  !entry.contains("\\"),
                  !entry.hasPrefix("/"),
                  !entry.contains("\0")
            else { throw NarInstallError.unsafeEntry(entry) }
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0 == ".." || $0 == "." }) else {
                throw NarInstallError.unsafeEntry(entry)
            }
        }
    }

    private func archiveEntries(at archiveURL: URL) throws -> [String] {
        let output = try run(
            executable: "/usr/bin/unzip",
            arguments: ["-Z1", archiveURL.path],
            capturesOutput: true
        )
        guard let listing = String(data: output, encoding: .utf8)
            ?? String(data: output, encoding: .shiftJIS)
        else { throw NarInstallError.unreadableArchive }
        return listing.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func validateArchiveEntryTypes(at archiveURL: URL) throws {
        let output = try run(
            executable: "/usr/bin/unzip",
            arguments: ["-Z", "-l", archiveURL.path],
            capturesOutput: true
        )
        guard let listing = String(data: output, encoding: .utf8)
            ?? String(data: output, encoding: .shiftJIS)
        else { throw NarInstallError.unreadableArchive }
        for line in listing.components(separatedBy: .newlines) where line.count >= 10 {
            let mode = line.prefix(10)
            guard mode.dropFirst().allSatisfy({ "rwxstST-".contains($0) }) else { continue }
            guard let type = mode.first, type == "-" || type == "d" else {
                throw NarInstallError.unsafeEntry("symbolic link or special file")
            }
        }
    }

    private func validateExtractedTree(at root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
            options: []
        ) else { throw NarInstallError.unreadableArchive }
        var totalBytes = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                throw NarInstallError.symbolicLink(url)
            }
            if values.isRegularFile == true {
                totalBytes += values.fileSize ?? 0
                guard totalBytes <= maximumExtractedBytes else {
                    throw NarInstallError.extractedContentTooLarge
                }
            }
        }
    }

    private func primaryInstallFile(in root: URL) throws -> URL {
        let candidates = try installFiles(in: root)
        guard !candidates.isEmpty else { throw NarInstallError.missingInstallFile }
        let depths = candidates.map { ($0, $0.pathComponents.count) }
        guard let minimumDepth = depths.map(\.1).min() else { throw NarInstallError.missingInstallFile }
        let shallowest = depths.filter { $0.1 == minimumDepth }.map(\.0)
        guard shallowest.count == 1, let installURL = shallowest.first else {
            throw NarInstallError.ambiguousInstallFile
        }
        return installURL
    }

    private func installFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw NarInstallError.missingInstallFile }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent.caseInsensitiveCompare("install.txt") == .orderedSame
            else { return nil }
            return url
        }
    }

    public func readInstallMetadata(from url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else { throw NarInstallError.unsupportedTextEncoding(url) }
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), let separator = line.firstIndex(of: ",") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return values
    }

    private func validatedDirectoryName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0")
        else { throw NarInstallError.invalidDirectoryName(name) }
        return trimmed
    }

    private func refreshUndeleteMask(_ value: String?) -> Set<String> {
        Set(value?.split(separator: ":").map(String.init).filter { !$0.isEmpty } ?? [])
    }

    private func installationOperations(
        metadata: [String: String],
        sourceRoot: URL,
        roots: NarInstallationRoots,
        selectedGhostDirectory: URL?,
        activeGhostDirectories: [String: URL]
    ) throws -> (operations: [InstallOperation], acceptedGhostName: String?) {
        let fileManager = FileManager.default
        guard let rawType = metadata["type"], let contentType = NarContentType(rawValue: rawType.lowercased()),
              contentType != .package
        else { throw NarInstallError.unsupportedType(metadata["type"] ?? "") }
        let directoryName = try validatedDirectoryName(metadata["directory"] ?? "")
        let primaryName = metadata["name"] ?? directoryName
        let refreshes = metadata["refresh"] == "1"
        let undeleteMask = refreshUndeleteMask(metadata["refreshundeletemask"])
        let acceptedGhostName = metadata["accept"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedGhostDirectory = acceptedGhostName.flatMap { acceptedName in
            activeGhostDirectories.first {
                $0.key.caseInsensitiveCompare(acceptedName) == .orderedSame
            }?.value
        }
        if let acceptedGhostName, !acceptedGhostName.isEmpty, acceptedGhostDirectory == nil {
            throw NarInstallError.refused(accept: acceptedGhostName, type: contentType.rawValue, name: primaryName)
        }

        var operations: [InstallOperation] = []
        func appendBundledOperations() throws {
            for key in metadata.keys.sorted() where key.hasSuffix(".directory") && !key.hasSuffix(".source.directory") {
                let identifier = String(key.dropLast(".directory".count))
                let type: NarContentType
                if identifier.hasPrefix("balloon"), identifier.dropFirst("balloon".count).allSatisfy(\.isNumber) {
                    type = .balloon
                } else if identifier.hasPrefix("headline"), identifier.dropFirst("headline".count).allSatisfy(\.isNumber) {
                    type = .headline
                } else {
                    continue
                }
                guard let destinationName = metadata[key] else { continue }
                let safeDestinationName = try validatedDirectoryName(destinationName)
                let sourceName = metadata["\(identifier).source.directory"] ?? safeDestinationName
                let safeSourceName = try validatedDirectoryName(sourceName)
                let bundledSource = sourceRoot.appending(path: safeSourceName, directoryHint: .isDirectory)
                guard fileManager.fileExists(atPath: bundledSource.path) else {
                    throw NarInstallError.missingSourceDirectory(safeSourceName)
                }
                let destinationRoot = type == .balloon ? roots.balloonsDirectory : roots.headlinesDirectory
                operations.append(InstallOperation(
                    source: bundledSource,
                    destination: destinationRoot.appending(path: safeDestinationName, directoryHint: .isDirectory),
                    type: type,
                    name: metadata["\(identifier).name"] ?? safeDestinationName,
                    refreshes: metadata["\(identifier).refresh"] == "1",
                    undeleteMask: refreshUndeleteMask(metadata["\(identifier).refreshundeletemask"])
                ))
            }
        }

        switch contentType {
        case .ghost:
            operations.append(InstallOperation(source: sourceRoot, destination: roots.ghostsDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            ), type: .ghost, name: primaryName, refreshes: refreshes, undeleteMask: undeleteMask))
            try appendBundledOperations()
        case .balloon:
            operations.append(InstallOperation(source: sourceRoot, destination: roots.balloonsDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            ), type: .balloon, name: primaryName, refreshes: refreshes, undeleteMask: undeleteMask))
        case .shell:
            guard let targetGhostDirectory = acceptedGhostDirectory ?? selectedGhostDirectory else {
                throw NarInstallError.shellRequiresGhost
            }
            operations.append(InstallOperation(source: sourceRoot, destination: targetGhostDirectory
                    .appending(path: "shell", directoryHint: .isDirectory)
                    .appending(path: directoryName, directoryHint: .isDirectory), type: .shell, name: primaryName,
                refreshes: refreshes, undeleteMask: undeleteMask))
            try appendBundledOperations()
        case .headline:
            operations.append(InstallOperation(source: sourceRoot, destination: roots.headlinesDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            ), type: .headline, name: primaryName, refreshes: refreshes, undeleteMask: undeleteMask))
        case .package:
            break
        }
        return (operations, acceptedGhostName)
    }

    private func installCopy(
        from source: URL,
        to destination: URL,
        refreshes: Bool,
        undeleteMask: Set<String>
    ) throws -> URL? {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(
            path: ".utatane-installing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: source, to: staging)
        if refreshes, fileManager.fileExists(atPath: destination.path), !undeleteMask.isEmpty,
           let enumerator = fileManager.enumerator(at: destination, includingPropertiesForKeys: [.isRegularFileKey])
        {
            let resolvedDestinationPath = destination.resolvingSymlinksInPath().path
            for case let oldURL as URL in enumerator where undeleteMask.contains(oldURL.lastPathComponent) {
                let resolvedOldPath = oldURL.resolvingSymlinksInPath().path
                var relativePath = String(resolvedOldPath.dropFirst(resolvedDestinationPath.count))
                if relativePath.hasPrefix("/") {
                    relativePath.removeFirst()
                }
                let preservedURL = staging.appending(path: relativePath)
                guard !fileManager.fileExists(atPath: preservedURL.path) else { continue }
                try fileManager.createDirectory(
                    at: preservedURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: oldURL, to: preservedURL)
            }
        }
        var backup: URL?
        if refreshes, fileManager.fileExists(atPath: destination.path) {
            let candidate = parent.appending(path: ".utatane-backup-\(UUID().uuidString)")
            try fileManager.moveItem(at: destination, to: candidate)
            backup = candidate
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if let backup {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
        return backup
    }

    @discardableResult
    private func run(
        executable: String,
        arguments: [String],
        capturesOutput: Bool = false
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = capturesOutput ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = capturesOutput ? output.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NarInstallError.commandFailed("\(URL(filePath: executable).lastPathComponent) exited \(process.terminationStatus)")
        }
        return data
    }
}

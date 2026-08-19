import Foundation

public enum NarContentType: String, Sendable, Equatable {
    case ghost
    case balloon
    case shell
    case headline
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

    public var installedURLs: [URL] { items.map(\.url) }

    public init(primaryType: NarContentType, items: [NarInstalledItem]) {
        self.primaryType = primaryType
        self.items = items
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
        case let .commandFailed(message): "NARの展開に失敗した: \(message)"
        }
    }
}

public struct NarInstaller: Sendable {
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
        selectedGhostDirectory: URL? = nil
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
        let directoryName = try validatedDirectoryName(metadata["directory"] ?? "")
        let sourceRoot = installURL.deletingLastPathComponent()

        var operations: [(source: URL, destination: URL, type: NarContentType, name: String)] = []
        let primaryName = metadata["name"] ?? directoryName
        switch contentType {
        case .ghost:
            operations.append((sourceRoot, roots.ghostsDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            ), .ghost, primaryName))
            if let sourceName = metadata["balloon.source.directory"],
               let balloonName = metadata["balloon.directory"]
            {
                let safeSourceName = try validatedDirectoryName(sourceName)
                let safeBalloonName = try validatedDirectoryName(balloonName)
                let balloonSource = sourceRoot.appending(path: safeSourceName, directoryHint: .isDirectory)
                guard fileManager.fileExists(atPath: balloonSource.path) else {
                    throw NarInstallError.missingSourceDirectory(safeSourceName)
                }
                operations.append((balloonSource, roots.balloonsDirectory.appending(
                    path: safeBalloonName,
                    directoryHint: .isDirectory
                ), .balloon, metadata["balloon.name"] ?? safeBalloonName))
            }
        case .balloon:
            operations.append((sourceRoot, roots.balloonsDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            ), .balloon, primaryName))
        case .shell:
            guard let selectedGhostDirectory else { throw NarInstallError.shellRequiresGhost }
            operations.append((sourceRoot, selectedGhostDirectory
                    .appending(path: "shell", directoryHint: .isDirectory)
                    .appending(path: directoryName, directoryHint: .isDirectory), .shell, primaryName))
        case .headline:
            operations.append((sourceRoot, roots.headlinesDirectory.appending(
                path: directoryName,
                directoryHint: .isDirectory
            ), .headline, primaryName))
        }

        for operation in operations where fileManager.fileExists(atPath: operation.destination.path) {
            throw NarInstallError.destinationExists(operation.destination)
        }

        var installedURLs: [URL] = []
        do {
            for operation in operations {
                try installCopy(from: operation.source, to: operation.destination)
                installedURLs.append(operation.destination)
            }
        } catch {
            for url in installedURLs {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
        return NarInstallResult(
            primaryType: contentType,
            items: zip(operations, installedURLs).map { operation, url in
                NarInstalledItem(type: operation.type, name: operation.name, url: url)
            }
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
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw NarInstallError.missingInstallFile }
        let candidates = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent.caseInsensitiveCompare("install.txt") == .orderedSame
            else { return nil }
            return url
        }
        guard !candidates.isEmpty else { throw NarInstallError.missingInstallFile }
        let depths = candidates.map { ($0, $0.pathComponents.count) }
        guard let minimumDepth = depths.map(\.1).min() else { throw NarInstallError.missingInstallFile }
        let shallowest = depths.filter { $0.1 == minimumDepth }.map(\.0)
        guard shallowest.count == 1, let installURL = shallowest.first else {
            throw NarInstallError.ambiguousInstallFile
        }
        return installURL
    }

    private func readInstallMetadata(from url: URL) throws -> [String: String] {
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

    private func installCopy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(
            path: ".utatane-installing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: source, to: staging)
        try fileManager.moveItem(at: staging, to: destination)
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

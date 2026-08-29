import Foundation
import UtataneCore

public enum NarContentType: String, Sendable, Equatable {
    case ghost
    case balloon
    case shell
    case headline
    case plugin
    case calendarSkin = "calendar skin"
    case calendarPlugin = "calendar plugin"
    case package
}

public struct NarInstallationRoots: Sendable, Equatable {
    public let ghostsDirectory: URL
    public let balloonsDirectory: URL
    public let headlinesDirectory: URL
    public let pluginsDirectory: URL
    public let calendarSkinsDirectory: URL
    public let calendarPluginsDirectory: URL

    public init(
        ghostsDirectory: URL,
        balloonsDirectory: URL,
        headlinesDirectory: URL? = nil,
        pluginsDirectory: URL? = nil,
        calendarSkinsDirectory: URL? = nil,
        calendarPluginsDirectory: URL? = nil
    ) {
        self.ghostsDirectory = ghostsDirectory
        self.balloonsDirectory = balloonsDirectory
        let contentDirectory = ghostsDirectory.deletingLastPathComponent()
        self.headlinesDirectory = headlinesDirectory ?? contentDirectory.appending(
            path: "Headline", directoryHint: .isDirectory
        )
        self.pluginsDirectory = pluginsDirectory ?? contentDirectory.appending(
            path: "Plugins", directoryHint: .isDirectory
        )
        self.calendarSkinsDirectory = calendarSkinsDirectory ?? contentDirectory.appending(
            path: "Calendar/Skins", directoryHint: .isDirectory
        )
        self.calendarPluginsDirectory = calendarPluginsDirectory ?? contentDirectory.appending(
            path: "Calendar/Plugins", directoryHint: .isDirectory
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
        case let .missingArchive(url): "NAR/ZIPが見つからない: \(url.path)"
        case .archiveTooLarge: "アーカイブの圧縮サイズが上限を超えている"
        case .unreadableArchive: "アーカイブの内容を読み取れない"
        case let .unsafeEntry(name): "安全でないアーカイブ内パス: \(name)"
        case .tooManyEntries: "アーカイブ内のファイル数が上限を超えている"
        case .extractedContentTooLarge: "展開後のサイズが上限を超えている"
        case let .symbolicLink(url): "シンボリックリンクはインストールできない: \(url.path)"
        case .missingInstallFile: "install.txtまたは適合するコンテンツ構造が見つからない"
        case .ambiguousInstallFile: "インストール元を一意に決められない"
        case let .unsupportedTextEncoding(url): "文字コードを判定できない: \(url.path)"
        case let .unsupportedType(type): "未対応のコンテンツ種別: \(type)"
        case let .invalidDirectoryName(name): "不正なインストール先ディレクトリ名: \(name)"
        case let .missingSourceDirectory(name): "同梱コンテンツが見つからない: \(name)"
        case .shellRequiresGhost: "Shellのインストール先ゴーストが選択されていない"
        case let .destinationExists(url): "同名のコンテンツが既にある: \(url.path)"
        case let .refused(accept, _, _): "このアーカイブは起動中の「\(accept)」用に指定されている"
        case let .commandFailed(message): "アーカイブの展開に失敗した: \(message)"
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

        // Older NAR creators commonly store Windows-style backslashes in ZIP entry names.
        // ditto extracts them as literal filename characters, then the isolated tree is normalized below.
        try run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", "--norsrc", archiveURL.path, extractionRoot.path]
        )
        try validateExtractedTree(at: extractionRoot)
        try normalizeWindowsSeparatedPaths(at: extractionRoot)
        try validateExtractedTree(at: extractionRoot)

        var operations: [InstallOperation] = []
        var primaryType: NarContentType = .ghost
        var acceptedGhostName: String?
        var bootGhostDirectory: String?

        let installURL: URL?
        do {
            installURL = try primaryInstallFile(in: extractionRoot)
        } catch NarInstallError.missingInstallFile {
            installURL = nil
        } catch {
            throw error
        }

        if let installURL {
            let metadata = try readInstallMetadata(from: installURL)
            guard let rawType = metadata["type"], let contentType = contentType(rawType) else {
                throw NarInstallError.unsupportedType(metadata["type"] ?? "")
            }
            primaryType = contentType
            let sourceRoot = installURL.deletingLastPathComponent()
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
        } else {
            guard archiveURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame else {
                throw NarInstallError.missingInstallFile
            }
            let inferred = try inferInstallationOperations(
                in: extractionRoot,
                archiveBaseName: archiveURL.deletingPathExtension().lastPathComponent,
                roots: roots,
                selectedGhostDirectory: selectedGhostDirectory,
                activeGhostDirectories: activeGhostDirectories
            )
            operations = inferred.operations
            primaryType = inferred.primaryType
            acceptedGhostName = inferred.acceptedGhostName
            bootGhostDirectory = inferred.bootGhostDirectory
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
            primaryType: primaryType,
            items: zip(operations, installedURLs).map { operation, url in
                NarInstalledItem(type: operation.type, name: operation.name, url: url)
            },
            acceptedGhostName: acceptedGhostName,
            bootGhostDirectory: bootGhostDirectory
        )
    }

    func validate(entries: [String]) throws {
        guard entries.count <= maximumEntryCount else { throw NarInstallError.tooManyEntries }
        var normalizedEntries = Set<String>()
        for entry in entries {
            let normalizedEntry = entry.replacingOccurrences(of: "\\", with: "/")
            guard !entry.isEmpty,
                  entry.utf8.count <= 1024,
                  !normalizedEntry.hasPrefix("/"),
                  !entry.contains("\0")
            else { throw NarInstallError.unsafeEntry(entry) }
            let components = normalizedEntry.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0 == ".." || $0 == "." }),
                  components.first?.contains(":") != true
            else {
                throw NarInstallError.unsafeEntry(entry)
            }
            guard normalizedEntry.hasSuffix("/") || normalizedEntries.insert(normalizedEntry).inserted else {
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

    private func normalizeWindowsSeparatedPaths(at root: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { throw NarInstallError.unreadableArchive }
        let resolvedRootPath = root.resolvingSymlinksInPath().path
        let rootPath = resolvedRootPath.hasSuffix("/") ? resolvedRootPath : resolvedRootPath + "/"
        var files: [URL] = []
        var directories: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                directories.append(url)
            } else {
                files.append(url)
            }
        }
        for source in files where source.path.contains("\\") {
            let resolvedSourcePath = source.resolvingSymlinksInPath().path
            guard resolvedSourcePath.hasPrefix(rootPath) else { throw NarInstallError.unsafeEntry(source.path) }
            let relativePath = String(resolvedSourcePath.dropFirst(rootPath.count))
                .replacingOccurrences(of: "\\", with: "/")
            if relativePath.hasSuffix("/") {
                try fileManager.removeItem(at: source)
                continue
            }
            let destination = root.appending(path: relativePath)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw NarInstallError.unsafeEntry(relativePath)
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: source, to: destination)
        }
        for directory in directories.sorted(by: { $0.pathComponents.count > $1.pathComponents.count })
            where directory.path.contains("\\")
        {
            try? fileManager.removeItem(at: directory)
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
        guard let text = LegacyTextDecoder.decode(data) else {
            throw NarInstallError.unsupportedTextEncoding(url)
        }
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
        guard let rawType = metadata["type"], let contentType = contentType(rawType),
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
                guard let bundledType = bundledContentType(identifier) else {
                    continue
                }
                type = bundledType
                guard let destinationName = metadata[key] else { continue }
                let safeDestinationName = try validatedDirectoryName(destinationName)
                let sourceName = metadata["\(identifier).source.directory"] ?? safeDestinationName
                let safeSourceName = try validatedDirectoryName(sourceName)
                let bundledSource = sourceRoot.appending(path: safeSourceName, directoryHint: .isDirectory)
                guard fileManager.fileExists(atPath: bundledSource.path) else {
                    throw NarInstallError.missingSourceDirectory(safeSourceName)
                }
                let destinationRoot = destinationRoot(for: type, roots: roots)
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
        case .plugin, .calendarSkin, .calendarPlugin:
            operations.append(InstallOperation(
                source: sourceRoot,
                destination: destinationRoot(for: contentType, roots: roots).appending(
                    path: directoryName,
                    directoryHint: .isDirectory
                ),
                type: contentType,
                name: primaryName,
                refreshes: refreshes,
                undeleteMask: undeleteMask
            ))
        case .package:
            break
        }
        return (operations, acceptedGhostName)
    }

    private func contentType(_ rawValue: String) -> NarContentType? {
        let normalized = rawValue.lowercased().replacingOccurrences(of: ".", with: " ")
        if normalized == "calendar" {
            return .calendarSkin
        }
        return NarContentType(rawValue: normalized)
    }

    private func bundledContentType(_ identifier: String) -> NarContentType? {
        for (prefix, type) in [
            ("calendar.plugin", NarContentType.calendarPlugin),
            ("calendar.skin", NarContentType.calendarSkin),
            ("balloon", NarContentType.balloon),
            ("headline", NarContentType.headline),
            ("plugin", NarContentType.plugin)
        ] where identifier.hasPrefix(prefix) && identifier.dropFirst(prefix.count).allSatisfy(\.isNumber) {
            return type
        }
        return nil
    }

    private func destinationRoot(for type: NarContentType, roots: NarInstallationRoots) -> URL {
        switch type {
        case .balloon: roots.balloonsDirectory
        case .headline: roots.headlinesDirectory
        case .plugin: roots.pluginsDirectory
        case .calendarSkin: roots.calendarSkinsDirectory
        case .calendarPlugin: roots.calendarPluginsDirectory
        case .ghost: roots.ghostsDirectory
        case .shell, .package: roots.ghostsDirectory
        }
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

    private func inferInstallationOperations(
        in root: URL,
        archiveBaseName: String,
        roots: NarInstallationRoots,
        selectedGhostDirectory: URL?,
        activeGhostDirectories: [String: URL]
    ) throws -> (
        operations: [InstallOperation],
        primaryType: NarContentType,
        acceptedGhostName: String?,
        bootGhostDirectory: String?
    ) {
        // 1. SSP root pattern (ghost/ and/or balloon/ containing sub-packages)
        if let sspResult = try inferSSPRootOperations(in: root, roots: roots) {
            return (
                operations: sspResult.operations,
                primaryType: .package,
                acceptedGhostName: nil,
                bootGhostDirectory: sspResult.bootGhostDirectory
            )
        }

        // 2. Ghost pattern (ghost/master/descript.txt or ghost/master directory)
        if let ghostRoot = findGhostRoot(in: root) {
            let descriptURL = ghostRoot.appending(path: "ghost/master/descript.txt", directoryHint: .notDirectory)
            let metadata = (try? readInstallMetadata(from: descriptURL)) ?? [:]
            let ghostName = metadata["name"] ?? (ghostRoot.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() ? archiveBaseName : ghostRoot.lastPathComponent)
            let rawDir = metadata["directory"]
            let directoryName = (rawDir != nil ? try? validatedDirectoryName(rawDir!) : nil)
                ?? (ghostRoot.resolvingSymlinksInPath() != root.resolvingSymlinksInPath() ? (try? validatedDirectoryName(ghostRoot.lastPathComponent)) : nil)
                ?? sanitizeDirectoryName(ghostName.isEmpty ? archiveBaseName : ghostName)

            var operations: [InstallOperation] = [
                InstallOperation(
                    source: ghostRoot,
                    destination: roots.ghostsDirectory.appending(path: directoryName, directoryHint: .isDirectory),
                    type: .ghost,
                    name: ghostName,
                    refreshes: false,
                    undeleteMask: []
                )
            ]

            let containerDir = ghostRoot.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() ? root : ghostRoot.deletingLastPathComponent()
            let bundledOps = try findBundledOperations(
                in: containerDir,
                excluding: ghostRoot,
                roots: roots
            )
            operations.append(contentsOf: bundledOps)

            return (
                operations: operations,
                primaryType: .ghost,
                acceptedGhostName: nil,
                bootGhostDirectory: directoryName
            )
        }

        // 3. Standalone content pattern (Balloon, Shell, Plugin, Headline, Calendar Skin)
        if let standalone = try inferStandaloneContentOperations(
            in: root,
            archiveBaseName: archiveBaseName,
            roots: roots,
            selectedGhostDirectory: selectedGhostDirectory,
            activeGhostDirectories: activeGhostDirectories
        ) {
            return (
                operations: standalone.operations,
                primaryType: standalone.primaryType,
                acceptedGhostName: standalone.acceptedGhostName,
                bootGhostDirectory: nil
            )
        }

        throw NarInstallError.missingInstallFile
    }

    private func findGhostRoot(in root: URL) -> URL? {
        if isGhostDirectory(root) {
            return root
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [URL] = []
        for case let url as URL in enumerator {
            if isIgnoredDirectory(url) {
                enumerator.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if isGhostDirectory(url) {
                    candidates.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        return candidates.sorted { $0.pathComponents.count < $1.pathComponents.count }.first
    }

    private func isGhostDirectory(_ directory: URL) -> Bool {
        let masterDescript = directory.appending(path: "ghost/master/descript.txt", directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: masterDescript.path) {
            return true
        }
        let masterDir = directory.appending(path: "ghost/master", directoryHint: .isDirectory)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: masterDir.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func inferSSPRootOperations(
        in root: URL,
        roots: NarInstallationRoots
    ) throws -> (operations: [InstallOperation], bootGhostDirectory: String?)? {
        let fileManager = FileManager.default

        func findCandidateRoot(_ dir: URL) -> URL {
            let ghostDir = dir.appending(path: "ghost", directoryHint: .isDirectory)
            let balloonDir = dir.appending(path: "balloon", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: ghostDir.path) || fileManager.fileExists(atPath: balloonDir.path) {
                return dir
            }
            if let children = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]),
               children.count == 1,
               let onlyChild = children.first,
               (try? onlyChild.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               !isIgnoredDirectory(onlyChild)
            {
                let g = onlyChild.appending(path: "ghost", directoryHint: .isDirectory)
                let b = onlyChild.appending(path: "balloon", directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: g.path) || fileManager.fileExists(atPath: b.path) {
                    return onlyChild
                }
            }
            return dir
        }

        let sspRoot = findCandidateRoot(root)
        let ghostDir = sspRoot.appending(path: "ghost", directoryHint: .isDirectory)
        let balloonDir = sspRoot.appending(path: "balloon", directoryHint: .isDirectory)

        var operations: [InstallOperation] = []
        var bootGhostDirectory: String?

        if fileManager.fileExists(atPath: ghostDir.path) {
            if let ghostChildren = try? fileManager.contentsOfDirectory(at: ghostDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for child in ghostChildren where !isIgnoredDirectory(child) && (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if isGhostDirectory(child) {
                        let descriptURL = child.appending(path: "ghost/master/descript.txt", directoryHint: .notDirectory)
                        let metadata = (try? readInstallMetadata(from: descriptURL)) ?? [:]
                        let name = metadata["name"] ?? child.lastPathComponent
                        let dirName = metadata["directory"].flatMap { try? validatedDirectoryName($0) } ?? sanitizeDirectoryName(child.lastPathComponent)
                        if bootGhostDirectory == nil {
                            bootGhostDirectory = dirName
                        }
                        operations.append(InstallOperation(
                            source: child,
                            destination: roots.ghostsDirectory.appending(path: dirName, directoryHint: .isDirectory),
                            type: .ghost,
                            name: name,
                            refreshes: false,
                            undeleteMask: []
                        ))
                    }
                }
            }
        }

        if fileManager.fileExists(atPath: balloonDir.path) {
            if let balloonChildren = try? fileManager.contentsOfDirectory(at: balloonDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for child in balloonChildren where !isIgnoredDirectory(child) && (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let descriptURL = child.appending(path: "descript.txt", directoryHint: .notDirectory)
                    let metadata = (try? readInstallMetadata(from: descriptURL)) ?? [:]
                    let name = metadata["name"] ?? child.lastPathComponent
                    let dirName = metadata["directory"].flatMap { try? validatedDirectoryName($0) } ?? sanitizeDirectoryName(child.lastPathComponent)
                    operations.append(InstallOperation(
                        source: child,
                        destination: roots.balloonsDirectory.appending(path: dirName, directoryHint: .isDirectory),
                        type: .balloon,
                        name: name,
                        refreshes: false,
                        undeleteMask: []
                    ))
                }
            }
        }

        guard !operations.isEmpty else { return nil }
        return (operations, bootGhostDirectory)
    }

    private func inferStandaloneContentOperations(
        in root: URL,
        archiveBaseName: String,
        roots: NarInstallationRoots,
        selectedGhostDirectory: URL?,
        activeGhostDirectories: [String: URL]
    ) throws -> (
        operations: [InstallOperation],
        primaryType: NarContentType,
        acceptedGhostName: String?
    )? {
        let fileManager = FileManager.default
        var candidates: [(directory: URL, descriptURL: URL)] = []
        if fileManager.fileExists(atPath: root.appending(path: "descript.txt").path) {
            candidates.append((root, root.appending(path: "descript.txt")))
        }

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if isIgnoredDirectory(url) {
                    enumerator.skipDescendants()
                    continue
                }
                if url.lastPathComponent.caseInsensitiveCompare("descript.txt") == .orderedSame {
                    let dir = url.deletingLastPathComponent()
                    if !candidates.contains(where: { $0.directory.resolvingSymlinksInPath() == dir.resolvingSymlinksInPath() }) {
                        candidates.append((dir, url))
                    }
                }
            }
        }

        candidates.sort { $0.directory.pathComponents.count < $1.directory.pathComponents.count }

        for (dir, descriptURL) in candidates {
            guard let metadata = try? readInstallMetadata(from: descriptURL) else { continue }
            let rawType = metadata["type"]
            let detectedType = rawType.flatMap(contentType)
            let name = metadata["name"] ?? (dir.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() ? archiveBaseName : dir.lastPathComponent)
            let dirName = metadata["directory"].flatMap { try? validatedDirectoryName($0) }
                ?? (dir.resolvingSymlinksInPath() != root.resolvingSymlinksInPath() ? (try? validatedDirectoryName(dir.lastPathComponent)) : nil)
                ?? sanitizeDirectoryName(name.isEmpty ? archiveBaseName : name)

            if detectedType == .balloon || isBalloonDirectory(dir) {
                let op = InstallOperation(
                    source: dir,
                    destination: roots.balloonsDirectory.appending(path: dirName, directoryHint: .isDirectory),
                    type: .balloon,
                    name: name,
                    refreshes: false,
                    undeleteMask: []
                )
                return ([op], .balloon, nil)
            }

            if detectedType == .shell || isShellDirectory(dir) {
                let acceptedGhost = metadata["accept"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let targetGhost = acceptedGhost.flatMap { acc in
                    activeGhostDirectories.first { $0.key.caseInsensitiveCompare(acc) == .orderedSame }?.value
                } ?? selectedGhostDirectory

                guard let targetGhost else {
                    if let acceptedGhost, !acceptedGhost.isEmpty {
                        throw NarInstallError.refused(accept: acceptedGhost, type: "shell", name: name)
                    }
                    throw NarInstallError.shellRequiresGhost
                }

                let op = InstallOperation(
                    source: dir,
                    destination: targetGhost.appending(path: "shell/\(dirName)", directoryHint: .isDirectory),
                    type: .shell,
                    name: name,
                    refreshes: false,
                    undeleteMask: []
                )
                return ([op], .shell, acceptedGhost)
            }

            if let detectedType, detectedType != .ghost, detectedType != .package {
                let destRoot = destinationRoot(for: detectedType, roots: roots)
                let op = InstallOperation(
                    source: dir,
                    destination: destRoot.appending(path: dirName, directoryHint: .isDirectory),
                    type: detectedType,
                    name: name,
                    refreshes: false,
                    undeleteMask: []
                )
                return ([op], detectedType, nil)
            }
        }

        // Also check if surfaces.txt exists without descript.txt (old shell)
        if let shellCandidate = findDirectoryWithFile(named: "surfaces.txt", in: root) {
            let name = shellCandidate.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() ? archiveBaseName : shellCandidate.lastPathComponent
            let dirName = sanitizeDirectoryName(name)
            guard let targetGhost = selectedGhostDirectory ?? activeGhostDirectories.values.first else {
                throw NarInstallError.shellRequiresGhost
            }
            let op = InstallOperation(
                source: shellCandidate,
                destination: targetGhost.appending(path: "shell/\(dirName)", directoryHint: .isDirectory),
                type: .shell,
                name: name,
                refreshes: false,
                undeleteMask: []
            )
            return ([op], .shell, nil)
        }

        return nil
    }

    private func findBundledOperations(
        in container: URL,
        excluding ghostRoot: URL,
        roots: NarInstallationRoots
    ) throws -> [InstallOperation] {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var operations: [InstallOperation] = []
        for item in items where item.resolvingSymlinksInPath() != ghostRoot.resolvingSymlinksInPath() && !isIgnoredDirectory(item) {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let lower = item.lastPathComponent.lowercased()
            let descriptURL = item.appending(path: "descript.txt", directoryHint: .notDirectory)
            let metadata = (try? readInstallMetadata(from: descriptURL)) ?? [:]
            let name = metadata["name"] ?? item.lastPathComponent
            let dirName = metadata["directory"].flatMap { try? validatedDirectoryName($0) } ?? sanitizeDirectoryName(item.lastPathComponent)

            if lower.hasPrefix("balloon") || isBalloonDirectory(item) {
                operations.append(InstallOperation(
                    source: item,
                    destination: roots.balloonsDirectory.appending(path: dirName, directoryHint: .isDirectory),
                    type: .balloon,
                    name: name,
                    refreshes: false,
                    undeleteMask: []
                ))
            } else if lower.hasPrefix("headline") || metadata["type"]?.lowercased() == "headline" {
                operations.append(InstallOperation(
                    source: item,
                    destination: roots.headlinesDirectory.appending(path: dirName, directoryHint: .isDirectory),
                    type: .headline,
                    name: name,
                    refreshes: false,
                    undeleteMask: []
                ))
            } else if lower.hasPrefix("plugin") || metadata["type"]?.lowercased() == "plugin" {
                operations.append(InstallOperation(
                    source: item,
                    destination: roots.pluginsDirectory.appending(path: dirName, directoryHint: .isDirectory),
                    type: .plugin,
                    name: name,
                    refreshes: false,
                    undeleteMask: []
                ))
            }
        }
        return operations
    }

    private func isIgnoredDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name.caseInsensitiveCompare("__MACOSX") == .orderedSame
    }

    private func isBalloonDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appending(path: "origin.txt").path)
            || fileManager.fileExists(atPath: directory.appending(path: "balloona0.png").path)
            || fileManager.fileExists(atPath: directory.appending(path: "balloonk0.png").path)
        {
            return true
        }
        return false
    }

    private func isShellDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appending(path: "surfaces.txt").path)
            || fileManager.fileExists(atPath: directory.appending(path: "surface0.png").path)
        {
            return true
        }
        return false
    }

    private func findDirectoryWithFile(named fileName: String, in root: URL) -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.appending(path: fileName).path) {
            return root
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if isIgnoredDirectory(url) {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    private func sanitizeDirectoryName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|\0\r\n\t")
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "installed_content"
        }
        return cleaned
    }
}

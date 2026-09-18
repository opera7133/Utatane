import Foundation
import ZIPFoundation

public struct ContentArchiveValidationLimits: Sendable {
    public var maximumArchiveBytes: UInt64
    public var maximumExtractedBytes: UInt64
    public var maximumEntryCount: Int
    public var maximumPathBytes: Int
    public var timeout: TimeInterval

    public init(
        maximumArchiveBytes: UInt64 = 50 * 1024 * 1024,
        maximumExtractedBytes: UInt64 = 200 * 1024 * 1024,
        maximumEntryCount: Int = 5000,
        maximumPathBytes: Int = 1024,
        timeout: TimeInterval = 10
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumExtractedBytes = maximumExtractedBytes
        self.maximumEntryCount = maximumEntryCount
        self.maximumPathBytes = maximumPathBytes
        self.timeout = timeout
    }
}

public struct ContentArchiveValidator: Sendable {
    private let limits: ContentArchiveValidationLimits
    private let validator: ContentValidator

    public init(
        limits: ContentArchiveValidationLimits = ContentArchiveValidationLimits(),
        validator: ContentValidator = ContentValidator()
    ) {
        self.limits = limits
        self.validator = validator
    }

    public func validate(archiveURL: URL) -> ContentValidationReport {
        let archiveURL = archiveURL.standardizedFileURL
        let startedAt = Date()
        let fileManager = FileManager.default

        do {
            let attributes = try fileManager.attributesOfItem(atPath: archiveURL.path)
            guard let fileSize = attributes[.size] as? NSNumber else {
                throw ArchiveValidationError.unreadable("ファイルサイズを取得できません。")
            }
            guard fileSize.uint64Value <= limits.maximumArchiveBytes else {
                throw ArchiveValidationError.tooLarge
            }

            let preflight = try ZIPPreflight.inspect(url: archiveURL)
            guard preflight.entryCount <= limits.maximumEntryCount else {
                throw ArchiveValidationError.tooManyEntries
            }
            guard !preflight.isEncrypted else {
                throw ArchiveValidationError.unsupported("暗号化されたZIPには対応していません。")
            }

            let archive = try Archive(url: archiveURL, accessMode: .read)
            let entries = Array(archive)
            guard entries.count == preflight.entryCount else {
                throw ArchiveValidationError.unreadable("ZIPのエントリ一覧を最後まで読み取れません。")
            }

            var prepared: [(entry: Entry, path: String)] = []
            var pathKeys = Set<String>()
            var declaredExtractedBytes: UInt64 = 0
            for entry in entries {
                try checkDeadline(startedAt)
                guard entry.type != .symlink else {
                    throw ArchiveValidationError.unsupported("シンボリックリンクは展開できません: \(entry.path)")
                }
                let path = try normalizedPath(for: entry)
                let key = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .precomposedStringWithCanonicalMapping.lowercased()
                guard pathKeys.insert(key).inserted else {
                    throw ArchiveValidationError.unsafeEntry("正規化後に重複するパスがあります: \(path)")
                }
                let (nextSize, overflow) = declaredExtractedBytes.addingReportingOverflow(entry.uncompressedSize)
                guard !overflow, nextSize <= limits.maximumExtractedBytes else {
                    throw ArchiveValidationError.extractedTooLarge
                }
                declaredExtractedBytes = nextSize
                prepared.append((entry, path))
            }

            let temporaryRoot = fileManager.temporaryDirectory
                .appending(path: "utatane-validate-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: temporaryRoot) }

            var extractedBytes: UInt64 = 0
            for item in prepared {
                try checkDeadline(startedAt)
                let destination = temporaryRoot.appending(path: item.path)
                switch item.entry.type {
                case .directory:
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                case .file:
                    try fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                        throw ArchiveValidationError.unreadable("一時ファイルを作成できません: \(item.path)")
                    }
                    let output = try FileHandle(forWritingTo: destination)
                    do {
                        _ = try archive.extract(item.entry) { chunk in
                            try checkDeadline(startedAt)
                            let (nextSize, overflow) = extractedBytes.addingReportingOverflow(UInt64(chunk.count))
                            guard !overflow, nextSize <= limits.maximumExtractedBytes else {
                                throw ArchiveValidationError.extractedTooLarge
                            }
                            extractedBytes = nextSize
                            try output.write(contentsOf: chunk)
                        }
                        try output.close()
                    } catch {
                        try? output.close()
                        throw error
                    }
                case .symlink:
                    throw ArchiveValidationError.unsupported("シンボリックリンクは展開できません。")
                }
            }

            let roots = ghostRoots(in: temporaryRoot, paths: prepared.map(\.path))
            guard !roots.isEmpty else { throw ArchiveValidationError.noGhost }
            guard roots.count == 1 else { throw ArchiveValidationError.multipleGhosts }
            let report = validator.validate(ghostRoot: roots[0])
            return ContentValidationReport(
                rootPath: archiveURL.path,
                ghostName: report.ghostName,
                shiori: report.shiori,
                shioriAssessment: report.shioriAssessment,
                diagnostics: report.diagnostics
            )
        } catch let error as ArchiveValidationError {
            return failureReport(archiveURL: archiveURL, error: error)
        } catch {
            return failureReport(
                archiveURL: archiveURL,
                error: .unreadable("ZIPを読み取れません: \(error.localizedDescription)")
            )
        }
    }

    private func checkDeadline(_ startedAt: Date) throws {
        guard limits.timeout > 0, Date().timeIntervalSince(startedAt) <= limits.timeout else {
            throw ArchiveValidationError.timeout
        }
    }

    private func normalizedPath(for entry: Entry) throws -> String {
        let defaultPath = entry.path
        let shiftJISPath = entry.path(using: .shiftJIS)
        let decodedPath = shouldPreferShiftJIS(defaultPath: defaultPath, shiftJISPath: shiftJISPath)
            ? shiftJISPath
            : defaultPath
        let path = decodedPath.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else {
            throw ArchiveValidationError.unsafeEntry("絶対パスまたは空のパスが含まれています。")
        }
        guard path.utf8.count <= limits.maximumPathBytes else {
            throw ArchiveValidationError.unsafeEntry("パスが長すぎます。")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let meaningfulComponents = path.hasSuffix("/") ? components.dropLast() : components[...]
        guard !meaningfulComponents.isEmpty,
              meaningfulComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw ArchiveValidationError.unsafeEntry("危険な相対パスが含まれています: \(path)")
        }
        guard meaningfulComponents.first.map({ !$0.contains(":") }) ?? false else {
            throw ArchiveValidationError.unsafeEntry("ドライブ名を含むパスは使用できません: \(path)")
        }
        return path
    }

    private func shouldPreferShiftJIS(defaultPath: String, shiftJISPath: String) -> Bool {
        guard defaultPath != shiftJISPath, !shiftJISPath.contains("�") else { return false }
        return defaultPath.unicodeScalars.contains { scalar in
            (0x2500 ... 0x259F).contains(scalar.value) || (0xE000 ... 0xF8FF).contains(scalar.value)
        }
    }

    private func ghostRoots(in temporaryRoot: URL, paths: [String]) -> [URL] {
        let suffix = "ghost/master/descript.txt"
        let prefixes = Set(paths.compactMap { path -> String? in
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard normalized == suffix || normalized.hasSuffix("/\(suffix)") else { return nil }
            return String(normalized.dropLast(suffix.count))
        })
        return prefixes.compactMap { prefix in
            let root = prefix.isEmpty ? temporaryRoot : temporaryRoot.appending(path: prefix)
            var isDirectory: ObjCBool = false
            let shell = root.appending(path: "shell")
            return FileManager.default.fileExists(atPath: shell.path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? root
                : nil
        }.sorted { $0.path < $1.path }
    }

    private func failureReport(archiveURL: URL, error: ArchiveValidationError) -> ContentValidationReport {
        ContentValidationReport(
            rootPath: archiveURL.path,
            ghostName: nil,
            shiori: nil,
            shioriAssessment: nil,
            diagnostics: [ContentDiagnostic(
                severity: .error,
                code: error.code,
                message: error.message,
                path: archiveURL.lastPathComponent
            )]
        )
    }
}

private enum ArchiveValidationError: Error {
    case tooLarge
    case tooManyEntries
    case unsafeEntry(String)
    case unsupported(String)
    case extractedTooLarge
    case timeout
    case unreadable(String)
    case noGhost
    case multipleGhosts

    var code: String {
        switch self {
        case .tooLarge: "archive.too-large"
        case .tooManyEntries: "archive.too-many-entries"
        case .unsafeEntry: "archive.unsafe-entry"
        case .unsupported: "archive.unsupported-entry"
        case .extractedTooLarge: "archive.extracted-too-large"
        case .timeout: "archive.timeout"
        case .unreadable: "archive.unreadable"
        case .noGhost: "archive.no-ghost"
        case .multipleGhosts: "archive.multiple-ghosts"
        }
    }

    var message: String {
        switch self {
        case .tooLarge: "アーカイブがアップロード上限を超えています。"
        case .tooManyEntries: "アーカイブ内のファイル数が上限を超えています。"
        case let .unsafeEntry(message), let .unsupported(message), let .unreadable(message): message
        case .extractedTooLarge: "展開後の合計サイズが上限を超えています。"
        case .timeout: "アーカイブの検査が制限時間を超えました。"
        case .noGhost: "ghost/master/descript.txt と shell を持つゴーストが見つかりません。"
        case .multipleGhosts: "複数のゴーストが含まれています。1つずつ検査してください。"
        }
    }
}

private struct ZIPPreflight {
    let entryCount: Int
    let isEncrypted: Bool

    static func inspect(url: URL) throws -> ZIPPreflight {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let minimumEOCDSize = 22
        guard data.count >= minimumEOCDSize else {
            throw ArchiveValidationError.unreadable("ZIPの終端情報がありません。")
        }
        let lowerBound = max(0, data.count - minimumEOCDSize - Int(UInt16.max))
        guard let eocd = stride(from: data.count - minimumEOCDSize, through: lowerBound, by: -1).first(where: {
            guard data.uint32LE(at: $0) == 0x0605_4B50 else { return false }
            return $0 + minimumEOCDSize + Int(data.uint16LE(at: $0 + 20)) == data.count
        }) else {
            throw ArchiveValidationError.unreadable("ZIPの終端情報がありません。")
        }
        let disk = data.uint16LE(at: eocd + 4)
        let centralDisk = data.uint16LE(at: eocd + 6)
        let entriesOnDisk = data.uint16LE(at: eocd + 8)
        let totalEntries = data.uint16LE(at: eocd + 10)
        guard disk == 0, centralDisk == 0, entriesOnDisk == totalEntries else {
            throw ArchiveValidationError.unsupported("分割ZIPには対応していません。")
        }
        guard totalEntries != .max else {
            throw ArchiveValidationError.unsupported("ZIP64には対応していません。")
        }
        let centralSize = Int(data.uint32LE(at: eocd + 12))
        var offset = Int(data.uint32LE(at: eocd + 16))
        guard offset >= 0, centralSize >= 0, offset <= data.count, centralSize <= data.count - offset else {
            throw ArchiveValidationError.unreadable("ZIPの中央ディレクトリが壊れています。")
        }
        let centralEnd = offset + centralSize
        var encrypted = false
        for _ in 0 ..< Int(totalEntries) {
            guard offset + 46 <= centralEnd, data.uint32LE(at: offset) == 0x0201_4B50 else {
                throw ArchiveValidationError.unreadable("ZIPの中央ディレクトリが壊れています。")
            }
            encrypted = encrypted || (data.uint16LE(at: offset + 8) & 1) != 0
            let nameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let next = offset + 46 + nameLength + extraLength + commentLength
            guard next >= offset, next <= centralEnd else {
                throw ArchiveValidationError.unreadable("ZIPのエントリ情報が壊れています。")
            }
            offset = next
        }
        guard offset == centralEnd else {
            throw ArchiveValidationError.unreadable("ZIPの中央ディレクトリ件数が一致しません。")
        }
        return ZIPPreflight(entryCount: Int(totalEntries), isEncrypted: encrypted)
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

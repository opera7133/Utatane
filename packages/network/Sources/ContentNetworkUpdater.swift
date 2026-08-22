import CryptoKit
import Foundation

public struct ContentUpdateEntry: Sendable, Equatable {
    public let path: String
    public let md5: String

    public init(path: String, md5: String) {
        self.path = path
        self.md5 = md5.lowercased()
    }
}

public struct ContentUpdateResult: Sendable, Equatable {
    public let changedFiles: [String]

    public init(changedFiles: [String]) {
        self.changedFiles = changedFiles
    }
}

public enum ContentNetworkUpdateError: LocalizedError, Equatable, Sendable {
    case invalidHomeURL
    case missingManifest
    case invalidManifestLine(String)
    case unsafePath(String)
    case tooManyFiles
    case updateTooLarge
    case checksumMismatch(String)
    case downloadFailed(path: String, underlyingError: String)

    public var errorDescription: String? {
        switch self {
        case .invalidHomeURL: "更新URLが不正"
        case .missingManifest: "updates2.dauまたはupdates.txtを取得できない"
        case let .invalidManifestLine(line): "更新定義が不正: \(line)"
        case let .unsafePath(path): "安全でない更新パス: \(path)"
        case .tooManyFiles: "更新ファイル数が上限を超えている"
        case .updateTooLarge: "更新サイズが上限を超えている"
        case let .checksumMismatch(path): "MD5が一致しない: \(path)"
        case let .downloadFailed(path, error): "ファイル取得失敗 (\(path)): \(error)"
        }
    }
}

public struct ContentNetworkUpdater: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data
    private let maximumFileCount: Int
    private let maximumTotalBytes: Int
    private let fetch: Fetch

    public init(
        maximumFileCount: Int = 20000,
        maximumTotalBytes: Int = 1024 * 1024 * 1024,
        fetch: @escaping Fetch = { try await NetworkFetchClient(maximumBytes: 512 * 1024 * 1024).fetch($0) }
    ) {
        self.maximumFileCount = maximumFileCount
        self.maximumTotalBytes = maximumTotalBytes
        self.fetch = fetch
    }

    public func update(rootDirectory: URL, homeURL: URL) async throws -> ContentUpdateResult {
        guard let scheme = homeURL.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw ContentNetworkUpdateError.invalidHomeURL
        }
        let (manifestURL, manifestData) = try await fetchManifest(homeURL: homeURL)
        let entries = try Self.parseManifest(manifestData)
        guard entries.count <= maximumFileCount else { throw ContentNetworkUpdateError.tooManyFiles }

        let fileManager = FileManager.default
        let root = rootDirectory.standardizedFileURL
        let staging = fileManager.temporaryDirectory.appending(path: "utatane-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        let backup = fileManager.temporaryDirectory.appending(path: "utatane-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }

        var changed: [(entry: ContentUpdateEntry, local: URL, staged: URL)] = []
        var totalBytes = 0
        for entry in entries {
            let local = try Self.confinedURL(path: entry.path, root: root)
            if let data = try? Data(contentsOf: local), Self.md5(data) == entry.md5 {
                continue
            }
            let remote = manifestURL.deletingLastPathComponent().appending(path: entry.path)
            let data: Data
            do {
                data = try await fetch(remote)
            } catch {
                throw ContentNetworkUpdateError.downloadFailed(path: entry.path, underlyingError: error.localizedDescription)
            }
            totalBytes += data.count
            guard totalBytes <= maximumTotalBytes else { throw ContentNetworkUpdateError.updateTooLarge }
            guard Self.md5(data) == entry.md5 else {
                throw ContentNetworkUpdateError.checksumMismatch(entry.path)
            }
            let staged = try Self.confinedURL(path: entry.path, root: staging)
            try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: staged, options: .atomic)
            changed.append((entry, local, staged))
        }

        var applied: [(local: URL, backup: URL?, existed: Bool)] = []
        do {
            for item in changed {
                let relativeBackup = try Self.confinedURL(path: item.entry.path, root: backup)
                let existed = fileManager.fileExists(atPath: item.local.path)
                if existed {
                    try fileManager.createDirectory(at: relativeBackup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: item.local, to: relativeBackup)
                }
                try fileManager.createDirectory(at: item.local.deletingLastPathComponent(), withIntermediateDirectories: true)
                applied.append((item.local, existed ? relativeBackup : nil, existed))
                if existed {
                    try fileManager.removeItem(at: item.local)
                }
                try fileManager.copyItem(at: item.staged, to: item.local)
            }
        } catch {
            for item in applied.reversed() {
                try? fileManager.removeItem(at: item.local)
                if let backup = item.backup {
                    try? fileManager.copyItem(at: backup, to: item.local)
                }
            }
            throw error
        }
        return ContentUpdateResult(changedFiles: changed.map(\.entry.path))
    }

    public static func homeURL(in rootDirectory: URL) -> URL? {
        let candidates = [
            rootDirectory.appending(path: "descript.txt"),
            rootDirectory.appending(path: "ghost/master/descript.txt")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
            else { continue }
            for line in text.components(separatedBy: .newlines) {
                let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
                if fields.count == 2, fields[0].trimmingCharacters(in: .whitespaces).lowercased() == "homeurl" {
                    return URL(string: fields[1].trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return nil
    }

    public static func parseManifest(_ data: Data) throws -> [ContentUpdateEntry] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            throw ContentNetworkUpdateError.invalidManifestLine("encoding")
        }
        return try text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let fields = line.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
            let path: String
            let hash: String
            if fields.count >= 2, fields[0].lowercased().hasPrefix("file,") {
                path = String(fields[0].dropFirst("file,".count))
                hash = fields[1]
            } else if fields.count >= 2 {
                path = fields[0]
                hash = fields[1]
            } else {
                throw ContentNetworkUpdateError.invalidManifestLine(line)
            }
            _ = try confinedURL(path: path, root: URL(filePath: "/manifest-root", directoryHint: .isDirectory))
            guard hash.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil else {
                throw ContentNetworkUpdateError.invalidManifestLine(line)
            }
            return ContentUpdateEntry(path: path, md5: hash)
        }
    }

    private func fetchManifest(homeURL: URL) async throws -> (URL, Data) {
        for name in ["updates2.dau", "updates.txt"] {
            let url = homeURL.appending(path: name)
            if let data = try? await fetch(url) {
                return (url, data)
            }
        }
        throw ContentNetworkUpdateError.missingManifest
    }

    private static func confinedURL(path: String, root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            throw ContentNetworkUpdateError.unsafePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw ContentNetworkUpdateError.unsafePath(path)
        }
        let result = components.reduce(root) { $0.appending(path: String($1)) }.standardizedFileURL
        guard result.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw ContentNetworkUpdateError.unsafePath(path)
        }
        return result
    }

    private static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

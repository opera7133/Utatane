import CryptoKit
import Foundation

public struct UpdateDataGeneratorResult: Sendable, Equatable {
    public let fileCount: Int
    public let manifestURL: URL

    public init(fileCount: Int, manifestURL: URL) {
        self.fileCount = fileCount
        self.manifestURL = manifestURL
    }
}

public struct UpdateDataGenerator: Sendable {
    public init() {}

    public func generateStandard(in directoryURL: URL) throws -> UpdateDataGeneratorResult {
        let result = try generate(in: directoryURL)
        for relativePath in ["updates.txt", "ghost/master/updates2.dau", "ghost/master/updates.txt"] {
            _ = try generate(in: directoryURL, outputURL: directoryURL.appending(path: relativePath))
        }
        return result
    }

    public func generate(
        in directoryURL: URL,
        manifestFilename: String = "updates2.dau"
    ) throws -> UpdateDataGeneratorResult {
        try generate(in: directoryURL, outputURL: directoryURL.appending(path: manifestFilename))
    }

    public func generate(in directoryURL: URL, outputURL manifestURL: URL) throws -> UpdateDataGeneratorResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        var entries: [(relativePath: String, md5: String, size: Int, date: String)] = []
        let developerOptions = try DeveloperOptions.load(from: directoryURL)
        let pathFilter = try ContentPathFilter.load(
            from: directoryURL,
            ignoreFilename: ".updateignore",
            includeFilename: ".updateinclude"
        )

        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }

            guard fileURL.resolvingSymlinksInPath().standardizedFileURL != manifestURL.resolvingSymlinksInPath().standardizedFileURL else { continue }
            let filename = fileURL.lastPathComponent
            if filename == "updates2.dau"
                || filename == "updates.txt"
            {
                continue
            }

            let rootPath = directoryURL.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath) else { continue }

            var relativePath = String(filePath.dropFirst(rootPath.count))
            if relativePath.hasPrefix("/") {
                relativePath.removeFirst()
            }
            if DeveloperOptions.isStandardExcluded(relativePath: relativePath)
                || developerOptions.excludesFromUpdate(relativePath: relativePath)
                || !pathFilter.includes(relativePath: relativePath)
            {
                continue
            }

            let data = try Data(contentsOf: fileURL)
            let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let modifiedValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = modifiedValues?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            entries.append((
                relativePath: relativePath,
                md5: md5,
                size: data.count,
                date: ISO8601DateFormatter().string(from: modified)
            ))
        }

        entries.sort { $0.relativePath < $1.relativePath }

        let isDAU = manifestURL.pathExtension.lowercased() == "dau"
        var manifestContent = isDAU ? "" : "charset,UTF-8\r\n"
        for (index, entry) in entries.enumerated() {
            let charset = isDAU && index == 0 ? "charset=UTF-8\u{1}" : ""
            manifestContent += "\(isDAU ? "" : "file,")\(entry.relativePath)\u{1}\(entry.md5)\u{1}size=\(entry.size)\u{1}date=\(entry.date)\u{1}\(charset)\r\n"
        }

        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifestContent.write(to: manifestURL, atomically: true, encoding: .utf8)

        return UpdateDataGeneratorResult(
            fileCount: entries.count,
            manifestURL: manifestURL
        )
    }
}

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

    public func generate(
        in directoryURL: URL,
        manifestFilename: String = "updates2.dau"
    ) throws -> UpdateDataGeneratorResult {
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

        var manifestContent = ""
        for (index, entry) in entries.enumerated() {
            let charset = index == 0 ? "charset=UTF-8\u{1}" : ""
            manifestContent += "\(entry.relativePath)\u{1}\(entry.md5)\u{1}size=\(entry.size)\u{1}date=\(entry.date)\u{1}\(charset)\r\n"
        }

        let manifestURL = directoryURL.appending(path: manifestFilename)
        try manifestContent.write(to: manifestURL, atomically: true, encoding: .utf8)

        return UpdateDataGeneratorResult(
            fileCount: entries.count,
            manifestURL: manifestURL
        )
    }
}

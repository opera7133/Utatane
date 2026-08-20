import Foundation
import UtataneCore

public enum ShellError: LocalizedError, Equatable {
    case missingFile(URL)
    case unsupportedTextEncoding(URL)
    case missingSurface(id: Int, directory: URL)
    case missingElement(filename: String, directory: URL)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            "必要なファイルがない: \(url.path)"
        case let .unsupportedTextEncoding(url):
            "文字コードを判定できない: \(url.path)"
        case let .missingSurface(id, directory):
            "surface\(id)が見つからない: \(directory.path)"
        case let .missingElement(filename, directory):
            "Surface要素\(filename)が見つからない: \(directory.path)"
        }
    }
}

public struct ShellLoader: Sendable {
    private let parser = SurfacesParser()

    public init() {}

    public func load(from shellDirectory: URL) throws -> ShellDefinition {
        let fileManager = FileManager.default
        let surfacesURLs = try fileManager.contentsOfDirectory(
            at: shellDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            $0.pathExtension.lowercased() == "txt"
                && $0.lastPathComponent.lowercased().hasPrefix("surfaces")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !surfacesURLs.isEmpty else {
            throw ShellError.missingFile(
                shellDirectory.appending(path: "surfaces.txt", directoryHint: .notDirectory)
            )
        }

        var sources = try surfacesURLs.map(readText(from:))
        let aliasURL = shellDirectory.appending(path: "alias.txt", directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: aliasURL.path) {
            try sources.append(readText(from: aliasURL))
        }
        let existingSurfaceIDs = try Set(fileManager.contentsOfDirectory(atPath: shellDirectory.path).compactMap {
            surfaceID(fromImageFilename: $0)
        })
        let document = parser.parseDocument(
            sources.joined(separator: "\n"),
            existingSurfaceIDs: existingSurfaceIDs
        )
        let shellMetadata = metadata(in: shellDirectory)
        return ShellDefinition(
            directory: shellDirectory,
            surfaces: document.surfaces,
            surfaceAliases: document.aliases,
            usesSelfAlpha: shellMetadata.usesSelfAlpha,
            defaultBindGroups: shellMetadata.defaultBindGroups
        )
    }

    public func loadSurface(id: Int, from shellDirectory: URL) throws -> SurfaceAsset {
        let candidates = [
            String(format: "surface%04d", id),
            "surface\(id)"
        ]
        let fileManager = FileManager.default

        for basename in candidates {
            let imageURL = shellDirectory.appending(path: "\(basename).png", directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: imageURL.path) else { continue }

            let maskURL = shellDirectory.appending(path: "\(basename).pna", directoryHint: .notDirectory)
            return SurfaceAsset(
                id: id,
                imageURL: imageURL,
                alphaMaskURL: fileManager.fileExists(atPath: maskURL.path) ? maskURL : nil
            )
        }

        throw ShellError.missingSurface(id: id, directory: shellDirectory)
    }

    public func loadElement(filename: String, from shellDirectory: URL) throws -> SurfaceAsset {
        let root = shellDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedFilename = filename.replacingOccurrences(of: "\\", with: "/")
        let imageURL = shellDirectory
            .appending(path: normalizedFilename, directoryHint: .notDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard imageURL.pathExtension.lowercased() == "png",
              imageURL.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: imageURL.path)
        else {
            throw ShellError.missingElement(filename: filename, directory: shellDirectory)
        }

        let maskURL = imageURL.deletingPathExtension().appendingPathExtension("pna")
        return SurfaceAsset(
            id: -1,
            imageURL: imageURL,
            alphaMaskURL: FileManager.default.fileExists(atPath: maskURL.path) ? maskURL : nil
        )
    }

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else {
            throw ShellError.unsupportedTextEncoding(url)
        }
        return text
    }

    private func metadata(in shellDirectory: URL) -> (usesSelfAlpha: Bool, defaultBindGroups: [Int: Set<Int>]) {
        let url = shellDirectory.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard let text = try? readText(from: url) else { return (false, [:]) }
        var usesSelfAlpha = false
        var defaultBindGroups: [Int: Set<Int>] = [:]
        for line in text.split(whereSeparator: \ .isNewline) {
            let fields = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count == 2, fields[1] == "1" else { continue }
            if fields[0].caseInsensitiveCompare("seriko.use_self_alpha") == .orderedSame {
                usesSelfAlpha = true
                continue
            }
            let key = fields[0].lowercased()
            let scope: Int
            let remainder: Substring
            if key.hasPrefix("sakura.bindgroup") {
                scope = 0
                remainder = key.dropFirst("sakura.bindgroup".count)
            } else if key.hasPrefix("kero.bindgroup") {
                scope = 1
                remainder = key.dropFirst("kero.bindgroup".count)
            } else if key.hasPrefix("char"), let separator = key.firstIndex(of: ".") {
                guard let parsedScope = Int(key[key.index(key.startIndex, offsetBy: 4) ..< separator]),
                      key[separator...].hasPrefix(".bindgroup")
                else { continue }
                scope = parsedScope
                remainder = key[key.index(separator, offsetBy: ".bindgroup".count)...]
            } else {
                continue
            }
            guard remainder.hasSuffix(".default"),
                  let groupID = Int(remainder.dropLast(".default".count))
            else { continue }
            defaultBindGroups[scope, default: []].insert(groupID)
        }
        return (usesSelfAlpha, defaultBindGroups)
    }

    private func surfaceID(fromImageFilename filename: String) -> Int? {
        let lowercased = filename.lowercased()
        guard lowercased.hasPrefix("surface"), lowercased.hasSuffix(".png") else { return nil }
        return Int(lowercased.dropFirst("surface".count).dropLast(".png".count))
    }
}

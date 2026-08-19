import Foundation

public struct InstalledHeadline: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case rss(feedURL: URL)
        case legacyDLL(fileName: String)
    }

    public let id: URL
    public let name: String
    public let siteURL: URL?
    public let kind: Kind

    public init(id: URL, name: String, siteURL: URL?, kind: Kind) {
        self.id = id
        self.name = name
        self.siteURL = siteURL
        self.kind = kind
    }
}

public struct HeadlineCatalog: Sendable {
    public init() {}

    public func load(from root: URL) throws -> [InstalledHeadline] {
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap(Self.load).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func load(directory: URL) -> InstalledHeadline? {
        let descriptor = directory.appending(path: "descript.txt")
        guard let data = try? Data(contentsOf: descriptor), let metadata = metadata(from: data) else { return nil }
        let name = metadata["name"] ?? directory.lastPathComponent
        let siteURL = metadata["url"].flatMap(URL.init(string:))
        if metadata["type"]?.lowercased() == "rss", let value = metadata["feed"], let feedURL = URL(string: value) {
            return InstalledHeadline(id: directory, name: name, siteURL: siteURL, kind: .rss(feedURL: feedURL))
        }
        if let dllName = metadata["dllname"] {
            return InstalledHeadline(id: directory, name: name, siteURL: siteURL, kind: .legacyDLL(fileName: dllName))
        }
        return nil
    }

    private static func metadata(from data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .ascii)
        else { return nil }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
            if fields.count == 2 {
                result[fields[0].trimmingCharacters(in: .whitespaces).lowercased()] = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }
}

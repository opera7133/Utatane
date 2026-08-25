import Foundation

public struct ReadmeDocument: Sendable, Equatable {
    public let url: URL
    public let charset: String?

    public init(url: URL, charset: String?) {
        self.url = url
        self.charset = charset
    }
}

public struct ReadmeResolver: Sendable {
    private let parser = DescriptParser()

    public init() {}

    public func resolve(contentDirectory: URL, descriptorURL: URL) -> ReadmeDocument? {
        let metadata = try? parser.parse(contentsOf: descriptorURL)
        let candidates: [String] = if let configured = metadata?["readme"], !configured.isEmpty {
            [configured]
        } else {
            ["readme.txt", "README.txt", "readme.md", "README.md"]
        }
        let root = contentDirectory.resolvingSymlinksInPath().standardizedFileURL
        for candidate in candidates {
            guard !candidate.hasPrefix("/"), !candidate.contains("\\") else { continue }
            let url = root.appending(path: candidate).resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(root.path + "/"),
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }
            return ReadmeDocument(url: url, charset: metadata?["readme.charset"])
        }
        return nil
    }
}

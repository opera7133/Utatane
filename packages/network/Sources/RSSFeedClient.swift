import Foundation

public struct RSSFeed: Sendable, Equatable {
    public let title: String
    public let link: String
    public let items: [RSSFeedItem]

    public init(title: String, link: String, items: [RSSFeedItem]) {
        self.title = title
        self.link = link
        self.items = items
    }
}

public struct RSSFeedItem: Sendable, Equatable {
    public let title: String
    public let link: String
    public let summary: String
    public let author: String
    public let published: String

    public init(title: String, link: String, summary: String = "", author: String = "", published: String = "") {
        self.title = title
        self.link = link
        self.summary = summary
        self.author = author
        self.published = published
    }
}

public enum RSSFeedError: LocalizedError, Equatable, Sendable {
    case invalidXML
    case noItems

    public var errorDescription: String? {
        switch self {
        case .invalidXML: "RSS/Atomを解析できない"
        case .noItems: "RSS/Atomに項目がない"
        }
    }
}

public struct RSSFeedClient: Sendable {
    public init() {}

    public func fetch(_ url: URL) async throws -> RSSFeed {
        let data = try await NetworkFetchClient(maximumBytes: 5 * 1024 * 1024).fetch(url)
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> RSSFeed {
        let delegate = RSSParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.parseError == nil else { throw RSSFeedError.invalidXML }
        guard !delegate.items.isEmpty else { throw RSSFeedError.noItems }
        return RSSFeed(title: delegate.feedTitle, link: delegate.feedLink, items: delegate.items)
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    var feedTitle = ""
    var feedLink = ""
    var items: [RSSFeedItem] = []
    var parseError: Error?
    private var path: [String] = []
    private var text = ""
    private var current: [String: String]?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        path.append(name)
        text = ""
        if name == "item" || name == "entry" {
            current = [:]
        }
        if name == "link", let href = attributeDict["href"] {
            if current != nil {
                current?["link"] = href
            } else if feedLink.isEmpty {
                feedLink = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if var item = current {
            switch name {
            case "title", "link", "description", "summary", "content", "author", "creator", "pubdate", "published", "updated":
                if !value.isEmpty {
                    item[name] = value
                }
                current = item
            default: break
            }
            if name == "item" || name == "entry" {
                items.append(RSSFeedItem(
                    title: item["title"] ?? "",
                    link: item["link"] ?? "",
                    summary: item["description"] ?? item["summary"] ?? item["content"] ?? "",
                    author: item["author"] ?? item["creator"] ?? "",
                    published: item["pubdate"] ?? item["published"] ?? item["updated"] ?? ""
                ))
                current = nil
            }
        } else if name == "title", feedTitle.isEmpty {
            feedTitle = value
        } else if name == "link", feedLink.isEmpty {
            feedLink = value
        }
        _ = path.popLast()
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

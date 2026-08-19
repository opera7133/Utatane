import Foundation

public struct HeadlineSensorItem: Sendable, Equatable, Hashable {
    public let title: String
    public let url: String?

    public init(title: String, url: String? = nil) {
        self.title = title
        self.url = url
    }
}

public enum ConfigHeadlineSensorError: LocalizedError, Equatable, Sendable {
    case missingConfig(URL)
    case invalidConfig(URL)
    case unsupportedEncoding(String)
    case parseBoundaryNotFound

    public var errorDescription: String? {
        switch self {
        case let .missingConfig(url): "HEADLINE設定が見つからない: \(url.path)"
        case let .invalidConfig(url): "HEADLINE設定を解析できない: \(url.path)"
        case let .unsupportedEncoding(name): "HEADLINEの文字コードに対応していない: \(name)"
        case .parseBoundaryNotFound: "HEADLINEの解析範囲がHTML内に見つからない"
        }
    }
}

public struct ConfigHeadlineSensor: Sendable {
    private struct Configuration: Sendable {
        let parseStart: String
        let parseEnd: String
        let elementStart: String
        let elementEnd: String
        let headlinePrefix: String
        let charset: String
    }

    public init() {}

    public static func canLoad(_ headline: InstalledHeadline) -> Bool {
        FileManager.default.fileExists(
            atPath: headline.id.appending(path: "config.txt", directoryHint: .notDirectory).path
        )
    }

    public func analyze(
        headline: InstalledHeadline,
        oldData: Data?,
        newData: Data
    ) throws -> [HeadlineSensorItem] {
        let configuration = try loadConfiguration(for: headline)
        let oldItems = try oldData.map {
            try items(from: $0, baseURL: headline.openURL ?? headline.siteURL, configuration: configuration)
        } ?? []
        let newItems = try items(
            from: newData,
            baseURL: headline.openURL ?? headline.siteURL,
            configuration: configuration
        )
        guard !headline.alwaysDisplay else { return newItems }
        let oldSet = Set(oldItems)
        return newItems.filter { !oldSet.contains($0) }
    }

    private func loadConfiguration(for headline: InstalledHeadline) throws -> Configuration {
        let url = headline.id.appending(path: "config.txt", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url) else {
            throw ConfigHeadlineSensorError.missingConfig(url)
        }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else { throw ConfigHeadlineSensorError.invalidConfig(url) }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            values[String(fields[0]).trimmingCharacters(in: .whitespaces).lowercased()] =
                String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let parseStart = values["parse.start"],
              let parseEnd = values["parse.end"],
              let elementStart = values["element.start"],
              let elementEnd = values["element.end"]
        else { throw ConfigHeadlineSensorError.invalidConfig(url) }
        return Configuration(
            parseStart: parseStart,
            parseEnd: parseEnd,
            elementStart: elementStart,
            elementEnd: elementEnd,
            headlinePrefix: values["headline.head"] ?? "",
            charset: values["charset"] ?? headline.charset
        )
    }

    private func items(
        from data: Data,
        baseURL: URL?,
        configuration: Configuration
    ) throws -> [HeadlineSensorItem] {
        guard let html = decode(data, charset: configuration.charset) else {
            throw ConfigHeadlineSensorError.unsupportedEncoding(configuration.charset)
        }
        guard let parseStart = html.range(of: configuration.parseStart),
              let parseEnd = html.range(
                  of: configuration.parseEnd,
                  range: parseStart.upperBound ..< html.endIndex
              )
        else { throw ConfigHeadlineSensorError.parseBoundaryNotFound }

        let body = String(html[parseStart.upperBound ..< parseEnd.lowerBound])
        var cursor = body.startIndex
        var result: [HeadlineSensorItem] = []
        while let start = body.range(of: configuration.elementStart, range: cursor ..< body.endIndex),
              let end = body.range(of: configuration.elementEnd, range: start.upperBound ..< body.endIndex)
        {
            let fragment = String(body[start.lowerBound ..< end.upperBound])
            let content = plainText(fragment)
            if !content.isEmpty {
                result.append(HeadlineSensorItem(
                    title: configuration.headlinePrefix + content,
                    url: link(in: fragment, relativeTo: baseURL)
                ))
            }
            cursor = end.upperBound
        }
        return result
    }

    private func decode(_ data: Data, charset: String) -> String? {
        switch charset.lowercased().replacingOccurrences(of: "-", with: "") {
        case "utf8": String(data: data, encoding: .utf8)
        case "shiftjis", "sjis", "cp932", "osnative": String(data: data, encoding: .shiftJIS)
        default: nil
        }
    }

    private func plainText(_ html: String) -> String {
        decodeEntities(
            html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        )
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    }

    private func link(in html: String, relativeTo baseURL: URL?) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)href\s*=\s*["']([^"']+)["']"#
        ), let match = expression.firstMatch(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ), let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = decodeEntities(String(html[range]))
        return URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    private func decodeEntities(_ source: String) -> String {
        var result = source
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let expression = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#)
        let matches = (expression?.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ) ?? []).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result)
            else { continue }
            let value = String(result[valueRange])
            let number = value.lowercased().hasPrefix("x")
                ? UInt32(value.dropFirst(), radix: 16)
                : UInt32(value, radix: 10)
            if let number, let scalar = UnicodeScalar(number) {
                result.replaceSubrange(whole, with: String(scalar))
            }
        }
        return result
    }
}

import CryptoKit
import Foundation

public enum URLInstallPayload: String, Sendable {
    case nar, feed, homeurl, ical, ssf

    public static func detect(data: Data, url: URL, contentType: String? = nil) -> Self? {
        if data.starts(with: [0x50, 0x4B]) {
            return .nar
        }
        let text = String(data: data.prefix(4096), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if text.contains("begin:vcalendar") {
            return .ical
        }
        if text.contains("<rss") || text.contains("<feed") || text.contains("<rdf:rdf") {
            return .feed
        }
        if text.contains("type,sakura_script_file") {
            return .ssf
        }
        switch url.pathExtension.lowercased() {
        case "nar", "zip": return .nar
        case "ics": return .ical
        case "ssf": return .ssf
        default: break
        }
        let mime = contentType?.lowercased() ?? ""
        if mime.contains("text/calendar") {
            return .ical
        }
        if mime.contains("rss") || mime.contains("atom") {
            return .feed
        }
        return nil
    }
}

public struct NetworkSensorStore: Sendable {
    public init() {}

    @discardableResult
    public func register(url: URL, name: String, type: URLInstallPayload, root: URL) throws -> URL {
        guard [.feed, .ical].contains(type), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw NetworkFetchError.unsupportedURL
        }
        let id = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = root.appending(path: "url-" + id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = name.components(separatedBy: .newlines).joined(separator: " ")
        let descriptor = type == .feed
            ? "type,rss\nname,\(safeName)\nfeed,\(url.absoluteString)\n"
            : "type,ical\nname,\(safeName)\nurl,\(url.absoluteString)\n"
        try descriptor.write(to: directory.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        return directory
    }
}

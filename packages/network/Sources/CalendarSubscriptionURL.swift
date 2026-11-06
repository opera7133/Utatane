import Foundation

/// Calendar drop links use the same HTTPS identity for fetching and persistence.
public enum CalendarSubscriptionURL {
    public static func matches(_ url: URL) -> Bool {
        ["webcal", "webcals"].contains(url.scheme?.lowercased() ?? "")
    }

    public static func normalized(_ url: URL) throws -> URL {
        guard matches(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty
        else { throw NetworkFetchError.unsupportedURL }
        components.scheme = "https"
        components.fragment = nil
        guard let result = components.url else { throw NetworkFetchError.unsupportedURL }
        return result
    }
}

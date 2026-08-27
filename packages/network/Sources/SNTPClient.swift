import Foundation

public struct SNTPComparison: Sendable, Equatable {
    public let server: String
    public let serverDate: Date
    public let localDate: Date

    public init(server: String, serverDate: Date, localDate: Date) {
        self.server = server
        self.serverDate = serverDate
        self.localDate = localDate
    }

    public var offset: TimeInterval {
        serverDate.timeIntervalSince(localDate)
    }

    public var extendedReferences: [Int: String] {
        [
            0: server,
            1: Self.components(serverDate, milliseconds: true),
            2: Self.components(localDate, milliseconds: true),
            3: Self.seconds(offset),
            4: String(Int((offset * 1000).rounded()))
        ]
    }

    public var legacyReferences: [Int: String] {
        [
            0: server,
            1: Self.components(serverDate, milliseconds: false),
            2: Self.components(localDate, milliseconds: false),
            3: String(Int(abs(offset).rounded(.down))),
            4: String(abs(Int((offset * 1000).rounded())))
        ]
    }

    public var correctedLegacyReferences: [Int: String] {
        var references = legacyReferences
        references[3] = String(Int(offset.rounded(.towardZero)))
        references[4] = String(Int((offset * 1000).rounded()))
        return references
    }

    private static func components(_ date: Date, milliseconds: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let values = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        var result = [values.year, values.month, values.day, values.hour, values.minute, values.second]
            .map { String($0 ?? 0) }
        if milliseconds {
            result.append(String((values.nanosecond ?? 0) / 1_000_000))
        }
        return result.joined(separator: ",")
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public struct SNTPClient: Sendable {
    public typealias FetchDate = @Sendable (URL) async throws -> Date

    private let fetchDate: FetchDate

    public init(fetchDate: @escaping FetchDate = SNTPClient.fetchHTTPDate) {
        self.fetchDate = fetchDate
    }

    public func compare(server: URL, now: @Sendable () -> Date = Date.init) async throws -> SNTPComparison {
        let serverDate = try await fetchDate(server)
        return SNTPComparison(server: server.absoluteString, serverDate: serverDate, localDate: now())
    }

    public static func fetchHTTPDate(_ server: URL) async throws -> Date {
        var request = URLRequest(url: server, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 400).contains(response.statusCode),
              let value = response.value(forHTTPHeaderField: "Date"),
              let date = HTTPDateParser.date(from: value)
        else {
            throw URLError(.badServerResponse)
        }
        return date
    }
}

private enum HTTPDateParser {
    static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

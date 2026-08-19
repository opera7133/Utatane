import Foundation

public enum NetworkFetchError: LocalizedError, Equatable, Sendable {
    case unsupportedURL
    case responseTooLarge
    case unsuccessfulStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL: "HTTPまたはHTTPSのURLではない"
        case .responseTooLarge: "取得データが上限を超えている"
        case let .unsuccessfulStatus(status): "HTTPエラー: \(status)"
        }
    }
}

public struct NetworkFetchClient: Sendable {
    public let maximumBytes: Int

    public init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw NetworkFetchError.unsupportedURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw NetworkFetchError.unsuccessfulStatus(0)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw NetworkFetchError.unsuccessfulStatus(response.statusCode)
        }
        guard data.count <= maximumBytes else { throw NetworkFetchError.responseTooLarge }
        return data
    }
}

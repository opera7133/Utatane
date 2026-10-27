import Foundation
import UtataneShiori

public struct PluginRequest: Sendable, Equatable {
    public let method: String
    public let headers: ShioriHeaders

    public init(method: String, id: String, charset: String = "UTF-8", sender: String? = nil,
                language: String = PluginLanguage.preferredHeader, references: [Int: String] = [:])
    {
        self.method = method
        var headers = ShioriHeaders([
            ShioriHeader(name: "ID", value: id),
            ShioriHeader(name: "Charset", value: charset),
            ShioriHeader(name: "Language", value: language)
        ])
        if let sender {
            headers.append(name: "Sender", value: sender)
        }
        for (index, value) in references.sorted(by: { $0.key < $1.key }) {
            headers.append(name: "Reference\(index)", value: value)
        }
        self.headers = headers
    }

    public func serialized() -> String {
        shioriRequest.serialized()
    }

    public var shioriRequest: ShioriRequest {
        ShioriRequest(method: method, version: "PLUGIN/2.0", headers: headers)
    }
}

public enum PluginLanguage {
    public static var preferredHeader: String {
        header(for: Locale.preferredLanguages.first ?? "en")
    }

    public static func header(for identifier: String) -> String {
        let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
        return Locale(identifier: "en_US_POSIX").localizedString(forLanguageCode: code) ?? "English"
    }
}

public struct PluginResponse: Sendable, Equatable {
    public let statusCode: Int
    public let headers: ShioriHeaders

    public init(statusCode: Int, headers: ShioriHeaders = ShioriHeaders()) {
        self.statusCode = statusCode
        self.headers = headers
    }

    public init(_ response: ShioriResponse) {
        self.init(statusCode: response.statusCode, headers: response.headers)
    }

    public var event: String? {
        headers["Event"]
    }

    public var script: String? {
        headers["Script"]
    }

    public var target: String? {
        headers["Target"]
    }

    public var references: [Int: String] {
        ShioriResponse(statusCode: statusCode, reasonPhrase: "", headers: headers).referenceValues
    }

    public static func parse(_ message: String) throws -> PluginResponse {
        let response = try ShioriMessageParser.parseResponse(message)
        return PluginResponse(statusCode: response.statusCode, headers: response.headers)
    }
}

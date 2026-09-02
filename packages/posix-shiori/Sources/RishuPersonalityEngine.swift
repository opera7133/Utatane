import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor RishuPersonalityEngine: PersonalityEngine {
    private let session: RishuSession
    private let adapter = GhostEventShioriAdapter()

    public init(masterDirectoryURL: URL) throws {
        session = try RishuSession(masterDirectoryURL: masterDirectoryURL)
    }

    public static func supports(masterDirectoryURL: URL, shioriFilename: String?) -> Bool {
        guard shioriFilename?.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?
            .caseInsensitiveCompare("rishu_proxy.dll") == .orderedSame
        else { return false }
        return RishuSession.remoteScriptURL(in: masterDirectoryURL) != nil
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let raw = try await session.request(adapter.request(for: event).serialized())
        let response = try ShioriMessageParser.parseResponse(raw)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw RishuError.protocolFailure("SHIORI returned \(response.statusCode)")
        }
        return PersonalityResponse(
            script: response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) },
            references: response.referenceValues
        )
    }

    public func shutdown() async {
        await session.close()
    }
}

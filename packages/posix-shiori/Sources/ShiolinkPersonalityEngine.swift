import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor ShiolinkPersonalityEngine: PersonalityEngine {
    private let session: ShiolinkSession
    private let charset: String
    private let adapter = GhostEventShioriAdapter()

    public init(masterDirectoryURL: URL) throws {
        let configuration = try ShiolinkConfiguration(directory: masterDirectoryURL)
        session = ShiolinkSession(configuration: configuration)
        charset = configuration.charset
    }

    public static func supports(shioriFilename: String?) -> Bool {
        shioriFilename?.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased() == "shiolink.dll"
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func shutdown() async {
        await session.close()
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        var context = ShioriEventContext(charset: charset)
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        } else if case let .mouse(mouseEvent) = event {
            context.scope = mouseEvent.scope
            context.mouseX = mouseEvent.x
            context.mouseY = mouseEvent.y
            context.mouseButton = mouseEvent.button
        }
        let raw = try await session.request(adapter.request(for: event, context: context).serialized())
        let response = try ShioriMessageParser.parseResponse(raw)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ShiolinkError.protocolFailure("SHIORI returned \(response.statusCode)")
        }
        return PersonalityResponse(
            script: response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) },
            references: response.referenceValues
        )
    }
}

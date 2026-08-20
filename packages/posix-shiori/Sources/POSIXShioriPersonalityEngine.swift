import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor POSIXShioriPersonalityEngine: PersonalityEngine {
    private let session: POSIXShioriSession
    private let adapter = GhostEventShioriAdapter()
    private let charset: String

    public init(
        masterDirectoryURL: URL,
        resolver: POSIXShioriModuleResolver = POSIXShioriModuleResolver()
    ) throws {
        guard let kind = resolver.kind(for: masterDirectoryURL) else {
            throw POSIXShioriError.unsupportedGhost
        }
        guard let moduleURL = resolver.moduleURL(for: kind, masterDirectoryURL: masterDirectoryURL) else {
            throw POSIXShioriError.moduleUnavailable(kind)
        }
        session = try POSIXShioriSession(
            masterDirectoryURL: masterDirectoryURL,
            moduleURL: moduleURL,
            kind: kind
        )
        charset = kind.charset
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        POSIXShioriModuleResolver().kind(for: masterDirectoryURL) != nil
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
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
        let response = try session.request(adapter.request(for: event, context: context))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw POSIXShioriError.requestFailed
        }
        let script = response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: response.referenceValues)
    }
}

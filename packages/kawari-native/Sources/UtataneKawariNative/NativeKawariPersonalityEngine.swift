import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor NativeKawariPersonalityEngine: PersonalityEngine {
    private let session: NativeKawariSession
    private let adapter = GhostEventShioriAdapter()

    public init(masterDirectoryURL: URL) throws {
        session = try NativeKawariSession(masterDirectoryURL: masterDirectoryURL)
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        ["kawarirc.kis", "kawari.ini"].contains { filename in
            FileManager.default.fileExists(
                atPath: masterDirectoryURL.appending(path: filename).path
            )
        }
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        var context = ShioriEventContext(charset: "Shift_JIS")
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
            throw NativeKawariError.requestFailed
        }
        let script = response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: response.referenceValues)
    }
}

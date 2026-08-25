import Foundation
import UtataneCore
import UtataneNativeSaori
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor NativeMisakaPersonalityEngine: PersonalityEngine {
    private let session: NativeMisakaSession
    private let adapter = GhostEventShioriAdapter()

    public init(
        masterDirectoryURL: URL,
        variableStoreURL: URL? = nil,
        saoriCaller: (any NativeSaoriCalling)? = nil
    ) throws {
        session = try NativeMisakaSession(
            masterDirectoryURL: masterDirectoryURL,
            variableStoreURL: variableStoreURL,
            saoriCaller: saoriCaller ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        )
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: masterDirectoryURL.appending(path: "misaka.ini").path)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        var context = ShioriEventContext(charset: "Shift_JIS")
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        }
        if case let .mouse(mouseEvent) = event {
            context.scope = mouseEvent.scope
            context.mouseX = mouseEvent.x
            context.mouseY = mouseEvent.y
            context.mouseButton = mouseEvent.button
        }
        let result = try session.request(adapter.request(for: event, context: context))
        let script = result.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: result.referenceValues)
    }
}

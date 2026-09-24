import Foundation
import UtataneCore
import UtataneModuleHost
import UtataneNativeSaori
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor NativeMisakaPersonalityEngine: PersonalityEngine {
    private let session: MisakaEngineSession
    private let adapter = GhostEventShioriAdapter()

    public init(
        masterDirectoryURL: URL,
        variableStoreURL: URL? = nil,
        saoriCaller: (any NativeSaoriCalling)? = nil,
        moduleResolver: UtataneModuleResolver = .init()
    ) throws {
        session = try MisakaEngineSession(
            masterDirectoryURL: masterDirectoryURL,
            variableStoreURL: variableStoreURL,
            saoriCaller: saoriCaller,
            moduleResolver: moduleResolver
        )
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: masterDirectoryURL.appending(path: "misaka.ini").path)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func shutdown() async {
        do { try session.close() }
        catch { NSLog("MISAKA save failed during shutdown: %@", error.localizedDescription) }
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
        let request = adapter.request(for: event, context: context)
        let result = try session.request(request)
        let script = result.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: result.referenceValues)
    }
}

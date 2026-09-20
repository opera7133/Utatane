import Foundation
import UtataneCore
import UtataneNativeSaori
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public enum NativeSatoriPersonalityError: LocalizedError, Equatable, Sendable {
    case unsuccessfulResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .unsuccessfulResponse(statusCode, reason):
            "SATORIがエラーを返した: \(statusCode) \(reason)"
        }
    }
}

public actor NativeSatoriPersonalityEngine: PersonalityEngine {
    private let session: NativeSatoriSession
    private let adapter = GhostEventShioriAdapter()

    public init(masterDirectoryURL: URL, saoriRegistry: NativeSaoriRegistry? = nil) throws {
        session = try NativeSatoriSession(masterDirectoryURL: masterDirectoryURL, saoriRegistry: saoriRegistry)
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "satori_conf.txt").path)
            || fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "satori.dll").path)
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
            throw NativeSatoriPersonalityError.unsuccessfulResponse(response.statusCode, response.reasonPhrase)
        }
        let script = response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: response.referenceValues)
    }
}

import Foundation
import UtataneCore
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

    public init(masterDirectoryURL: URL) throws {
        session = try NativeSatoriSession(masterDirectoryURL: masterDirectoryURL)
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "satori_conf.txt").path)
            || fileManager.fileExists(atPath: masterDirectoryURL.appending(path: "satori.dll").path)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        let requestEvent: GhostEvent
        if case let .choice(id, arguments) = event, !id.hasPrefix("On") {
            var references = Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                ($0.offset + 1, $0.element)
            })
            references[0] = id
            requestEvent = .shiori(id: "OnChoiceSelect", references: references)
        } else {
            requestEvent = event
        }
        var context = ShioriEventContext(charset: "Shift_JIS")
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        } else if case let .mouse(mouseEvent) = event {
            context.scope = mouseEvent.scope
            context.mouseX = mouseEvent.x
            context.mouseY = mouseEvent.y
            context.mouseButton = mouseEvent.button
        }
        let response = try session.request(adapter.request(for: requestEvent, context: context))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw NativeSatoriPersonalityError.unsuccessfulResponse(response.statusCode, response.reasonPhrase)
        }
        guard let value = response.value, !value.isEmpty else { return nil }
        return SakuraScript(rawValue: value)
    }
}

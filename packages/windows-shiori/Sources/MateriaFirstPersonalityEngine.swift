import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public enum MateriaFirstPersonalityError: LocalizedError, Equatable, Sendable {
    case unsuccessfulResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .unsuccessfulResponse(statusCode, reason):
            "FIRSTがエラーを返した: \(statusCode) \(reason)"
        }
    }
}

public actor MateriaFirstPersonalityEngine: PersonalityEngine {
    private let configuration: WindowsShioriProcessConfiguration
    private let adapter = GhostEventShioriAdapter()
    private var session: WindowsShioriProcessSession?

    public init(configuration: WindowsShioriProcessConfiguration) {
        self.configuration = configuration
    }

    public static func supports(shioriFilename: String?) -> Bool {
        shioriFilename?.caseInsensitiveCompare("first.dll") == .orderedSame
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let requestEvent = normalized(event)
        var context = ShioriEventContext(sender: "materia", charset: "Shift_JIS")
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        } else if case let .mouse(mouseEvent) = event {
            context.scope = mouseEvent.scope
            context.mouseX = mouseEvent.x
            context.mouseY = mouseEvent.y
            context.mouseButton = mouseEvent.button
        }

        let request = adapter.request(for: requestEvent, context: context)
        let activeSession = try await activeSession()
        let response = try await Task.detached {
            try activeSession.request(request)
        }.value
        if case .close = event {
            activeSession.close()
            session = nil
        } else if case .ghostChanging = event {
            activeSession.close()
            session = nil
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw MateriaFirstPersonalityError.unsuccessfulResponse(
                response.statusCode,
                response.reasonPhrase
            )
        }
        let initialScope: Int = switch event {
        case let .mouseClick(scope, _): scope
        case let .mouse(mouseEvent): mouseEvent.scope
        default: 0
        }
        let script = response.value.flatMap {
            $0.isEmpty ? nil : SakuraScript(
                rawValue: Self.normalizeLegacyKeroSurfaces(in: $0, initialScope: initialScope)
            )
        }
        return PersonalityResponse(script: script, references: response.referenceValues)
    }

    public static func normalizeLegacyKeroSurfaces(
        in script: String,
        initialScope: Int = 0
    ) -> String {
        let characters = Array(script)
        var result = ""
        var index = 0
        var scope = initialScope

        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                result.append(characters[index])
                index += 1
                continue
            }
            let command = characters[index + 1]
            if command == "0" || command == "h" {
                scope = 0
            } else if command == "1" || command == "u" {
                scope = 1
            } else if command == "p", index + 3 < characters.count,
                      characters[index + 2] == "[",
                      let closing = characters[(index + 3)...].firstIndex(of: "]"),
                      let selectedScope = Int(String(characters[(index + 3) ..< closing]))
            {
                scope = selectedScope
            }
            guard command == "s", scope == 1 else {
                result.append(characters[index])
                result.append(command)
                index += 2
                continue
            }

            if index + 2 < characters.count,
               let surface = characters[index + 2].wholeNumberValue
            {
                result += "\\s[\(surface + 10)]"
                index += 3
            } else if index + 3 < characters.count, characters[index + 2] == "[",
                      let closing = characters[(index + 3)...].firstIndex(of: "]"),
                      let surface = Int(String(characters[(index + 3) ..< closing])),
                      (0 ... 9).contains(surface)
            {
                result += "\\s[\(surface + 10)]"
                index = closing + 1
            } else {
                result += "\\s"
                index += 2
            }
        }
        return result
    }

    private func activeSession() async throws -> WindowsShioriProcessSession {
        if let session {
            return session
        }
        let configuration = configuration
        let created = try await Task.detached {
            try WindowsShioriProcessSession(configuration: configuration)
        }.value
        session = created
        return created
    }

    private func normalized(_ event: GhostEvent) -> GhostEvent {
        guard case let .choice(id, arguments) = event, !id.hasPrefix("On") else {
            return event
        }
        var references = Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
            ($0.offset + 1, $0.element)
        })
        references[0] = id
        return .shiori(id: "OnChoiceSelect", references: references)
    }
}

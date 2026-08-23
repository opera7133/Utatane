import Foundation
import UtataneCore

public struct AIPersonalityInput: Codable, Sendable, Equatable {
    public let event: String
    public let references: [String: String]
    public let timestamp: String

    public init(event: String, references: [String: String], timestamp: String) {
        self.event = event
        self.references = references
        self.timestamp = timestamp
    }

    init(event: GhostEvent, date: Date) {
        let mapped = Self.map(event)
        self.init(
            event: mapped.0,
            references: mapped.1,
            timestamp: ISO8601DateFormatter().string(from: date)
        )
    }

    private static func map(_ event: GhostEvent) -> (String, [String: String]) {
        switch event {
        case .boot: ("OnBoot", [:])
        case .close: ("OnClose", [:])
        case let .ghostChanging(name): ("OnGhostChanging", ["name": name ?? ""])
        case let .mouseClick(scope, region):
            ("OnMouseClick", ["scope": String(scope), "region": region ?? ""])
        case let .mouse(mouse):
            (mouse.eventName, [
                "scope": String(mouse.scope), "region": mouse.region ?? "",
                "x": String(mouse.x), "y": String(mouse.y), "button": String(mouse.button)
            ])
        case let .shiori(id, references):
            (id, Dictionary(uniqueKeysWithValues: references.map { (String($0.key), $0.value) }))
        case .randomTalk: ("OnAITalk", [:])
        case let .choice(id, arguments):
            ("OnChoiceSelect", ["id": id, "arguments": arguments.joined(separator: "\u{1}")])
        }
    }
}

private extension GhostMouseEvent {
    var eventName: String {
        switch kind {
        case .move: "OnMouseMove"
        case .click: "OnMouseClick"
        case .doubleClick: "OnMouseDoubleClick"
        case .wheel: "OnMouseWheel"
        }
    }
}

public struct AIPersonalityOutput: Codable, Sendable, Equatable {
    public struct Speech: Codable, Sendable, Equatable {
        public let text: String
        public let surface: Int

        public init(text: String, surface: Int) {
            self.text = text
            self.surface = surface
        }
    }

    public let speech: Speech?

    public init(speech: Speech?) {
        self.speech = speech
    }
}

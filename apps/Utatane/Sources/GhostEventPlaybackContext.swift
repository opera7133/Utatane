import UtataneCore
import UtatanePlatformMacOS
import UtataneSakuraScript

extension GhostEvent {
    var playbackContext: SakuraScriptPlaybackContext {
        switch self {
        case .boot:
            return .init(eventID: "OnBoot")
        case .close:
            return .init(eventID: "OnClose")
        case let .ghostChanging(name):
            return .init(eventID: "OnGhostChanging", references: name.map { [0: $0] } ?? [:])
        case let .shiori(id, references), let .notification(id, references):
            return .init(eventID: id, references: references)
        case .randomTalk:
            return .init(eventID: "OnAITalk")
        case let .choice(id, arguments):
            if id.hasPrefix("On") {
                return .init(
                    eventID: id,
                    references: Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                        ($0.offset, $0.element)
                    })
                )
            }
            var references = Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                ($0.offset + 1, $0.element)
            })
            references[0] = id
            return .init(eventID: "OnChoiceSelect", references: references)
        case let .mouseClick(scope, region):
            return .init(eventID: "OnMouseClick", references: [3: String(scope), 4: region ?? ""])
        case let .mouse(event):
            return .init(eventID: event.playbackEventID, references: [
                0: String(event.x), 1: String(event.y), 3: String(event.scope),
                4: event.region ?? "", 5: String(event.button)
            ])
        }
    }
}

extension SakuraScriptPlaybackContext {
    func translateReferences(script: SakuraScript) -> [Int: String] {
        var result = [0: script.rawValue]
        if !flags.isEmpty {
            result[1] = flags.joined(separator: ",")
        }
        if let eventID {
            result[2] = eventID
        }
        if let maximum = references.keys.max() {
            result[3] = (0 ... maximum).map { references[$0] ?? "" }.joined(separator: "\u{1}")
        }
        return result
    }
}

private extension GhostMouseEvent {
    var playbackEventID: String {
        switch kind {
        case .move: "OnMouseMove"
        case .enter: "OnMouseEnter"
        case .leave: "OnMouseLeave"
        case .enterAll: "OnMouseEnterAll"
        case .leaveAll: "OnMouseLeaveAll"
        case .down: "OnMouseDown"
        case .up: "OnMouseUp"
        case .click: "OnMouseClick"
        case .doubleClick: "OnMouseDoubleClick"
        case .multipleClick: "OnMouseMultipleClick"
        case .dragStart: "OnMouseDragStart"
        case .dragEnd: "OnMouseDragEnd"
        case .hover: "OnMouseHover"
        case .wheel: "OnMouseWheel"
        }
    }
}

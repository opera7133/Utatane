import Foundation
import UtataneCore
import UtataneSakuraScript

/// Identifies the plugin that supplied a dialogue and its one-use interaction hook.
public struct SakuraScriptPluginOrigin: Sendable, Equatable {
    public let id: String
    public let interactionID: UUID
    public let resourceDirectory: URL?
    public let generation: UUID?

    public init(id: String, interactionID: UUID = UUID(), resourceDirectory: URL? = nil, generation: UUID? = nil) {
        self.id = id
        self.interactionID = interactionID
        self.resourceDirectory = resourceDirectory
        self.generation = generation
    }
}

public struct SakuraScriptPluginPlayback: Sendable, Equatable {
    public let script: SakuraScript
    public let origin: SakuraScriptPluginOrigin?
    public let flags: [String]

    public init(script: SakuraScript, origin: SakuraScriptPluginOrigin? = nil, flags: [String] = []) {
        self.script = script
        self.origin = origin
        self.flags = flags
    }

    public var context: SakuraScriptPlaybackContext {
        .init(flags: flags, pluginOrigin: origin)
    }
}

public extension BalloonTextLink {
    /// Uses the same event ID/reference conventions as ghost choices and anchors.
    func pluginSelectionEvents(label: String) -> [(id: String, arguments: [String])] {
        let extended = kind == .anchor ? "OnAnchorSelectEx" : "OnChoiceSelectEx"
        let legacy = kind == .anchor ? "OnAnchorSelect" : "OnChoiceSelect"
        let fallback = kind == .anchor ? (legacy, [id]) : (id.hasPrefix("On") ? (id, arguments) : (legacy, [id] + arguments))
        return [(extended, [label, id] + arguments), fallback]
    }
}

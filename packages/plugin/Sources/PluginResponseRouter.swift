import Foundation

/// A snapshot of a running ghost, rather than an installed but inactive ghost.
public struct PluginGhostTarget: Sendable, Equatable {
    public let id: URL
    public let names: [String]

    public init(id: URL, names: [String]) {
        self.id = id
        self.names = names
    }
}

public struct PluginRoutedPlayback: Sendable, Equatable {
    public let ghostID: URL
    public let script: String
    public let flags: [String]
    public let isPluginScript: Bool
}

public enum PluginResponseRouter {
    public static func targets(for target: String?, callerID: URL?, running: [PluginGhostTarget]) -> [URL] {
        let name = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.caseInsensitiveCompare("__SYSTEM_ALL_GHOST__") == .orderedSame {
            return running.map(\.id)
        }
        if !name.isEmpty, let matched = running.first(where: { ghost in
            ghost.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }) {
            return [matched.id]
        }
        // UKADOC also assigns an unknown Target to one suitable running ghost.
        if let callerID, running.contains(where: { $0.id == callerID }) {
            return [callerID]
        }
        return Array(running.prefix(1).map(\.id))
    }

    @MainActor
    public static func route(
        _ response: PluginResponse,
        callerID: URL?,
        running: [PluginGhostTarget],
        handleEvent: (URL, String, [Int: String], Bool) async -> String?
    ) async -> [PluginRoutedPlayback] {
        guard response.statusCode == 200 else { return [] }
        let flags = options(response.headers["ScriptOption"])
        let notifies = options(response.headers["EventOption"]).contains("notify")
        var results: [PluginRoutedPlayback] = []
        for ghostID in targets(for: response.target, callerID: callerID, running: running) {
            var script = response.script
            var playbackFlags = flags + ["plugin-script"]
            var isPluginScript = true
            if let event = response.event, !event.isEmpty {
                let reply = await handleEvent(ghostID, event, response.references, notifies)
                if !notifies, let reply, !reply.isEmpty {
                    script = reply
                    // ScriptOption applies to the plugin's fallback, not the ghost's reply.
                    playbackFlags = ["plugin-event"]
                    isPluginScript = false
                }
            }
            if let script, !script.isEmpty {
                results.append(.init(ghostID: ghostID, script: script, flags: playbackFlags, isPluginScript: isPluginScript))
            }
        }
        return results
    }

    private static func options(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }
}

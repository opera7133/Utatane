import Foundation
import UtataneBalloon
import UtataneCore

@MainActor
public final class ContentSelectionStore {
    private let defaults: UserDefaults
    private let namespace: String

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = "dev.utatane.content-selection"
    ) {
        self.defaults = defaults
        self.namespace = namespace
    }

    public var ghostDirectoryName: String? {
        get { defaults.string(forKey: "\(namespace).ghost") }
        set { defaults.set(newValue, forKey: "\(namespace).ghost") }
    }

    public func shellDirectoryName(for ghostID: URL) -> String? {
        defaults.string(forKey: key("shell", ghostID: ghostID))
    }

    public func setShellDirectoryName(_ name: String, for ghostID: URL) {
        defaults.set(name, forKey: key("shell", ghostID: ghostID))
    }

    public func balloonDirectoryName(for ghostID: URL) -> String? {
        defaults.string(forKey: key("balloon", ghostID: ghostID))
    }

    public func setBalloonDirectoryName(_ name: String, for ghostID: URL) {
        defaults.set(name, forKey: key("balloon", ghostID: ghostID))
    }

    public func resolveShell(for ghost: InstalledGhost) -> InstalledShell? {
        let selected = ghost.shells.first {
            $0.directory.lastPathComponent == shellDirectoryName(for: ghost.id)
        } ?? ghost.shells.first {
            $0.directory == ghost.defaultShellDirectory
        } ?? ghost.shells.first
        if let selected {
            setShellDirectoryName(selected.directory.lastPathComponent, for: ghost.id)
        }
        return selected
    }

    public func resolveBalloon(
        for ghost: InstalledGhost,
        from balloons: [BalloonDefinition],
        defaultDirectoryName: String?
    ) -> BalloonDefinition? {
        let preferredNames = ([
            balloonDirectoryName(for: ghost.id),
            ghost.defaultBalloonDirectoryName,
            defaultDirectoryName
        ] as [String?]).compactMap { name -> String? in
            guard let name, !name.isEmpty else { return nil }
            return name
        }
        let selected = preferredNames.compactMap { name in
            balloons.first { $0.directory.lastPathComponent == name }
        }.first ?? balloons.first
        if let selected {
            setBalloonDirectoryName(selected.directory.lastPathComponent, for: ghost.id)
        }
        return selected
    }

    private func key(_ kind: String, ghostID: URL) -> String {
        let ghostKey = ghostID.standardizedFileURL.path
            .data(using: .utf8)?
            .base64EncodedString()
            ?? ghostID.lastPathComponent
        return "\(namespace).\(ghostKey).\(kind)"
    }
}

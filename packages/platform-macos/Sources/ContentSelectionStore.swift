import Foundation

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

    private func key(_ kind: String, ghostID: URL) -> String {
        let ghostKey = ghostID.standardizedFileURL.path
            .data(using: .utf8)?
            .base64EncodedString()
            ?? ghostID.lastPathComponent
        return "\(namespace).\(ghostKey).\(kind)"
    }
}

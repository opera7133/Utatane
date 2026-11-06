import Foundation

public struct GhostShioriSelection: Codable, Equatable, Sendable {
    public let modulePath: String
    public let kindID: String?

    public init(modulePath: String, kindID: String? = nil) {
        self.modulePath = modulePath
        self.kindID = kindID
    }

    public var kind: ConventionalShioriKind? {
        kindID.flatMap(ConventionalShioriKind.init(rawValue:))
            ?? ConventionalShioriKind(libraryFilename: URL(fileURLWithPath: modulePath).lastPathComponent)
    }

    public func validatedModuleURL() throws -> URL {
        guard modulePath.hasPrefix("/"), !modulePath.contains("\0"),
              kindID == nil || ConventionalShioriKind(rawValue: kindID!) != nil
        else { throw CocoaError(.fileReadInvalidFileName) }
        let url = URL(fileURLWithPath: modulePath).standardizedFileURL
        guard ["dylib", "so", "bundle"].contains(url.pathExtension.lowercased()) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }
}

/// Preferences follow the installed ghost's absolute directory, independently of its descriptor.
@MainActor
public struct GhostShioriSelectionStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func selection(for ghostDirectory: URL) throws -> GhostShioriSelection? {
        guard let data = defaults.data(forKey: key(ghostDirectory)) else { return nil }
        return try JSONDecoder().decode(GhostShioriSelection.self, from: data)
    }

    public func set(_ selection: GhostShioriSelection?, for ghostDirectory: URL) throws {
        if let selection {
            _ = try selection.validatedModuleURL()
            try defaults.set(JSONEncoder().encode(selection), forKey: key(ghostDirectory))
        } else {
            defaults.removeObject(forKey: key(ghostDirectory))
        }
    }

    private func key(_ directory: URL) -> String {
        "utatane.ghost.shioriSelection." + Data(directory.standardizedFileURL.path.utf8).base64EncodedString()
    }
}

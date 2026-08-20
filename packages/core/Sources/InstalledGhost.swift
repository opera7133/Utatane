import Foundation

public struct InstalledShell: Identifiable, Sendable, Equatable {
    public let name: String
    public let directory: URL

    public var id: URL {
        directory
    }

    public init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}

public struct InstalledGhostCharacter: Sendable, Equatable {
    public let scope: Int
    public let name: String?
    public let defaultSurfaceID: Int
    public let defaultBalloonSurfaceID: Int

    public init(
        scope: Int,
        name: String? = nil,
        defaultSurfaceID: Int,
        defaultBalloonSurfaceID: Int = 0
    ) {
        self.scope = scope
        self.name = name
        self.defaultSurfaceID = defaultSurfaceID
        self.defaultBalloonSurfaceID = defaultBalloonSurfaceID
    }
}

/// A ghost package installed on disk. A running ghost is represented separately by the runtime.
public struct InstalledGhost: Identifiable, Sendable, Equatable {
    public let name: String
    public let rootDirectory: URL
    public let defaultShellDirectory: URL
    public let shells: [InstalledShell]
    public let characters: [InstalledGhostCharacter]
    public let shioriFilename: String?
    public let defaultBalloonDirectoryName: String?

    public var id: URL {
        rootDirectory
    }

    public init(
        name: String,
        rootDirectory: URL,
        defaultShellDirectory: URL,
        shells: [InstalledShell]? = nil,
        characters: [InstalledGhostCharacter]? = nil,
        shioriFilename: String? = nil,
        defaultBalloonDirectoryName: String? = nil
    ) {
        self.name = name
        self.rootDirectory = rootDirectory
        self.defaultShellDirectory = defaultShellDirectory
        self.shells = shells ?? [
            InstalledShell(name: defaultShellDirectory.lastPathComponent, directory: defaultShellDirectory)
        ]
        self.characters = characters ?? [
            InstalledGhostCharacter(scope: 0, defaultSurfaceID: 0),
            InstalledGhostCharacter(scope: 1, defaultSurfaceID: 10)
        ]
        self.shioriFilename = shioriFilename
        self.defaultBalloonDirectoryName = defaultBalloonDirectoryName
    }
}

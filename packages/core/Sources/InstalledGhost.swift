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
    /// An explicit Utatane macOS override; shioriFilename is the selected filename on macOS.
    public let shioriMacOSFilename: String?
    public let charset: String?
    public let defaultBalloonDirectoryName: String?

    public var id: URL {
        rootDirectory
    }

    /// The module name a baseware resolves when `shiori` is omitted.
    /// Keep shioriFilename optional so dictionary-based compatibility detection
    /// can still distinguish an omitted declaration from an explicit one.
    public var effectiveShioriFilename: String {
        shioriFilename ?? "shiori.dll"
    }

    public init(
        name: String,
        rootDirectory: URL,
        defaultShellDirectory: URL,
        shells: [InstalledShell]? = nil,
        characters: [InstalledGhostCharacter]? = nil,
        shioriFilename: String? = nil,
        shioriMacOSFilename: String? = nil,
        charset: String? = nil,
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
        #if os(macOS)
            self.shioriFilename = shioriMacOSFilename ?? shioriFilename
        #else
            self.shioriFilename = shioriFilename
        #endif
        self.shioriMacOSFilename = shioriMacOSFilename
        self.charset = charset
        self.defaultBalloonDirectoryName = defaultBalloonDirectoryName
    }
}

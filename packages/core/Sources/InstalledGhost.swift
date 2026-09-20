import Foundation

public struct InstalledShell: Identifiable, Sendable, Equatable {
    public let name: String
    public let directory: URL
    public let characterNames: [Int: String]
    public let secondaryCharacterName: String?

    public var id: URL {
        directory
    }

    public init(
        name: String,
        directory: URL,
        characterNames: [Int: String] = [:],
        secondaryCharacterName: String? = nil
    ) {
        self.name = name
        self.directory = directory
        self.characterNames = characterNames
        self.secondaryCharacterName = secondaryCharacterName
    }
}

public struct InstalledGhostCharacter: Sendable, Equatable {
    public let scope: Int
    public let name: String?
    public let secondaryName: String?
    public let defaultSurfaceID: Int
    public let defaultBalloonSurfaceID: Int

    public init(
        scope: Int,
        name: String? = nil,
        secondaryName: String? = nil,
        defaultSurfaceID: Int,
        defaultBalloonSurfaceID: Int = 0
    ) {
        self.scope = scope
        self.name = name
        self.secondaryName = secondaryName
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

    public func characterName(for scope: Int, shell: InstalledShell? = nil) -> String? {
        shell?.characterNames[scope] ?? characters.first(where: { $0.scope == scope })?.name
    }

    public func secondaryCharacterName(shell: InstalledShell? = nil) -> String? {
        shell?.secondaryCharacterName
            ?? characters.first(where: { $0.scope == 0 })?.secondaryName
            ?? characterName(for: 0, shell: shell)
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

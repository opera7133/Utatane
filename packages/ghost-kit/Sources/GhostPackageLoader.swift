import Foundation
import UtataneCore

public enum GhostPackageError: LocalizedError, Equatable {
    case missingFile(URL)
    case missingDefaultShell(URL)
    case unsupportedTextEncoding(URL)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            "必要なファイルがない: \(url.path)"
        case let .missingDefaultShell(url):
            "Shellが見つからない: \(url.path)"
        case let .unsupportedTextEncoding(url):
            "文字コードを判定できない: \(url.path)"
        }
    }
}

public struct GhostPackageLoader: Sendable {
    private let descriptParser = DescriptParser()

    public init() {}

    public func loadGhost(at rootDirectory: URL) throws -> InstalledGhost {
        let masterDirectory = rootDirectory.appending(path: "ghost/master", directoryHint: .isDirectory)
        let descriptURL = masterDirectory.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: descriptURL.path) else {
            throw GhostPackageError.missingFile(descriptURL)
        }

        let metadata = try descriptParser.parse(contentsOf: descriptURL)
        let aliasURL = masterDirectory.appending(path: "alias.txt", directoryHint: .notDirectory)
        let aliasMetadata = FileManager.default.fileExists(atPath: aliasURL.path)
            ? (try? descriptParser.parse(contentsOf: aliasURL)) ?? [:]
            : [:]
        let shells = try findShells(in: rootDirectory)
        let name = metadata["name"] ?? rootDirectory.lastPathComponent
        let macOSShiori = metadata["shiori.macos"].flatMap { $0.isEmpty ? nil : $0 }
        let commonShiori = metadata["shiori"] ?? aliasMetadata["shiori"]
        let defaultShellDirectoryName = metadata["seriko.defaultsurfacedirectoryname"]
        let defaultShellDirectory = try findDefaultShell(
            in: rootDirectory,
            shells: shells,
            preferredDirectoryName: defaultShellDirectoryName
        )

        return InstalledGhost(
            name: name,
            rootDirectory: rootDirectory,
            defaultShellDirectory: defaultShellDirectory,
            shells: shells,
            characters: characters(from: metadata),
            shioriFilename: commonShiori,
            shioriMacOSFilename: macOSShiori,
            charset: metadata["charset"],
            defaultBalloonDirectoryName: metadata["balloon"],
            allowsShellCharacterNameOverride: Self.boolean(metadata["name.allowoverride"], default: true),
            allowsUnspecifiedSSTP: Self.boolean(metadata["sstp.allowunspecifiedsend"], default: true),
            allowsSSTPCommunicate: Self.boolean(metadata["sstp.allowcommunicate"], default: true),
            desktopAlignment: metadata["seriko.alignmenttodesktop"].flatMap {
                GhostDesktopAlignment(rawValue: $0.lowercased())
            },
            preventsBalloonMovement: Self.boolean(metadata["balloon.dontmove"], default: false),
            synchronizesBalloonScale: Self.boolean(metadata["balloon.syncscale"], default: false),
            iconFilename: metadata["icon"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func characters(from metadata: [String: String]) -> [InstalledGhostCharacter] {
        let commonBalloonSurfaceID = metadata["balloon.defaultsurface"].flatMap(Int.init) ?? 0
        var characters = [
            InstalledGhostCharacter(
                scope: 0,
                name: metadata["sakura.name"],
                secondaryName: metadata["sakura.name2"],
                defaultSurfaceID: metadata["sakura.seriko.defaultsurface"].flatMap(Int.init) ?? 0,
                defaultBalloonSurfaceID: metadata["sakura.balloon.defaultsurface"].flatMap(Int.init)
                    ?? commonBalloonSurfaceID,
                presentationSettings: presentationSettings(prefix: "sakura", metadata: metadata)
            ),
            InstalledGhostCharacter(
                scope: 1,
                name: metadata["kero.name"],
                defaultSurfaceID: metadata["kero.seriko.defaultsurface"].flatMap(Int.init) ?? 10,
                defaultBalloonSurfaceID: metadata["kero.balloon.defaultsurface"].flatMap(Int.init)
                    ?? commonBalloonSurfaceID,
                presentationSettings: presentationSettings(prefix: "kero", metadata: metadata)
            )
        ]

        let additionalScopes = Set(metadata.keys.compactMap { key -> Int? in
            guard key.hasPrefix("char"),
                  let dot = key.firstIndex(of: "."),
                  key[dot...].hasPrefix(".seriko.defaultsurface")
            else { return nil }
            return Int(key[key.index(key.startIndex, offsetBy: 4) ..< dot])
        })
        for scope in additionalScopes.sorted() {
            let prefix = "char\(scope)"
            guard let surfaceID = metadata["\(prefix).seriko.defaultsurface"].flatMap(Int.init) else {
                continue
            }
            characters.append(
                InstalledGhostCharacter(
                    scope: scope,
                    name: metadata["\(prefix).name"],
                    defaultSurfaceID: surfaceID,
                    defaultBalloonSurfaceID: metadata["\(prefix).balloon.defaultsurface"].flatMap(Int.init)
                        ?? commonBalloonSurfaceID,
                    presentationSettings: presentationSettings(prefix: prefix, metadata: metadata)
                )
            )
        }
        return characters
    }

    private func presentationSettings(
        prefix: String,
        metadata: [String: String]
    ) -> GhostScopePresentationSettings {
        GhostScopePresentationSettings(
            desktopAlignment: metadata["\(prefix).seriko.alignmenttodesktop"]
                .flatMap { GhostDesktopAlignment(rawValue: $0.lowercased()) },
            defaultX: metadata["\(prefix).defaultx"].flatMap(Int.init),
            defaultY: metadata["\(prefix).defaulty"].flatMap(Int.init),
            defaultLeft: metadata["\(prefix).defaultleft"].flatMap(Int.init),
            defaultTop: metadata["\(prefix).defaulttop"].flatMap(Int.init)
        )
    }

    private func findShells(in rootDirectory: URL) throws -> [InstalledShell] {
        let shellsDirectory = rootDirectory.appending(path: "shell", directoryHint: .isDirectory)
        let directories = try FileManager.default.contentsOfDirectory(
            at: shellsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }

        return directories.compactMap { directory in
            let descriptURL = directory.appending(path: "descript.txt", directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: descriptURL.path),
                  let metadata = try? descriptParser.parse(contentsOf: descriptURL)
            else { return nil }
            return InstalledShell(
                name: metadata["name"] ?? directory.lastPathComponent,
                directory: directory,
                characterNames: [
                    0: metadata["sakura.name"],
                    1: metadata["kero.name"]
                ].compactMapValues { $0 },
                secondaryCharacterName: metadata["sakura.name2"]
            )
        }.sorted { lhs, rhs in
            if lhs.directory.lastPathComponent == "master" {
                return true
            }
            if rhs.directory.lastPathComponent == "master" {
                return false
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func findDefaultShell(
        in rootDirectory: URL,
        shells: [InstalledShell],
        preferredDirectoryName: String? = nil
    ) throws -> URL {
        let shellsDirectory = rootDirectory.appending(path: "shell", directoryHint: .isDirectory)
        if let preferredDirectoryName,
           let preferred = shells.first(where: {
               $0.directory.lastPathComponent.caseInsensitiveCompare(preferredDirectoryName) == .orderedSame
           })
        {
            return preferred.directory
        }
        if let master = shells.first(where: {
            $0.directory.lastPathComponent.caseInsensitiveCompare("master") == .orderedSame
        }) {
            return master.directory
        }
        if let shell = shells.first {
            return shell.directory
        }

        throw GhostPackageError.missingDefaultShell(shellsDirectory)
    }

    private static func boolean(_ value: String?, default defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "false", "off", "no": false
        case "1", "true", "on", "yes": true
        default: defaultValue
        }
    }
}

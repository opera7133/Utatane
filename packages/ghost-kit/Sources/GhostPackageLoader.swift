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
        let shells = try findShells(in: rootDirectory)
        let shellDirectory = try findDefaultShell(in: rootDirectory, shells: shells)
        let name = metadata["name"] ?? rootDirectory.lastPathComponent

        return InstalledGhost(
            name: name,
            rootDirectory: rootDirectory,
            defaultShellDirectory: shellDirectory,
            shells: shells,
            characters: characters(from: metadata),
            shioriFilename: metadata["shiori"],
            charset: metadata["charset"],
            defaultBalloonDirectoryName: metadata["balloon"]
        )
    }

    private func characters(from metadata: [String: String]) -> [InstalledGhostCharacter] {
        let commonBalloonSurfaceID = metadata["balloon.defaultsurface"].flatMap(Int.init) ?? 0
        var characters = [
            InstalledGhostCharacter(
                scope: 0,
                name: metadata["sakura.name"],
                defaultSurfaceID: metadata["sakura.seriko.defaultsurface"].flatMap(Int.init) ?? 0,
                defaultBalloonSurfaceID: metadata["sakura.balloon.defaultsurface"].flatMap(Int.init)
                    ?? commonBalloonSurfaceID
            ),
            InstalledGhostCharacter(
                scope: 1,
                name: metadata["kero.name"],
                defaultSurfaceID: metadata["kero.seriko.defaultsurface"].flatMap(Int.init) ?? 10,
                defaultBalloonSurfaceID: metadata["kero.balloon.defaultsurface"].flatMap(Int.init)
                    ?? commonBalloonSurfaceID
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
                        ?? commonBalloonSurfaceID
                )
            )
        }
        return characters
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
                directory: directory
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
        shells: [InstalledShell]
    ) throws -> URL {
        let shellsDirectory = rootDirectory.appending(path: "shell", directoryHint: .isDirectory)
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
}

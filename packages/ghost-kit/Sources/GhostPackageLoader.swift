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
        let shellDirectory = try findDefaultShell(in: rootDirectory)
        let name = metadata["name"] ?? rootDirectory.lastPathComponent

        return InstalledGhost(
            name: name,
            rootDirectory: rootDirectory,
            defaultShellDirectory: shellDirectory
        )
    }

    private func findDefaultShell(in rootDirectory: URL) throws -> URL {
        let shellsDirectory = rootDirectory.appending(path: "shell", directoryHint: .isDirectory)
        let masterDirectory = shellsDirectory.appending(path: "master", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: masterDirectory.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            return masterDirectory
        }

        let shells = try? FileManager.default.contentsOfDirectory(
            at: shellsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        if let shell = try shells?.first(where: {
            try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }) {
            return shell
        }

        throw GhostPackageError.missingDefaultShell(shellsDirectory)
    }
}

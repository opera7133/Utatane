import Foundation

public struct BundledContentInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func install(
        from bundledRoot: URL,
        ghostsDirectory: URL,
        balloonsDirectory: URL
    ) throws {
        try installDirectories(
            from: bundledRoot.appending(path: "Ghosts", directoryHint: .isDirectory),
            to: ghostsDirectory
        )
        try installDirectories(
            from: bundledRoot.appending(path: "Balloons", directoryHint: .isDirectory),
            to: balloonsDirectory
        )
    }

    private func installDirectories(from sourceRoot: URL, to destinationRoot: URL) throws {
        guard fileManager.fileExists(atPath: sourceRoot.path) else { return }
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sources = try fileManager.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for source in sources {
            guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            let destination = destinationRoot.appending(
                path: source.lastPathComponent,
                directoryHint: .isDirectory
            )
            if fileManager.fileExists(atPath: destination.path) {
                try installMissingHomeURL(from: source, to: destination)
                continue
            }

            let staging = destinationRoot.appending(
                path: ".utatane-bundled-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            defer { try? fileManager.removeItem(at: staging) }
            try fileManager.copyItem(at: source, to: staging)
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    private func installMissingHomeURL(from source: URL, to destination: URL) throws {
        for relativePath in ["descript.txt", "ghost/master/descript.txt"] {
            let sourceDescriptor = source.appending(path: relativePath)
            let destinationDescriptor = destination.appending(path: relativePath)
            guard fileManager.fileExists(atPath: sourceDescriptor.path),
                  fileManager.fileExists(atPath: destinationDescriptor.path),
                  let sourceText = try? String(contentsOf: sourceDescriptor, encoding: .utf8),
                  var destinationText = try? String(contentsOf: destinationDescriptor, encoding: .utf8),
                  homeURLLine(in: destinationText) == nil,
                  let bundledHomeURL = homeURLLine(in: sourceText)
            else { continue }

            if !destinationText.isEmpty, !destinationText.hasSuffix("\n") {
                destinationText.append("\n")
            }
            destinationText.append(bundledHomeURL)
            destinationText.append("\n")
            try destinationText.write(to: destinationDescriptor, atomically: true, encoding: .utf8)
        }
    }

    private func homeURLLine(in descriptor: String) -> String? {
        descriptor.components(separatedBy: .newlines).first { line in
            let fields = line.split(separator: ",", maxSplits: 1)
            return fields.count == 2 && fields[0].trimmingCharacters(in: .whitespaces).lowercased() == "homeurl"
        }
    }
}

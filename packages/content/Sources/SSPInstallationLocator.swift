import Foundation

/// Finds SSP installations in known Wine prefixes without following directory links.
public struct SSPInstallationLocator: Sendable {
    public struct Candidate: Sendable, Equatable {
        public let directory: URL
        public let environment: String
    }

    private let home: URL
    private let maximumDepth: Int
    private let maximumDirectories: Int

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        maximumDepth: Int = 6,
        maximumDirectories: Int = 10000
    ) {
        self.home = home
        self.maximumDepth = max(0, maximumDepth)
        self.maximumDirectories = max(0, maximumDirectories)
    }

    public func locate() -> [Candidate] {
        let manager = FileManager.default
        var roots: [(URL, String)] = [(home.appending(path: ".wine/drive_c"), "Wine")]
        for (path, environment) in [
            ("Library/Application Support/CrossOver/Bottles", "CrossOver"),
            ("Library/Containers/com.isaacmarovitz.Whisky/Bottles", "Whisky")
        ] {
            for bottle in directories(in: home.appending(path: path)) {
                roots.append((bottle.appending(path: "drive_c"), "\(environment) (\(bottle.lastPathComponent))"))
            }
        }

        var result: [Candidate] = []
        var seen: Set<URL> = []
        var remaining = maximumDirectories
        func scan(_ directory: URL, environment: String, depth: Int) {
            guard remaining > 0, isDirectoryWithoutLinks(directory),
                  seen.insert(directory.standardizedFileURL).inserted else { return }
            remaining -= 1
            let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
            if names.contains(where: { $0.caseInsensitiveCompare("ssp.exe") == .orderedSame }),
               let ghost = names.first(where: { $0.caseInsensitiveCompare("ghost") == .orderedSame }),
               isDirectoryWithoutLinks(directory.appending(path: ghost))
            {
                result.append(Candidate(directory: directory, environment: environment))
                return
            }
            guard depth < maximumDepth else { return }
            for child in directories(in: directory) {
                guard !["windows", "programdata", "dosdevices", "appdata"].contains(child.lastPathComponent.lowercased()) else { continue }
                scan(child, environment: environment, depth: depth + 1)
            }
        }
        for (root, environment) in roots {
            scan(root, environment: environment, depth: 0)
        }
        return result
    }

    private func directories(in directory: URL) -> [URL] {
        guard isDirectoryWithoutLinks(directory) else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []).filter(isDirectoryWithoutLinks).sorted { $0.path < $1.path }
    }

    private func isDirectoryWithoutLinks(_ directory: URL) -> Bool {
        // Check ancestors too: a bottle or drive_c itself can be a link outside the prefix.
        var current = directory.standardizedFileURL
        let boundary = home.standardizedFileURL
        guard current.path.hasPrefix(boundary.path + "/") else { return false }
        while current != boundary {
            guard let values = try? current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { return false }
            current.deleteLastPathComponent()
        }
        return true
    }
}

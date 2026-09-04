import Foundation
import UtataneCore
import UtataneGhostKit
import UtataneSakuraScript
import UtataneShell

public enum ContentDiagnosticSeverity: String, Codable, Sendable {
    case error
    case warning
}

public struct ContentDiagnostic: Codable, Equatable, Sendable {
    public let severity: ContentDiagnosticSeverity
    public let code: String
    public let message: String
    public let path: String
    public let line: Int?

    public init(
        severity: ContentDiagnosticSeverity,
        code: String,
        message: String,
        path: String,
        line: Int? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.path = path
        self.line = line
    }
}

public struct ContentValidationReport: Codable, Equatable, Sendable {
    public let rootPath: String
    public let ghostName: String?
    public let shiori: String?
    public let diagnostics: [ContentDiagnostic]

    public var errorCount: Int {
        diagnostics.count { $0.severity == .error }
    }

    public var warningCount: Int {
        diagnostics.count { $0.severity == .warning }
    }
}

public struct ContentValidator: Sendable {
    private let ghostLoader = GhostPackageLoader()
    private let shellLoader = ShellLoader()
    private let scriptParser = SakuraScriptParser()

    public init() {}

    public func validate(ghostRoot: URL) -> ContentValidationReport {
        let root = ghostRoot.standardizedFileURL
        let ghost: InstalledGhost
        do {
            ghost = try ghostLoader.loadGhost(at: root)
        } catch {
            return ContentValidationReport(
                rootPath: root.path,
                ghostName: nil,
                shiori: nil,
                diagnostics: [diagnostic(
                    .error,
                    code: "ghost.load",
                    message: error.localizedDescription,
                    url: root,
                    root: root
                )]
            )
        }

        var diagnostics: [ContentDiagnostic] = []
        let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
        if let declared = ghost.shioriFilename {
            if ShioriCatalog.identify(masterDirectory: master, declaredModuleFilename: declared) == nil {
                diagnostics.append(diagnostic(
                    .warning,
                    code: "shiori.unknown",
                    message: "対応方法を判定できないSHIORI: \(declared)",
                    url: master.appending(path: "descript.txt"),
                    root: root
                ))
            }
            let moduleURL = master.appending(path: declared, directoryHint: .notDirectory)
            let descriptor = ShioriCatalog.descriptor(moduleFilename: declared)
            if descriptor?.provisioning == .ghost,
               !FileManager.default.fileExists(atPath: moduleURL.path)
            {
                diagnostics.append(diagnostic(
                    .error,
                    code: "shiori.missing-module",
                    message: "宣言されたSHIORIファイルがない: \(declared)",
                    url: moduleURL,
                    root: root
                ))
            }
        } else {
            diagnostics.append(diagnostic(
                .warning,
                code: "shiori.missing-declaration",
                message: "SHIORIの宣言または既知の辞書が見つからない",
                url: master,
                root: root
            ))
        }

        for installedShell in ghost.shells {
            do {
                let shell = try shellLoader.load(from: installedShell.directory)
                validate(shell: shell, ghost: ghost, root: root, diagnostics: &diagnostics)
            } catch {
                diagnostics.append(diagnostic(
                    .error,
                    code: "shell.load",
                    message: error.localizedDescription,
                    url: installedShell.directory,
                    root: root
                ))
            }
        }
        diagnostics.append(contentsOf: scriptDiagnostics(in: master, root: root))
        diagnostics.sort {
            ($0.path, $0.line ?? 0, $0.code, $0.message)
                < ($1.path, $1.line ?? 0, $1.code, $1.message)
        }
        return ContentValidationReport(
            rootPath: root.path,
            ghostName: ghost.name,
            shiori: ShioriCatalog.identify(
                masterDirectory: master,
                declaredModuleFilename: ghost.shioriFilename
            )?.displayName ?? ghost.shioriFilename,
            diagnostics: diagnostics
        )
    }

    private func validate(
        shell: ShellDefinition,
        ghost: InstalledGhost,
        root: URL,
        diagnostics: inout [ContentDiagnostic]
    ) {
        if shell.directory.standardizedFileURL == ghost.defaultShellDirectory.standardizedFileURL {
            for character in ghost.characters where shell.surfaces[character.defaultSurfaceID] == nil {
                diagnostics.append(diagnostic(
                    .error,
                    code: "shell.missing-default-surface",
                    message: "scope \(character.scope)の既定surface\(character.defaultSurfaceID)がない",
                    url: shell.directory,
                    root: root
                ))
            }
        }
        var checkedElements = Set<String>()
        for surface in shell.surfaces.values {
            for element in surface.elements where checkedElements.insert(element.filename).inserted {
                do {
                    _ = try shellLoader.loadElement(filename: element.filename, from: shell.directory)
                } catch {
                    diagnostics.append(diagnostic(
                        .error,
                        code: "shell.missing-element",
                        message: error.localizedDescription,
                        url: shell.directory.appending(path: element.filename),
                        root: root
                    ))
                }
            }
        }
    }

    private func scriptDiagnostics(in directory: URL, root: URL) -> [ContentDiagnostic] {
        let extensions: Set = ["as", "azr", "dic", "txt", "yaml", "yml"]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var diagnostics: [ContentDiagnostic] = []
        for case let url as URL in enumerator {
            guard extensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url),
                  data.count <= 16 * 1024 * 1024,
                  let text = LegacyTextDecoder.decode(data)
            else { continue }
            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                guard let script = probableSakuraScript(in: line) else { continue }
                let unknown = scriptParser.parse(String(script)).compactMap { token -> String? in
                    guard case let .unknown(command) = token else { return nil }
                    return command
                }
                for command in Set(unknown).sorted() {
                    diagnostics.append(diagnostic(
                        .warning,
                        code: "sakurascript.unknown",
                        message: "未対応または不正なSakuraScript: \(command)",
                        url: url,
                        root: root,
                        line: offset + 1
                    ))
                }
            }
        }
        return diagnostics
    }

    /// Dictionary languages also use backslashes for paths, regular expressions, and escaping.
    /// Limit static checks to text following a common speaker/surface command so those constructs
    /// are not reported as SakuraScript. Runtime responses remain the authoritative validation path.
    private func probableSakuraScript(in line: String) -> Substring? {
        guard !line.contains("%(") else { return nil }
        let anchors = [#"\0"#, #"\1"#, #"\h"#, #"\u"#, #"\p["#, #"\s["#]
        let start = anchors.compactMap { line.range(of: $0)?.lowerBound }.min()
        return start.map { line[$0...] }
    }

    private func diagnostic(
        _ severity: ContentDiagnosticSeverity,
        code: String,
        message: String,
        url: URL,
        root: URL,
        line: Int? = nil
    ) -> ContentDiagnostic {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let relativePath = path == rootPath ? "." : String(path.dropFirst(min(path.count, rootPath.count + 1)))
        return ContentDiagnostic(
            severity: severity,
            code: code,
            message: message,
            path: relativePath,
            line: line
        )
    }
}

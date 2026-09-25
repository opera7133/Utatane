import CryptoKit
import Foundation
import UtataneNetwork
import ZIPFoundation

public enum ModulePackageInstallError: Error, Equatable {
    case invalidPackage
    case archiveMismatch
    case unsafeEntry
    case packageTooLarge
    case manifestMismatch
}

private struct ModulePackageManifest: Decodable {
    let schemaVersion: Int
    let id: String
    let version: String
    let revision: Int
    let abi: String
    let minimumOS: String
    let architectures: [String]
    let files: [String: String]
}

/// Installs a catalog ZIP into a managed root such as NativeShiori or NativeSaori.
public struct ModulePackageInstaller: Sendable {
    public init() {}

    @discardableResult
    public func install(
        archiveURL: URL,
        module: SignedModuleCatalog.Module,
        artifact: SignedModuleCatalog.Module.Artifact,
        managedRootURL: URL
    ) throws -> URL {
        guard archiveURL.isFileURL, managedRootURL.isFileURL,
              validComponent(module.id),
              module.artifacts.contains(where: { $0.path == artifact.path && $0.sha256 == artifact.sha256 }),
              artifact.size > 0, artifact.size <= 512_000_000
        else { throw ModulePackageInstallError.invalidPackage }
        let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue == artifact.size else {
            throw ModulePackageInstallError.archiveMismatch
        }
        let archiveBytes = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        guard archiveBytes.count == artifact.size, digest(archiveBytes) == artifact.sha256 else {
            throw ModulePackageInstallError.archiveMismatch
        }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let entries = Array(archive)
        guard !entries.isEmpty, entries.count <= 2048 else { throw ModulePackageInstallError.packageTooLarge }
        var paths = Set<String>()
        var totalSize: UInt64 = 0
        for entry in entries {
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            guard safePath(path, moduleID: module.id) || (path == module.id && entry.type == .directory),
                  entry.type == .file || entry.type == .directory,
                  paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted
            else { throw ModulePackageInstallError.unsafeEntry }
            let (size, overflow) = totalSize.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, size <= 512_000_000, entry.uncompressedSize <= 256_000_000 else {
                throw ModulePackageInstallError.packageTooLarge
            }
            totalSize = size
        }

        let manager = FileManager.default
        let root = managedRootURL.standardizedFileURL
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        var extractedFiles = Set<String>()
        var extractedBytes: UInt64 = 0
        for entry in entries {
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let output = staging.appending(path: path)
            if entry.type == .directory {
                try manager.createDirectory(at: output, withIntermediateDirectories: true)
            } else {
                try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard manager.createFile(atPath: output.path, contents: nil) else {
                    throw ModulePackageInstallError.invalidPackage
                }
                let file = try FileHandle(forWritingTo: output)
                var entryBytes: UInt64 = 0
                do {
                    _ = try archive.extract(entry) { chunk in
                        let (nextEntry, entryOverflow) = entryBytes.addingReportingOverflow(UInt64(chunk.count))
                        let (nextTotal, totalOverflow) = extractedBytes.addingReportingOverflow(UInt64(chunk.count))
                        guard !entryOverflow, !totalOverflow,
                              nextEntry <= entry.uncompressedSize, nextTotal <= 512_000_000
                        else { throw ModulePackageInstallError.packageTooLarge }
                        entryBytes = nextEntry
                        extractedBytes = nextTotal
                        try file.write(contentsOf: chunk)
                    }
                    try file.close()
                } catch {
                    try? file.close()
                    throw error
                }
                guard entryBytes == entry.uncompressedSize else {
                    throw ModulePackageInstallError.invalidPackage
                }
                let relative = String(path.dropFirst(module.id.count + 1))
                extractedFiles.insert(relative)
                try manager.setAttributes([.posixPermissions: relative.hasSuffix(".dylib") ? 0o755 : 0o644],
                                          ofItemAtPath: output.path)
            }
        }
        let package = staging.appending(path: module.id, directoryHint: .isDirectory)
        let manifestURL = package.appending(path: "module.json")
        guard let manifest = try? JSONDecoder().decode(ModulePackageManifest.self, from: Data(contentsOf: manifestURL)),
              manifest.schemaVersion == 1, manifest.id == module.id,
              manifest.version == artifact.version, manifest.revision == artifact.revision,
              manifest.abi == artifact.abi, manifest.minimumOS == artifact.minimumOS,
              Set(manifest.architectures) == Set(artifact.architectures),
              !manifest.files.isEmpty,
              Set(manifest.files.keys).union(["module.json"]) == extractedFiles,
              manifest.files.keys.contains(where: { $0.hasPrefix("lib/") && $0.hasSuffix(".dylib") })
        else { throw ModulePackageInstallError.manifestMismatch }
        for (path, checksum) in manifest.files {
            guard safePath("\(module.id)/\(path)", moduleID: module.id),
                  checksum.count == 64,
                  try digest(Data(contentsOf: package.appending(path: path), options: .mappedIfSafe)) == checksum
            else { throw ModulePackageInstallError.manifestMismatch }
        }

        let destination = root.appending(path: module.id, directoryHint: .isDirectory)
        let backup = root.appending(path: ".backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        let hadPrevious = manager.fileExists(atPath: destination.path)
        if hadPrevious {
            try manager.moveItem(at: destination, to: backup)
        }
        do {
            try manager.moveItem(at: package, to: destination)
        } catch {
            if hadPrevious {
                try? manager.moveItem(at: backup, to: destination)
            }
            throw error
        }
        if hadPrevious {
            try? manager.removeItem(at: backup)
        }
        return destination
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validComponent(_ value: String) -> Bool {
        guard let first = value.utf8.first, (97 ... 122).contains(first) else { return false }
        return value.utf8.allSatisfy { (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 45 || $0 == 46 }
    }

    private func safePath(_ value: String, moduleID: String) -> Bool {
        guard value.utf8.count <= 512, !value.contains("\\"), !value.contains(":"), !value.contains("\0") else {
            return false
        }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.first == Substring(moduleID)
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

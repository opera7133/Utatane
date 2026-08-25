import Foundation

public struct ArchiveOperationResult: Sendable, Equatable {
    public let fileCount: Int
    public let compressedBytes: Int
    public let uncompressedBytes: Int

    public init(fileCount: Int, compressedBytes: Int, uncompressedBytes: Int) {
        self.fileCount = fileCount
        self.compressedBytes = compressedBytes
        self.uncompressedBytes = uncompressedBytes
    }
}

public enum ArchiveOperationError: LocalizedError, Equatable, Sendable {
    case invalidParameter
    case fileNotFound
    case directoryNotFound
    case createDirectoryFailed
    case openFailed
    case corrupted
    case passwordRequired
    case passwordMismatch
    case unsafeEntry(String)

    public var errorCode: String {
        switch self {
        case .invalidParameter: "invalid parameter"
        case .fileNotFound: "file not found"
        case .directoryNotFound: "directory not found"
        case .createDirectoryFailed: "create directory failed"
        case .openFailed: "open failed"
        case .corrupted: "corrupted"
        case .passwordRequired: "password required"
        case .passwordMismatch: "password mismatch"
        case .unsafeEntry: "corrupted"
        }
    }
}

public struct ArchiveOperationRunner: Sendable {
    public init() {}

    public func extract(
        archiveURL: URL,
        destinationDirectoryURL: URL,
        password: String? = nil
    ) throws -> ArchiveOperationResult {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ArchiveOperationError.fileNotFound
        }
        let entries = try archiveEntries(at: archiveURL)
        guard !entries.isEmpty else {
            throw ArchiveOperationError.corrupted
        }
        for entry in entries {
            guard !entry.isEmpty,
                  !entry.contains("\\"),
                  !entry.hasPrefix("/"),
                  !entry.contains("\0")
            else { throw ArchiveOperationError.unsafeEntry(entry) }
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0 == ".." || $0 == "." }) else {
                throw ArchiveOperationError.unsafeEntry(entry)
            }
        }
        try validateArchiveEntryTypes(at: archiveURL)
        do {
            try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw ArchiveOperationError.createDirectoryFailed
        }

        var arguments = ["-q", "-o", archiveURL.path]
        if let password, !password.isEmpty {
            arguments.append(contentsOf: ["-P", password])
        }
        arguments.append(contentsOf: ["-d", destinationDirectoryURL.path])

        _ = try run(executable: "/usr/bin/unzip", arguments: arguments)

        let compressedBytes = (try? FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? Int) ?? 0
        var uncompressedBytes = 0
        var fileCount = 0

        if let enumerator = FileManager.default.enumerator(at: destinationDirectoryURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile == true {
                    fileCount += 1
                    uncompressedBytes += values?.fileSize ?? 0
                }
            }
        }

        return ArchiveOperationResult(
            fileCount: fileCount,
            compressedBytes: compressedBytes,
            uncompressedBytes: uncompressedBytes
        )
    }

    public func compress(
        destinationArchiveURL: URL,
        sourceDirectoryURL: URL,
        password: String? = nil,
        appliesNarExclusions: Bool = false
    ) throws -> ArchiveOperationResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceDirectoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ArchiveOperationError.directoryNotFound
        }
        let parentURL = destinationArchiveURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        } catch {
            throw ArchiveOperationError.createDirectoryFailed
        }
        if FileManager.default.fileExists(atPath: destinationArchiveURL.path) {
            try? FileManager.default.removeItem(at: destinationArchiveURL)
        }

        var arguments = ["-r", "-q"]
        if let password, !password.isEmpty {
            arguments.append(contentsOf: ["-P", password])
        }
        arguments.append(destinationArchiveURL.path)
        arguments.append(".")
        let developerOptions = try DeveloperOptions.load(from: sourceDirectoryURL)
        let narPathFilter = appliesNarExclusions ? try ContentPathFilter.load(
            from: sourceDirectoryURL,
            ignoreFilename: ".narignore",
            includeFilename: ".narinclude"
        ) : nil
        if appliesNarExclusions {
            let standardPatterns = [
                "desktop.ini", "thumbs.db", "folder.htt", "mscreate.dir", ".DS_Store", "_CATALOG.VIX",
                "profile/*", "*/profile/*", "var/*", "*/var/*", "__MACOSX/*", "*/__MACOSX/*",
                "XtraStuf.mac/*", "*/XtraStuf.mac/*", "*_variable.cfg", "*/*_variable.cfg"
            ]
            var excludedPaths = standardPatterns + developerOptions.exclusionPatterns(option: "nonar")
            if let enumerator = FileManager.default.enumerator(at: sourceDirectoryURL, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    var relativePath = String(fileURL.standardizedFileURL.path.dropFirst(
                        sourceDirectoryURL.standardizedFileURL.path.count
                    ))
                    if relativePath.hasPrefix("/") {
                        relativePath.removeFirst()
                    }
                    if !relativePath.isEmpty,
                       narPathFilter?.includes(relativePath: relativePath) == false
                    {
                        excludedPaths.append(relativePath)
                    }
                }
            }
            arguments.append("-x")
            arguments.append(contentsOf: excludedPaths)
        }

        _ = try run(executable: "/usr/bin/zip", arguments: arguments, currentDirectoryURL: sourceDirectoryURL)

        let compressedBytes = (try? FileManager.default.attributesOfItem(atPath: destinationArchiveURL.path)[.size] as? Int) ?? 0
        var uncompressedBytes = 0
        var fileCount = 0

        if let enumerator = FileManager.default.enumerator(at: sourceDirectoryURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile == true {
                    var relativePath = String(fileURL.standardizedFileURL.path.dropFirst(
                        sourceDirectoryURL.standardizedFileURL.path.count
                    ))
                    if relativePath.hasPrefix("/") {
                        relativePath.removeFirst()
                    }
                    let isExcludedFromNar = DeveloperOptions.isStandardExcluded(relativePath: relativePath)
                        || developerOptions.excludesFromNar(relativePath: relativePath)
                    if appliesNarExclusions,
                       isExcludedFromNar || narPathFilter?.includes(relativePath: relativePath) == false
                    {
                        continue
                    }
                    fileCount += 1
                    uncompressedBytes += values?.fileSize ?? 0
                }
            }
        }

        return ArchiveOperationResult(
            fileCount: fileCount,
            compressedBytes: compressedBytes,
            uncompressedBytes: uncompressedBytes
        )
    }

    private func archiveEntries(at archiveURL: URL) throws -> [String] {
        let output = try run(
            executable: "/usr/bin/unzip",
            arguments: ["-Z1", archiveURL.path],
            capturesOutput: true
        )
        guard let listing = String(data: output, encoding: .utf8)
            ?? String(data: output, encoding: .shiftJIS)
        else { throw ArchiveOperationError.corrupted }
        return listing.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func validateArchiveEntryTypes(at archiveURL: URL) throws {
        let output = try run(
            executable: "/usr/bin/unzip",
            arguments: ["-Z", "-l", archiveURL.path],
            capturesOutput: true
        )
        guard let listing = String(data: output, encoding: .utf8)
            ?? String(data: output, encoding: .shiftJIS)
        else { throw ArchiveOperationError.corrupted }
        for line in listing.components(separatedBy: .newlines) where line.count >= 10 {
            let mode = line.prefix(10)
            guard mode.dropFirst().allSatisfy({ "rwxstST-".contains($0) }) else { continue }
            guard let type = mode.first, type == "-" || type == "d" else {
                throw ArchiveOperationError.unsafeEntry("symbolic link or special file")
            }
        }
    }

    @discardableResult
    private func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        capturesOutput: Bool = false
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }
        let outputPipe = capturesOutput ? Pipe() : nil
        if let outputPipe {
            process.standardOutput = outputPipe
            process.standardError = Pipe()
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ArchiveOperationError.openFailed
        }
        guard process.terminationStatus == 0 else {
            throw ArchiveOperationError.openFailed
        }
        return outputPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    }
}

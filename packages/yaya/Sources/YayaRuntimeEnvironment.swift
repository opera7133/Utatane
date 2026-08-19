import Foundation

public enum YayaRuntimeEnvironmentError: Error, Equatable, Sendable {
    case capabilityUnavailable(String)
    case pathEscapesRoot(String)
}

public protocol YayaRuntimeEnvironment: AnyObject {
    var calendar: Calendar { get }

    func currentDate() -> Date
    func uptimeMilliseconds() -> Int64
    func setting(named name: String) -> YayaValue?
    @discardableResult func setSetting(_ value: YayaValue, named name: String) -> Bool
    func saveVariables(_ variables: [String: YayaValue], path: String?) throws
    func restoreVariables(path: String?) throws -> [String: YayaValue]
    func fileSize(path: String) throws -> Int64
    func setFileEncoding(_ encoding: YayaTextEncoding)
    func openFile(path: String, mode: String) throws -> Int
    func closeFile(path: String) throws -> Int
    func readLine(path: String) throws -> String?
    func writeLine(_ line: String, path: String) throws -> Bool
    func deleteFile(path: String) throws -> Bool
    func renameFile(from source: String, to destination: String) throws -> Bool
    func enumerateFiles(path: String) throws -> [String]
    func fileAttributes(path: String) throws -> [Int64]?
    func log(_ message: String)
    func errorLog() -> String
}

public final class YayaNativeRuntimeEnvironment: YayaRuntimeEnvironment {
    public let calendar: Calendar

    private let rootDirectory: URL?
    private let saveFileURL: URL?
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let uptimeProvider: () -> TimeInterval
    private var settings: [String: YayaValue]
    private var fileEncoding: YayaTextEncoding = .utf8
    private var openFiles: [String: OpenFile] = [:]
    private var logMessages: [String] = []

    public init(
        rootDirectory: URL? = nil,
        saveFileURL: URL? = nil,
        settings: [String: YayaValue] = [:],
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init,
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.rootDirectory = rootDirectory?.standardizedFileURL.resolvingSymlinksInPath()
        self.saveFileURL = saveFileURL?.standardizedFileURL
        self.settings = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.lowercased(), $0.value) })
        self.calendar = calendar
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.uptimeProvider = uptimeProvider

        if let rootDirectory {
            self.settings["coreinfo.path"] = .string(rootDirectory.standardizedFileURL.path)
        }
        if let saveFileURL {
            self.settings["coreinfo.savefile"] = .string(saveFileURL.standardizedFileURL.path)
        }
        self.settings["coreinfo.name"] = self.settings["coreinfo.name"] ?? .string("Utatane YAYA")
        self.settings["coreinfo.version"] = self.settings["coreinfo.version"] ?? .string("0")
        self.settings["coreinfo.author"] = self.settings["coreinfo.author"] ?? .string("Utatane")
        self.settings["coreinfo.mode"] = self.settings["coreinfo.mode"] ?? .string("native")
    }

    public convenience init(configuration: YayaConfiguration, saveFileURL: URL? = nil) {
        let settings = configuration.settings.compactMapValues { $0.last }.mapValues(YayaValue.string)
        self.init(
            rootDirectory: configuration.rootDirectory,
            saveFileURL: saveFileURL,
            settings: settings
        )
    }

    public func currentDate() -> Date {
        dateProvider()
    }

    public func uptimeMilliseconds() -> Int64 {
        Int64(uptimeProvider() * 1000)
    }

    public func setting(named name: String) -> YayaValue? {
        settings[name.lowercased()]
    }

    @discardableResult
    public func setSetting(_ value: YayaValue, named name: String) -> Bool {
        settings[name.lowercased()] = value
        return true
    }

    public func saveVariables(_ variables: [String: YayaValue], path: String?) throws {
        let url = try persistenceURL(path: path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(variables).write(to: url, options: .atomic)
    }

    public func restoreVariables(path: String?) throws -> [String: YayaValue] {
        let url = try persistenceURL(path: path)
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: YayaValue].self, from: Data(contentsOf: url))
    }

    public func fileSize(path: String) throws -> Int64 {
        let url = try resolvedURL(path)
        guard fileManager.fileExists(atPath: url.path) else { return -1 }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? -1
    }

    public func setFileEncoding(_ encoding: YayaTextEncoding) {
        fileEncoding = encoding
    }

    public func openFile(path: String, mode: String) throws -> Int {
        let url = try resolvedURL(path)
        let key = url.path
        guard openFiles[key] == nil else { return 2 }
        let normalizedMode = normalizedFileMode(mode)
        guard let normalizedMode else { return 0 }

        if normalizedMode == .read {
            guard fileManager.fileExists(atPath: url.path),
                  let text = try String(data: Data(contentsOf: url), encoding: fileEncoding.foundationEncoding)
            else { return 0 }
            let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            var lines = normalizedText.components(separatedBy: "\n")
            if normalizedText.hasSuffix("\n"), lines.last?.isEmpty == true {
                lines.removeLast()
            }
            openFiles[key] = .read(lines: lines, index: 0)
            return 1
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        if normalizedMode == .append {
            try handle.seekToEnd()
        } else {
            try handle.truncate(atOffset: 0)
        }
        openFiles[key] = .write(handle)
        return 1
    }

    public func closeFile(path: String) throws -> Int {
        let key = try resolvedURL(path).path
        guard let file = openFiles.removeValue(forKey: key) else { return 2 }
        if case let .write(handle) = file {
            try handle.close()
        }
        return 1
    }

    public func readLine(path: String) throws -> String? {
        let key = try resolvedURL(path).path
        guard let file = openFiles[key], case let .read(lines, index) = file else { return nil }
        guard index < lines.count else { return nil }
        openFiles[key] = .read(lines: lines, index: index + 1)
        return lines[index].trimmingCharacters(in: .newlines)
    }

    public func writeLine(_ line: String, path: String) throws -> Bool {
        let key = try resolvedURL(path).path
        guard let file = openFiles[key], case let .write(handle) = file,
              let data = (line + "\n").data(using: fileEncoding.foundationEncoding)
        else { return false }
        try handle.write(contentsOf: data)
        return true
    }

    public func deleteFile(path: String) throws -> Bool {
        let url = try resolvedURL(path)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.removeItem(at: url)
        return true
    }

    public func renameFile(from source: String, to destination: String) throws -> Bool {
        let sourceURL = try resolvedURL(source)
        let destinationURL = try resolvedURL(destination)
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path)
        else { return false }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return true
    }

    public func enumerateFiles(path: String) throws -> [String] {
        let url = try resolvedURL(path)
        return try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { child in
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return (isDirectory ? "\\" : "") + child.lastPathComponent
            }
    }

    public func fileAttributes(path: String) throws -> [Int64]? {
        let url = try resolvedURL(path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType
        let creation = (attributes[.creationDate] as? Date).map { Int64($0.timeIntervalSince1970) } ?? 0
        let modification = (attributes[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970) } ?? 0
        return [0, 0, type == .typeDirectory ? 1 : 0, 0, type == .typeRegular ? 1 : 0, 0, 0, 0, 0,
                creation, modification]
    }

    public func log(_ message: String) {
        logMessages.append(message)
    }

    public func errorLog() -> String {
        logMessages.joined(separator: "\n")
    }

    private func persistenceURL(path: String?) throws -> URL {
        if let path, !path.isEmpty {
            return try resolvedURL(path)
        }
        guard let saveFileURL else {
            throw YayaRuntimeEnvironmentError.capabilityUnavailable("variable persistence")
        }
        return saveFileURL
    }

    private func resolvedURL(_ path: String) throws -> URL {
        guard let rootDirectory else {
            throw YayaRuntimeEnvironmentError.capabilityUnavailable("file access")
        }
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let url = if normalizedPath.hasPrefix("/") {
            URL(fileURLWithPath: normalizedPath)
        } else {
            rootDirectory.appendingPathComponent(normalizedPath)
        }
        return try checked(url)
    }

    private func checked(_ url: URL) throws -> URL {
        guard let rootDirectory else {
            throw YayaRuntimeEnvironmentError.capabilityUnavailable("file access")
        }
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        if let saveFileURL,
           candidate == saveFileURL || candidate.path == saveFileURL.path + ".ays"
        {
            return candidate
        }
        let rootPath = rootDirectory.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw YayaRuntimeEnvironmentError.pathEscapesRoot(candidate.path)
        }
        return candidate
    }

    private func normalizedFileMode(_ mode: String) -> FileMode? {
        switch mode.lowercased() {
        case "r", "rb", "r+", "rb+", "read", "read_binary", "read_random", "read_binary_random": .read
        case "w", "wb", "w+", "wb+", "write", "write_binary", "write_random", "write_binary_random": .write
        case "a", "ab", "a+", "ab+", "append", "append_binary", "append_random", "append_binary_random": .append
        default: nil
        }
    }
}

private enum FileMode: Equatable {
    case read
    case write
    case append
}

private enum OpenFile {
    case read(lines: [String], index: Int)
    case write(FileHandle)
}

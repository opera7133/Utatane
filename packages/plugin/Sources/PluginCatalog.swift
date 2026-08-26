import Foundation

public struct InstalledPlugin: Identifiable, Sendable, Equatable {
    public enum Runtime: Sendable, Equatable {
        case nativeSHIORI(NativeSHIORIKind)
        case dynamicLibrary(URL)
        case windowsDLL(URL)
        case unavailable(URL)
    }

    public enum NativeSHIORIKind: String, Sendable, Equatable {
        case akari
        case kawari
        case misaka
        case satori
        case yaya
    }

    public let id: String
    public let name: String
    public let directory: URL
    public let moduleURL: URL
    public let charset: String
    public let author: String?
    public let authorURL: URL?
    public let homeURL: URL?
    public let readmeURL: URL?
    public let readmeCharset: String?
    public let secondChangeInterval: Int
    public let observesOtherGhostTalk: Bool
    public let runtime: Runtime
}

public struct PluginCatalog: Sendable {
    public init() {}

    public func load(from roots: [URL]) throws -> [InstalledPlugin] {
        var pluginsByID: [String: InstalledPlugin] = [:]
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            let directories = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for directory in directories {
                guard let plugin = Self.load(directory: directory) else { continue }
                pluginsByID[plugin.id.lowercased()] = pluginsByID[plugin.id.lowercased()] ?? plugin
            }
        }
        return pluginsByID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func load(directory: URL) -> InstalledPlugin? {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let descriptor = root.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: descriptor), let metadata = metadata(from: data),
              let name = metadata["name"], !name.isEmpty,
              let id = metadata["id"], isValidID(id),
              metadata["type"]?.lowercased() == nil || metadata["type"]?.lowercased() == "plugin",
              let filename = metadata["filename"],
              let moduleURL = safeFile(named: filename, in: root, mustExist: true)
        else { return nil }

        let runtime = runtime(for: moduleURL, directory: root)
        return InstalledPlugin(
            id: id,
            name: name,
            directory: root,
            moduleURL: moduleURL,
            charset: metadata["charset"] ?? "Shift_JIS",
            author: metadata["craftmanw"] ?? metadata["craftman"],
            authorURL: metadata["craftmanurl"].flatMap(URL.init(string:)),
            homeURL: metadata["homeurl"].flatMap(URL.init(string:)),
            readmeURL: safeFile(named: metadata["readme"] ?? "readme.txt", in: root, mustExist: true),
            readmeCharset: metadata["readme.charset"],
            secondChangeInterval: max(Int(metadata["secondchangeinterval"] ?? "1") ?? 1, 0),
            observesOtherGhostTalk: ["true", "1", "immediate", "delayed"].contains(
                metadata["otherghosttalk"]?.lowercased() ?? ""
            ),
            runtime: runtime
        )
    }

    private static func runtime(for moduleURL: URL, directory: URL) -> InstalledPlugin.Runtime {
        if let kind = nativeSHIORIKind(in: directory) {
            return .nativeSHIORI(kind)
        }
        switch moduleURL.pathExtension.lowercased() {
        case "dylib", "so", "bundle": return .dynamicLibrary(moduleURL)
        case "dll": return .windowsDLL(moduleURL)
        default: return .unavailable(moduleURL)
        }
    }

    private static func nativeSHIORIKind(in directory: URL) -> InstalledPlugin.NativeSHIORIKind? {
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
        if exists("main.amb") || exists("main.azr") || exists("akari.ini") {
            return .akari
        }
        if exists("kawarirc.kis") || exists("kawari.ini") {
            return .kawari
        }
        if exists("misaka.ini") {
            return .misaka
        }
        if exists("satori_conf.txt") || exists("satori.dll") {
            return .satori
        }
        if exists("yaya.txt") || exists("yaya_config.txt") {
            return .yaya
        }
        return nil
    }

    private static func safeFile(named name: String, in root: URL, mustExist: Bool = false) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\") else { return nil }
        let url = root.appending(path: name).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        if mustExist, !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        return url
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 63 && id.unicodeScalars.allSatisfy(\.isASCII)
    }

    private static func metadata(from data: Data) -> [String: String]? {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .ascii)
        else { return nil }
        return source.components(separatedBy: .newlines).reduce(into: [:]) { result, line in
            let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return }
            let key = fields[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.hasPrefix("\\"), !value.hasPrefix("%") else { return }
            result[key] = value
        }
    }
}

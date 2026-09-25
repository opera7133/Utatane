import Foundation

public protocol NativeSaoriCalling: Sendable {
    func load(_ path: String)
    func unload(_ path: String)
    func call(_ path: String, arguments: [String]) -> String
}

public protocol ExternalSaoriModule: AnyObject, Sendable {
    func call(arguments: [String]) -> String
}

public struct NativeSaoriWindowFrame: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public protocol NativeSaoriWindowControlling: Sendable {
    func frame(scope: Int) -> NativeSaoriWindowFrame?
    func desktopSize() -> (width: Int, height: Int)
    func move(scope: Int, x: Int, speed: Int)
}

public final class NativeSaoriRegistry: NativeSaoriCalling, @unchecked Sendable {
    private let lock = NSLock()
    private let baseDirectoryURL: URL
    private let windowController: (any NativeSaoriWindowControlling)?
    private let externalModuleFactory: (@Sendable (URL, URL, (any NativeSaoriWindowControlling)?) -> (any ExternalSaoriModule)?)?
    private let managedModulesURL: URL
    private let prefersExternalWindowsDLL: Bool
    private var externalModules: [String: any ExternalSaoriModule] = [:]

    public init(
        baseDirectoryURL: URL,
        textCopyPasteboardName: String? = nil,
        textCopyHandler: (@Sendable (String) -> Void)? = nil,
        windowController: (any NativeSaoriWindowControlling)? = nil,
        prefersExternalWindowsDLL: Bool = false,
        managedModulesURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/NativeSaori"),
        externalModuleFactory: (@Sendable (URL, URL, (any NativeSaoriWindowControlling)?) -> (any ExternalSaoriModule)?)? = nil
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.windowController = windowController
        self.prefersExternalWindowsDLL = prefersExternalWindowsDLL
        self.managedModulesURL = managedModulesURL
        self.externalModuleFactory = externalModuleFactory
    }

    public func load(_ path: String) {
        lock.withLock { loadUnlocked(path) }
    }

    private func loadUnlocked(_ path: String) {
        let key = moduleKey(path)
        guard externalModules[key] == nil else { return }
        let declaredURL = safeExternalModuleURL(path)
        if let declaredURL, let factory = externalModuleFactory {
            for candidate in nativeCandidates(for: declaredURL) where FileManager.default.fileExists(atPath: candidate.path) {
                if let module = factory(candidate, declaredURL.deletingLastPathComponent(), windowController) {
                    externalModules[key] = module
                    return
                }
            }
        }
        if prefersExternalWindowsDLL, let declaredURL,
           declaredURL.pathExtension.lowercased() == "dll",
           let module = externalModuleFactory?(declaredURL, declaredURL.deletingLastPathComponent(), windowController)
        {
            externalModules[key] = module
            return
        }
        if let declaredURL,
           let module = externalModuleFactory?(declaredURL, declaredURL.deletingLastPathComponent(), windowController)
        {
            externalModules[key] = module
        }
    }

    public func unload(_ path: String) {
        _ = lock.withLock {
            externalModules.removeValue(forKey: moduleKey(path))
        }
    }

    public func call(_ path: String, arguments: [String]) -> String {
        lock.withLock {
            let key = moduleKey(path)
            return externalModules[key]?.call(arguments: arguments) ?? ""
        }
    }

    public func response(path: String, request: String) -> String {
        let arguments = request.components(separatedBy: .newlines).compactMap { line -> (Int, String)? in
            let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard trimmed.lowercased().hasPrefix("argument"), let colon = trimmed.firstIndex(of: ":"),
                  let index = Int(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 8) ..< colon])
            else { return nil }
            return (index, trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }.sorted { $0.0 < $1.0 }.map(\.1)
        guard request.hasPrefix("EXECUTE SAORI/1.") else {
            return request.hasPrefix("GET Version SAORI/1.")
                ? "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\r\n"
                : "SAORI/1.0 400 Bad Request\r\nCharset: Shift_JIS\r\n\r\n"
        }
        let result = call(path, arguments: arguments)
        let values = result.split(separator: "\u{1}", omittingEmptySubsequences: false).map(String.init)
        var headers = ""
        if let first = values.first, !first.isEmpty {
            headers += "Result: \(first)\r\n"
        }
        for (index, value) in values.enumerated() where !value.isEmpty {
            headers += "Value\(index): \(value)\r\n"
        }
        return "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\(headers)\r\n"
    }

    private func moduleKey(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last
            .map(String.init)?.lowercased() ?? ""
    }

    private func resolvedModuleURL(_ path: String) -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasPrefix("/")
            ? URL(filePath: normalized).standardizedFileURL
            : baseDirectoryURL.appending(path: normalized).standardizedFileURL
    }

    private func safeExternalModuleURL(_ path: String) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let url = resolvedModuleURL(normalized)
        guard !normalized.hasPrefix("/") else { return url }
        let basePath = baseDirectoryURL.standardizedFileURL.path
        return basePath == "/" || url.path == basePath || url.path.hasPrefix(basePath + "/") ? url : nil
    }

    private func nativeCandidates(for declaredURL: URL) -> [URL] {
        guard declaredURL.pathExtension.lowercased() == "dll" else { return [] }
        let stem = declaredURL.deletingPathExtension().lastPathComponent.lowercased()
        let directory = declaredURL.deletingLastPathComponent()
        let moduleID = stem == "saori_cpuid" ? "saori-cpuid" : stem
        let managedRoot = ProcessInfo.processInfo.environment["UTATANE_SAORI_ROOT"]
            .flatMap { $0.hasPrefix("/") && !$0.contains("\0") ? URL(filePath: $0) : nil } ?? managedModulesURL
        return [
            directory.appending(path: "\(stem).dylib"),
            directory.appending(path: "lib\(stem).dylib"),
            managedRoot.appending(path: "\(moduleID)/lib/lib\(stem).dylib")
        ]
    }
}

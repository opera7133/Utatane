import CryptoKit
import Foundation

struct AkariVirtualFileSystem: Sendable {
    private let master: URL
    private let storage: URL

    init(master: URL, storage: URL) {
        self.master = master.standardizedFileURL
        self.storage = storage.standardizedFileURL
    }

    func readText(path: String, encoding: String = "auto", newline: String? = nil) -> AkariValue? {
        guard let url = readableURL(path), let data = try? Data(contentsOf: url),
              var text = decode(data, encoding: encoding)
        else { return nil }
        guard newline?.lowercased() != "none" else { return .string(text) }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return .array(text.split(separator: "\n", omittingEmptySubsequences: false).map { .string(String($0)) })
    }

    func writeText(path: String, value: AkariValue, encoding: String = "utf8", newline: String = "crlf") -> Bool {
        let separator = newline.lowercased() == "lf" ? "\n" : "\r\n"
        let text: String = if case let .array(values) = value {
            values.map(\.stringValue).joined(separator: separator)
        } else {
            value.stringValue
        }
        guard let data = encode(text, encoding: encoding), let url = writableURL(path) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func exists(path: String) -> Bool {
        readableURL(path) != nil
    }

    func enumerate(path: String) -> AkariValue? {
        guard let components = components(path) else { return nil }
        var folders = Set<String>()
        var files = Set<String>()
        for root in [master, storage] {
            let directory = append(components, to: root)
            guard isContained(directory, by: root), let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where isContained(entry.resolvingSymlinksInPath(), by: root.resolvingSymlinksInPath()) {
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    folders.insert(entry.lastPathComponent)
                } else {
                    files.insert(entry.lastPathComponent)
                }
            }
        }
        return .dictionary([
            "folder": .array(folders.sorted().map(AkariValue.string)),
            "file": .array(files.sorted().map(AkariValue.string))
        ])
    }

    func absolutePath(path: String) -> String? {
        if let existing = readableURL(path) {
            return existing.path
        }
        return writableURL(path)?.path
    }

    func readCSV(path: String, encoding: String = "auto") -> AkariValue? {
        guard case let .string(text)? = readText(path: path, encoding: encoding, newline: "none") else { return nil }
        return .array(parseCSV(text).map { .array($0.map(AkariValue.string)) })
    }

    func writeCSV(path: String, rows: AkariValue, encoding: String = "utf8") -> Bool {
        guard case let .array(values) = rows else { return false }
        let lines = values.compactMap { row -> String? in
            guard case let .array(columns) = row else { return nil }
            return columns.map { column in
                let value = column.stringValue
                return value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                    ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
            }.joined(separator: ",")
        }
        guard lines.count == values.count else { return false }
        return writeText(path: path, value: .string(lines.joined(separator: "\r\n")), encoding: encoding)
    }

    func saveValue(name: String, value: AkariValue) -> Bool {
        guard let url = writableURL("variables/\(name).json"), let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    func loadValue(name: String) -> AkariValue? {
        guard let url = readableURL("variables/\(name).json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AkariValue.self, from: data)
    }

    func readScript(path: String) -> String? {
        let path = path.lowercased().hasSuffix(".azr") ? path : path + ".azr"
        guard case let .string(source)? = readText(path: path, encoding: "auto", newline: "none") else { return nil }
        return source
    }

    func tokenize(path: String) -> AkariValue? {
        guard case let .string(source)? = readText(path: path, encoding: "auto", newline: "none") else { return nil }
        return .array(AkariPureFunctions.tokenize(source).map(AkariValue.string))
    }

    func md5(path: String) -> String? {
        guard let url = readableURL(path), let data = try? Data(contentsOf: url) else { return nil }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func writeData(path: String, data: Data) -> Bool {
        guard let url = writableURL(path) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    func copy(source: String, destination: String, move: Bool = false) -> Bool {
        guard let sourceURL = readableURL(source), let destinationURL = writableURL(destination) else { return false }
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            if move, isContained(sourceURL, by: storage) {
                try FileManager.default.removeItem(at: sourceURL)
            }
            return true
        } catch { return false }
    }

    func delete(path: String, directory: Bool = false) -> Bool {
        guard let url = writableURL(path), FileManager.default.fileExists(atPath: url.path),
              ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) == directory
        else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch { return false }
    }

    func createDirectory(path: String) -> Bool {
        guard let url = writableURL(path) else { return false }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch { return false }
    }

    private func readableURL(_ path: String) -> URL? {
        guard let parts = components(path) else { return nil }
        for root in [storage, master] {
            let candidate = append(parts, to: root)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isContained(candidate.resolvingSymlinksInPath(), by: root.resolvingSymlinksInPath())
            else { continue }
            return candidate
        }
        return nil
    }

    private func writableURL(_ path: String) -> URL? {
        guard let parts = components(path), !parts.isEmpty, !containsSymbolicLink(parts, under: storage) else { return nil }
        let candidate = append(parts, to: storage)
        return isContained(candidate, by: storage) ? candidate : nil
    }

    private func containsSymbolicLink(_ components: [String], under root: URL) -> Bool {
        var candidate = root
        for component in components {
            candidate.append(path: component)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return true
            }
        }
        return false
    }

    private func components(_ path: String) -> [String]? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"), !normalized.hasPrefix("~"),
              !normalized.contains(":")
        else { return nil }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.contains("..") else { return nil }
        return parts.filter { $0 != "." }
    }

    private func append(_ components: [String], to root: URL) -> URL {
        components.reduce(root) { $0.appending(path: $1) }.standardizedFileURL
    }

    private func isContained(_ candidate: URL, by root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func decode(_ data: Data, encoding: String) -> String? {
        switch encoding.lowercased().replacingOccurrences(of: "-", with: "") {
        case "utf8": String(data: data, encoding: .utf8)
        case "sjis", "shiftjis": String(data: data, encoding: .shiftJIS)
        case "auto", "": String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
        default: nil
        }
    }

    private func encode(_ text: String, encoding: String) -> Data? {
        switch encoding.lowercased().replacingOccurrences(of: "-", with: "") {
        case "utf8", "auto", "": text.data(using: .utf8)
        case "sjis", "shiftjis": text.data(using: .shiftJIS)
        default: nil
        }
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character.isNewline, !quoted {
                if character == "\n", index > text.startIndex, text[text.index(before: index)] == "\r" {
                    index = text.index(after: index)
                    continue
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" || quoted {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

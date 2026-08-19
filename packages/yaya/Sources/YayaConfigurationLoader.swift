import Foundation

public enum YayaConfigurationError: Error, Equatable, Sendable {
    case fileNotFound(String)
    case unreadableText(String)
    case unsupportedEncoding(String)
    case pathEscapesRoot(String)
    case includeCycle(String)
}

public struct YayaConfigurationLoader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(masterDirectory: URL, settingsFileName: String = "yaya.txt") throws -> YayaConfiguration {
        let root = masterDirectory.standardizedFileURL
        let settingsURL = root.appendingPathComponent(settingsFileName).standardizedFileURL
        var state = LoaderState(rootDirectory: root)
        try loadSettings(
            at: settingsURL,
            settingsEncoding: nil,
            loadDirectory: root,
            baseDirectory: root,
            state: &state
        )
        return YayaConfiguration(
            rootDirectory: root,
            dictionaries: state.dictionaries,
            includedConfigurationURLs: state.includedConfigurationURLs,
            settings: state.settings,
            diagnostics: state.diagnostics
        )
    }

    private func loadSettings(
        at url: URL,
        settingsEncoding: YayaTextEncoding?,
        loadDirectory: URL,
        baseDirectory: URL,
        state: inout LoaderState
    ) throws {
        let checkedURL = try checked(url, under: state.rootDirectory)
        guard fileManager.fileExists(atPath: checkedURL.path) else {
            throw YayaConfigurationError.fileNotFound(checkedURL.path)
        }
        guard !state.activeIncludes.contains(checkedURL) else {
            throw YayaConfigurationError.includeCycle(checkedURL.path)
        }

        let text = try readText(at: checkedURL, encoding: settingsEncoding)
        state.activeIncludes.insert(checkedURL)
        state.includedConfigurationURLs.append(checkedURL)
        defer { state.activeIncludes.remove(checkedURL) }

        for (offset, sourceLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(from: sourceLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let fields = splitFields(line)
            let command = fields[0].lowercased()
            let arguments = Array(fields.dropFirst())
            state.settings[command, default: []].append(arguments.joined(separator: ", "))

            switch command {
            case "charset.dic":
                guard let name = arguments.first, let encoding = YayaTextEncoding(name: name) else {
                    throw YayaConfigurationError.unsupportedEncoding(arguments.first ?? "")
                }
                state.dictionaryEncoding = encoding

            case "include", "includeex":
                guard let fileName = arguments.first, !fileName.isEmpty else { continue }
                let includeURL = loadDirectory.appendingPathComponent(unquote(fileName)).standardizedFileURL
                let explicitEncoding = try encoding(from: arguments.dropFirst().first)
                let includeDirectory = includeURL.deletingLastPathComponent()
                try loadSettings(
                    at: includeURL,
                    settingsEncoding: explicitEncoding,
                    loadDirectory: command == "includeex" ? includeDirectory : loadDirectory,
                    baseDirectory: command == "includeex" ? includeDirectory : baseDirectory,
                    state: &state
                )

            case "dic", "dicif":
                guard let fileName = arguments.first, !fileName.isEmpty else { continue }
                let dictionaryURL = try checked(
                    baseDirectory.appendingPathComponent(unquote(fileName)),
                    under: state.rootDirectory
                )
                let explicitEncoding = try encoding(from: arguments.dropFirst().first)
                let isOptional = command == "dicif"
                let exists = fileManager.fileExists(atPath: dictionaryURL.path)
                if exists || !isOptional {
                    state.dictionaries.append(YayaDictionarySource(
                        url: dictionaryURL,
                        encoding: explicitEncoding ?? state.dictionaryEncoding,
                        isOptional: isOptional
                    ))
                }
                if !exists, !isOptional {
                    state.diagnostics.append(YayaDiagnostic(
                        severity: .error,
                        url: checkedURL,
                        line: lineNumber,
                        message: "Dictionary does not exist: \(dictionaryURL.lastPathComponent)"
                    ))
                }

            case "dicdir":
                guard let directoryName = arguments.first, !directoryName.isEmpty else { continue }
                let directoryURL = try checked(
                    baseDirectory.appendingPathComponent(unquote(directoryName)),
                    under: state.rootDirectory
                )
                let explicitEncoding = try encoding(from: arguments.dropFirst().first)
                appendDictionaryDirectory(
                    directoryURL,
                    encoding: explicitEncoding ?? state.dictionaryEncoding,
                    sourceURL: checkedURL,
                    line: lineNumber,
                    state: &state
                )

            default:
                break
            }
        }
    }

    private func appendDictionaryDirectory(
        _ directoryURL: URL,
        encoding: YayaTextEncoding,
        sourceURL: URL,
        line: Int,
        state: inout LoaderState
    ) {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            state.diagnostics.append(YayaDiagnostic(
                severity: .error,
                url: sourceURL,
                line: line,
                message: "Dictionary directory does not exist: \(directoryURL.lastPathComponent)"
            ))
            return
        }

        let urls = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.caseInsensitiveCompare("dic") == .orderedSame }
            .sorted { $0.path < $1.path }
        state.dictionaries.append(contentsOf: urls.map {
            YayaDictionarySource(url: $0.standardizedFileURL, encoding: encoding, isOptional: false)
        })

        let override = directoryURL.appendingPathComponent("_loading_order_override.txt")
        let order = directoryURL.appendingPathComponent("_loading_order.txt")
        if fileManager.fileExists(atPath: override.path) || fileManager.fileExists(atPath: order.path) {
            state.diagnostics.append(YayaDiagnostic(
                severity: .warning,
                url: sourceURL,
                line: line,
                message: "dicdir loading-order files are not supported yet; lexical order was used"
            ))
        }
    }

    private func readText(at url: URL, encoding: YayaTextEncoding?) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw YayaConfigurationError.fileNotFound(url.path)
        }

        if let encoding {
            guard let text = String(data: data, encoding: encoding.foundationEncoding) else {
                throw YayaConfigurationError.unreadableText(url.path)
            }
            return strippingByteOrderMark(text)
        }
        if let text = String(data: data, encoding: .utf8) {
            return strippingByteOrderMark(text)
        }
        if let text = String(data: data, encoding: .shiftJIS) {
            return strippingByteOrderMark(text)
        }
        throw YayaConfigurationError.unreadableText(url.path)
    }

    private func encoding(from name: String?) throws -> YayaTextEncoding? {
        guard let name, !name.isEmpty else { return nil }
        guard let encoding = YayaTextEncoding(name: name) else {
            throw YayaConfigurationError.unsupportedEncoding(name)
        }
        return encoding
    }

    private func checked(_ url: URL, under root: URL) throws -> URL {
        let candidate = url.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw YayaConfigurationError.pathEscapesRoot(candidate.path)
        }
        return candidate
    }

    private func splitFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                current.append(character)
            } else if character == ",", quote == nil {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func stripComment(from line: String) -> String {
        var quote: Character?
        var previous: Character?
        for index in line.indices {
            let character = line[index]
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }
            if character == "/", previous == "/", quote == nil {
                return String(line[..<line.index(before: index)])
            }
            previous = character
        }
        return line
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else { return value }
        return String(value.dropFirst().dropLast())
    }

    private func strippingByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}

private struct LoaderState {
    let rootDirectory: URL
    var dictionaryEncoding: YayaTextEncoding = .shiftJIS
    var dictionaries: [YayaDictionarySource] = []
    var includedConfigurationURLs: [URL] = []
    var settings: [String: [String]] = [:]
    var diagnostics: [YayaDiagnostic] = []
    var activeIncludes: Set<URL> = []
}

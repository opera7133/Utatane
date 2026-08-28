import AppKit
import CKawariNative
import Foundation
import UtataneNativeSaori
import UtataneShiori

private let kawariSaoriLock = NSLock()
private let activeKawariSaori = KawariSaoriSlot()

private final class KawariSaoriSlot: @unchecked Sendable {
    var registry: NativeSaoriRegistry?
}

public enum NativeKawariError: LocalizedError, Equatable, Sendable {
    case loadFailed
    case requestFailed
    case undecodableResponse

    public var errorDescription: String? {
        switch self {
        case .loadFailed:
            "KAWARIがゴーストの読み込みに失敗した。"
        case .requestFailed:
            "KAWARIへのリクエストに失敗した。"
        case .undecodableResponse:
            "KAWARIの応答をShift_JISとして読み取れなかった。"
        }
    }
}

public final class NativeKawariSession: @unchecked Sendable {
    private let handle: UInt32
    private let compatibilityDirectoryURL: URL?
    private let usesLegacyCompatibility: Bool
    private let legacyDoubleClickEntries: [String: String]
    private let legacySurfaceRestoreScript: String?
    private let saoriRegistry: NativeSaoriRegistry

    public init(masterDirectoryURL: URL, saoriRegistry: NativeSaoriRegistry? = nil) throws {
        Self.installNativeSaoriCallback()
        self.saoriRegistry = saoriRegistry ?? NativeSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        let preparation = try Self.prepareDirectoryIfNeeded(masterDirectoryURL)
        let preparedDirectory = preparation.directory
        compatibilityDirectoryURL = preparation.isLegacy ? preparedDirectory : nil
        usesLegacyCompatibility = preparation.isLegacy
        legacyDoubleClickEntries = preparation.doubleClickEntries
        legacySurfaceRestoreScript = preparation.surfaceRestoreScript
        let path = preparedDirectory.standardizedFileURL.path + "/"
        guard let data = path.data(using: .shiftJIS) else {
            throw NativeKawariError.loadFailed
        }
        handle = data.withUnsafeBytes { bytes in
            utatane_kawari_create(
                bytes.bindMemory(to: CChar.self).baseAddress,
                Int64(data.count)
            )
        }
        guard handle != 0 else {
            throw NativeKawariError.loadFailed
        }
    }

    private static func installNativeSaoriCallback() {
        utatane_kawari_set_saori_request_callback(utataneKawariSaoriRequest)
    }

    deinit {
        _ = utatane_kawari_dispose(handle)
        if let compatibilityDirectoryURL {
            try? FileManager.default.removeItem(at: compatibilityDirectoryURL)
        }
    }

    private static func prepareDirectoryIfNeeded(_ masterDirectoryURL: URL) throws -> (
        directory: URL,
        isLegacy: Bool,
        doubleClickEntries: [String: String],
        surfaceRestoreScript: String?
    ) {
        let currentConfig = masterDirectoryURL.appending(path: "kawarirc.kis")
        guard !FileManager.default.fileExists(atPath: currentConfig.path) else {
            return (masterDirectoryURL, false, [:], nil)
        }

        let legacyConfig = masterDirectoryURL.appending(path: "kawari.ini")
        guard FileManager.default.fileExists(atPath: legacyConfig.path) else {
            return (masterDirectoryURL, false, [:], nil)
        }
        let data = try Data(contentsOf: legacyConfig)
        guard let source = String(data: data, encoding: .shiftJIS) else {
            throw NativeKawariError.loadFailed
        }

        var startupCommands: [String] = []
        var dictionaryFilenames: [String] = []
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"),
                  let colon = line.firstIndex(of: ":")
            else { continue }
            let command = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let argument = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch command {
            case "set": startupCommands.append("set \(argument);")
            case "dict", "include":
                dictionaryFilenames.append(argument)
            default: continue
            }
        }

        var eventIDs = Set<String>()
        var generatedDictionaries: [(filename: String, data: Data)] = []
        var doubleClickEntries: [String: String] = [:]
        var legacyEntries: [String: [String]] = [:]
        for (dictionaryIndex, filename) in dictionaryFilenames.enumerated() {
            let dictionaryURL = masterDirectoryURL.appending(path: filename)
            guard let data = try? Data(contentsOf: dictionaryURL),
                  var dictionary = String(data: data, encoding: .shiftJIS)
            else { continue }
            doubleClickEntries.merge(extractLegacyDoubleClickEntries(from: dictionary)) { _, newer in newer }
            dictionary = translateLegacyIfSyntax(in: dictionary)
            for index in (0 ... 7).reversed() {
                dictionary = dictionary.replacingOccurrences(
                    of: "system.Reference\(index)",
                    with: "System.Request.Reference\(index + 1)"
                )
            }
            for rawLine in dictionary.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard let colon = line.firstIndex(of: ":") else {
                    continue
                }
                let entryName = line[..<colon].trimmingCharacters(in: .whitespaces)
                let entryValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !entryName.isEmpty {
                    legacyEntries[entryName, default: []].append(entryValue)
                }
                if entryName.hasPrefix("event.") {
                    eventIDs.insert(String(entryName.dropFirst(6)))
                }
            }
            for (lineIndex, rawLine) in dictionary.components(separatedBy: .newlines).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), line.contains(":") else {
                    continue
                }
                let generatedFilename = "legacy-\(dictionaryIndex)-\(lineIndex).dat"
                guard let lineData = (line + "\r\n").data(using: .shiftJIS) else {
                    continue
                }
                generatedDictionaries.append((generatedFilename, lineData))
                startupCommands.append("load \(generatedFilename);")
            }
        }
        var compatibilityEntries: [String] = []
        if !eventIDs.contains("OnAITalk") {
            compatibilityEntries.append("event.OnAITalk : ${talk}")
        }
        var commands = compatibilityEntries + ["=kis", "debugger on;"]
        commands.append(contentsOf: startupCommands)
        commands.append("=end")

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Utatane-KAWARI-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for item in try FileManager.default.contentsOfDirectory(at: masterDirectoryURL, includingPropertiesForKeys: nil) {
                let destination = directory.appending(path: item.lastPathComponent)
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: item)
            }
            for generated in generatedDictionaries {
                try generated.data.write(
                    to: directory.appending(path: generated.filename),
                    options: .atomic
                )
            }
            guard let configData = commands.joined(separator: "\r\n").data(using: .shiftJIS) else {
                throw NativeKawariError.loadFailed
            }
            try configData.write(to: directory.appending(path: "kawarirc.kis"), options: .atomic)
            return (
                directory,
                true,
                doubleClickEntries,
                extractLegacySurfaceRestoreScript(from: legacyEntries)
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func extractLegacyDoubleClickEntries(from dictionary: String) -> [String: String] {
        var entries: [String: String] = [:]
        for rawLine in dictionary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("event.OnMouseDoubleClick") else { continue }
            let aliasPattern = #"set\s+([A-Za-z0-9_.]+)\s+\$\{system\.Reference4\}"#
            let aliasExpression = try? NSRegularExpression(pattern: aliasPattern)
            let range = NSRange(line.startIndex ..< line.endIndex, in: line)
            let alias = aliasExpression?.firstMatch(in: line, range: range).flatMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: line) else { return nil }
                return String(line[range])
            }
            let reference = alias.map { NSRegularExpression.escapedPattern(for: $0) }
                ?? "system\\.Reference4"
            let pattern = #"\$\(\[\s*\$\{"# + reference
                + #"\}\s*==\s*"([^"]+)"\s*\]\)\s*\$\{([^}]+)\}"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: line, range: range) {
                guard let regionRange = Range(match.range(at: 1), in: line),
                      let entryRange = Range(match.range(at: 2), in: line)
                else { continue }
                entries[String(line[regionRange])] = String(line[entryRange])
            }
        }
        return entries
    }

    private static func extractLegacySurfaceRestoreScript(from entries: [String: [String]]) -> String? {
        var pending = ["event.OnSurfaceRestore"]
        var visited = Set<String>()
        var surfaces: [Int: Int] = [:]
        let referenceExpression = try? NSRegularExpression(pattern: #"\$\{([A-Za-z0-9_.]+)\}"#)
        let surfaceExpression = try? NSRegularExpression(pattern: #"\\([01])\\s\[(-?\d+)\]"#)

        while let entry = pending.popLast() {
            guard visited.insert(entry).inserted else { continue }
            for value in entries[entry] ?? [] {
                let range = NSRange(value.startIndex ..< value.endIndex, in: value)
                for match in referenceExpression?.matches(in: value, range: range) ?? [] {
                    guard let nameRange = Range(match.range(at: 1), in: value) else { continue }
                    let name = String(value[nameRange])
                    if entries[name] != nil {
                        pending.append(name)
                    }
                }
                for quotedValue in quotedContents(in: value) {
                    let quotedRange = NSRange(quotedValue.startIndex ..< quotedValue.endIndex, in: quotedValue)
                    for match in surfaceExpression?.matches(in: quotedValue, range: quotedRange) ?? [] {
                        guard let scopeRange = Range(match.range(at: 1), in: quotedValue),
                              let surfaceRange = Range(match.range(at: 2), in: quotedValue),
                              let scope = Int(quotedValue[scopeRange]), let surface = Int(quotedValue[surfaceRange])
                        else { continue }
                        surfaces[scope] = surface
                    }
                }
            }
        }
        guard !surfaces.isEmpty else { return nil }
        return surfaces.keys.sorted(by: >).map { "\\\($0)\\s[\(surfaces[$0]!)]" }.joined()
    }

    private static func quotedContents(in source: String) -> [String] {
        let characters = Array(source)
        var values: [String] = []
        var start: Int?
        var escaped = false
        for index in characters.indices {
            let character = characters[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            guard character == "\"" else { continue }
            if let openingIndex = start {
                values.append(String(characters[(openingIndex + 1) ..< index]))
                start = nil
            } else {
                start = index
            }
        }
        return values
    }

    static func translateLegacyIfSyntax(in source: String) -> String {
        translateLegacyIfSyntax(in: Array(source))
    }

    private static func translateLegacyIfSyntax(in characters: [Character]) -> String {
        var result = ""
        var index = 0
        while index < characters.count {
            guard index + 1 < characters.count,
                  characters[index] == "$", characters[index + 1] == "("
            else {
                result.append(characters[index])
                index += 1
                continue
            }
            guard let closingIndex = matchingParenthesis(in: characters, openingAt: index + 1) else {
                result.append(characters[index])
                index += 1
                continue
            }
            let body = Array(characters[(index + 2) ..< closingIndex])
            let translatedBody = translateLegacyIfSyntax(in: body)
            let commands = topLevelCommands(in: translatedBody)
            if commands.count > 1 {
                result += commands.map { "$(" + addLegacyElseIfNeeded(to: $0) + ")" }.joined()
            } else {
                result += "$(" + addLegacyElseIfNeeded(to: translatedBody) + ")"
            }
            index = closingIndex + 1
        }
        return result
    }

    private static func matchingParenthesis(in characters: [Character], openingAt openingIndex: Int) -> Int? {
        var depth = 0
        var quote: Character?
        var escaped = false
        for index in openingIndex ..< characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }

    private static func addLegacyElseIfNeeded(to body: String) -> String {
        let characters = Array(body)
        let words = topLevelWordRanges(in: characters)
        guard words.count >= 4,
              String(characters[words[0]]).lowercased() == "if",
              String(characters[words[3]]).lowercased() != "else"
        else { return body }
        let insertionIndex = words[3].lowerBound
        return String(characters[..<insertionIndex]) + "else " + String(characters[insertionIndex...])
    }

    private static func topLevelWordRanges(in characters: [Character]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var wordStart: Int?
        var parenthesisDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var quote: Character?
        var escaped = false

        for index in characters.indices {
            let character = characters[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else {
                switch character {
                case "(": parenthesisDepth += 1
                case ")": parenthesisDepth -= 1
                case "{": braceDepth += 1
                case "}": braceDepth -= 1
                case "[": bracketDepth += 1
                case "]": bracketDepth -= 1
                default: break
                }
            }

            let isSeparator = character.isWhitespace
                && parenthesisDepth == 0 && braceDepth == 0 && bracketDepth == 0 && quote == nil
            if isSeparator, let start = wordStart {
                ranges.append(start ..< index)
                wordStart = nil
            } else if !isSeparator, wordStart == nil {
                wordStart = index
            }
        }
        if let wordStart {
            ranges.append(wordStart ..< characters.count)
        }
        return ranges
    }

    private static func topLevelCommands(in body: String) -> [String] {
        let characters = Array(body)
        var commands: [String] = []
        var commandStart = 0
        var parenthesisDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var quote: Character?
        var escaped = false

        for index in characters.indices {
            let character = characters[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else {
                switch character {
                case "(": parenthesisDepth += 1
                case ")": parenthesisDepth -= 1
                case "{": braceDepth += 1
                case "}": braceDepth -= 1
                case "[": bracketDepth += 1
                case "]": bracketDepth -= 1
                default: break
                }
            }
            guard character == ";", parenthesisDepth == 0, braceDepth == 0,
                  bracketDepth == 0, quote == nil
            else { continue }
            let command = String(characters[commandStart ..< index]).trimmingCharacters(in: .whitespaces)
            if !command.isEmpty {
                commands.append(command)
            }
            commandStart = index + 1
        }
        let command = String(characters[commandStart...]).trimmingCharacters(in: .whitespaces)
        if !command.isEmpty {
            commands.append(command)
        }
        return commands
    }

    public func request(_ request: ShioriRequest) throws -> ShioriResponse {
        guard usesLegacyCompatibility, let id = request.id else {
            return try ShioriMessageParser.parseResponse(self.request(request.serialized()))
        }
        let entry = id == "OnMouseDoubleClick"
            ? request.reference(4).flatMap { legacyDoubleClickEntries[$0] }
            : nil
        let effectiveRequest = legacyEchoRequest(
            expression: "${\(entry ?? "event.\(id)")}",
            originalRequest: request
        )
        var response = try ShioriMessageParser.parseResponse(self.request(effectiveRequest.serialized()))
        if id == "OnSurfaceRestore", response.value == #"\e"#, let legacySurfaceRestoreScript {
            response.headers = ShioriHeaders(response.headers.entries.map { header in
                header.name.caseInsensitiveCompare("Value") == .orderedSame
                    ? ShioriHeader(name: header.name, value: legacySurfaceRestoreScript + #"\e"#)
                    : header
            })
        }
        return response
    }

    private func legacyEchoRequest(expression: String, originalRequest request: ShioriRequest) -> ShioriRequest {
        var headers = ShioriHeaders([
            ShioriHeader(name: "Charset", value: "Shift_JIS"),
            ShioriHeader(name: "Sender", value: request.headers["Sender"] ?? "Utatane"),
            ShioriHeader(name: "SecurityLevel", value: request.headers["SecurityLevel"] ?? "local"),
            ShioriHeader(name: "ID", value: "ShioriEcho"),
            ShioriHeader(name: "Reference0", value: expression)
        ])
        for index in 0 ... 7 {
            if let value = request.reference(index) {
                headers.append(name: "Reference\(index + 1)", value: value)
            }
        }
        return ShioriRequest(method: "GET", headers: headers)
    }

    public func request(_ request: String) throws -> String {
        kawariSaoriLock.lock()
        defer { kawariSaoriLock.unlock() }
        activeKawariSaori.registry = saoriRegistry
        defer { activeKawariSaori.registry = nil }
        guard let data = request.data(using: .shiftJIS) else {
            throw NativeKawariError.undecodableResponse
        }
        var responseLength = Int64(data.count)
        let responsePointer = data.withUnsafeBytes { bytes in
            utatane_kawari_request(
                handle,
                bytes.bindMemory(to: CChar.self).baseAddress,
                &responseLength
            )
        }
        guard let responsePointer, responseLength >= 0 else {
            throw NativeKawariError.requestFailed
        }
        defer { utatane_kawari_free(responsePointer) }
        let responseData = Data(bytes: responsePointer, count: Int(responseLength))
        guard let response = String(data: responseData, encoding: .shiftJIS) else {
            throw NativeKawariError.undecodableResponse
        }
        return response
    }
}

private func utataneKawariSaoriRequest(
    _ path: UnsafePointer<CChar>?,
    _ request: UnsafePointer<CChar>?,
    _ length: UnsafeMutablePointer<Int64>?
) -> UnsafeMutablePointer<CChar>? {
    guard let path, let request, let length, length.pointee >= 0 else { return nil }
    let data = Data(bytes: request, count: Int(length.pointee))
    guard let message = String(data: data, encoding: .shiftJIS) else { return nil }

    let modulePath = String(cString: path)
    activeKawariSaori.registry?.load(modulePath)
    let response = activeKawariSaori.registry?.response(path: modulePath, request: message)
        ?? "SAORI/1.0 500 Internal Server Error\r\n\r\n"
    guard let responseData = response.data(using: .shiftJIS),
          let allocation = malloc(max(responseData.count, 1))
    else { return nil }
    responseData.copyBytes(to: allocation.assumingMemoryBound(to: UInt8.self), count: responseData.count)
    length.pointee = Int64(responseData.count)
    return allocation.assumingMemoryBound(to: CChar.self)
}

func nativeTextCopySaoriResponse(for message: String, pasteboardName: String? = nil) -> String {
    let registry = NativeSaoriRegistry(baseDirectoryURL: URL(filePath: "/"), textCopyPasteboardName: pasteboardName)
    registry.load("textcopy2.dll")
    return registry.response(path: "textcopy2.dll", request: message)
}

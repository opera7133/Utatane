import Foundation
import UtataneRuntime

public struct SatoriConversionResult: Sendable, Equatable {
    public let catalog: DialogueCatalog
    public let sourceFileCount: Int
    public let convertedEntryCount: Int
    public let skippedEntryCount: Int

    public init(
        catalog: DialogueCatalog,
        sourceFileCount: Int,
        convertedEntryCount: Int,
        skippedEntryCount: Int
    ) {
        self.catalog = catalog
        self.sourceFileCount = sourceFileCount
        self.convertedEntryCount = convertedEntryCount
        self.skippedEntryCount = skippedEntryCount
    }
}

public enum SatoriDictionaryConverterError: LocalizedError {
    case missingDirectory(URL)
    case unreadableFile(URL)

    public var errorDescription: String? {
        switch self {
        case let .missingDirectory(url):
            "Satori辞書ディレクトリが見つからない: \(url.path)"
        case let .unreadableFile(url):
            "Satori辞書をUTF-8またはShift JISで読み込めない: \(url.path)"
        }
    }
}

public struct SatoriDictionaryConverter: Sendable {
    private static let bootEntryNames: Set<String> = ["通常起動", "OnBoot"]
    private static let closeEntryNames: Set<String> = ["終了", "OnClose"]
    private static let randomTalkEntryNames: Set<String> = ["", "通常トーク", "PCトーク", "アニメトーク"]

    public init() {}

    public func convert(masterDirectory: URL) throws -> SatoriConversionResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: masterDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw SatoriDictionaryConverterError.missingDirectory(masterDirectory)
        }

        let sourceURLs = try FileManager.default.contentsOfDirectory(
            at: masterDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            url.pathExtension.lowercased() == "txt" && url.lastPathComponent.lowercased().hasPrefix("dic")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var entries: [Entry] = []
        for sourceURL in sourceURLs {
            try entries.append(contentsOf: parse(source: readSource(at: sourceURL)))
        }

        return makeResult(entries: entries, sourceFileCount: sourceURLs.count)
    }

    public func convert(source: String) -> SatoriConversionResult {
        makeResult(entries: parse(source: source), sourceFileCount: 1)
    }

    private func readSource(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let source = String(data: data, encoding: .utf8) {
            return source
        }
        if let source = String(data: data, encoding: .shiftJIS) {
            return source
        }
        throw SatoriDictionaryConverterError.unreadableFile(url)
    }

    private func parse(source: String) -> [Entry] {
        var entries: [Entry] = []
        var current: Entry?

        func finishCurrent() {
            if let current {
                entries.append(current)
            }
        }

        source.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("＊") {
                finishCurrent()
                current = Entry(
                    name: String(line.dropFirst()).trimmingCharacters(in: .whitespaces),
                    dialogueLines: [],
                    hasUnsupportedControl: false
                )
                return
            }

            guard current != nil, !line.isEmpty, !line.hasPrefix("＃") else { return }
            if line.hasPrefix("＞") || line.hasPrefix("＄") || line.hasPrefix("＠") {
                current?.hasUnsupportedControl = true
            } else if line.hasPrefix("：") {
                current?.dialogueLines.append(String(line.dropFirst()))
            } else if line.hasPrefix("\\") || current?.dialogueLines.isEmpty == false {
                current?.dialogueLines.append(line)
            }
        }
        finishCurrent()
        return entries
    }

    private func makeResult(entries: [Entry], sourceFileCount: Int) -> SatoriConversionResult {
        var boot: [String] = []
        var close: [String] = []
        var randomTalk: [String] = []
        var choices: [String: [String]] = [:]
        var convertedEntryCount = 0
        var skippedEntryCount = 0

        for entry in entries {
            guard !entry.hasUnsupportedControl,
                  !entry.dialogueLines.isEmpty,
                  let script = makeScript(from: entry.dialogueLines)
            else {
                skippedEntryCount += 1
                continue
            }

            convertedEntryCount += 1
            if Self.bootEntryNames.contains(entry.name) {
                boot.append(script)
            } else if Self.closeEntryNames.contains(entry.name) {
                close.append(script)
            } else if Self.randomTalkEntryNames.contains(entry.name) {
                randomTalk.append(script)
            } else {
                choices[entry.name, default: []].append(script)
            }
        }

        return SatoriConversionResult(
            catalog: DialogueCatalog(
                boot: boot,
                close: close,
                randomTalk: randomTalk,
                choices: choices
            ),
            sourceFileCount: sourceFileCount,
            convertedEntryCount: convertedEntryCount,
            skippedEntryCount: skippedEntryCount
        )
    }

    private func makeScript(from lines: [String]) -> String? {
        let body = lines
            .map(convertSurfaceMarkers(in:))
            .joined(separator: "\\n")
            .replacingOccurrences(of: "\\-", with: "\\e")
        guard !body.isEmpty else { return nil }
        return body.hasSuffix("\\e") ? body : body + "\\e"
    }

    private func convertSurfaceMarkers(in line: String) -> String {
        var output = ""
        var remainder = line[...]

        while let opening = remainder.firstIndex(of: "（"),
              let closing = remainder[remainder.index(after: opening)...].firstIndex(of: "）")
        {
            let digits = remainder[remainder.index(after: opening) ..< closing]
            guard let surface = surfaceNumber(from: digits) else {
                output += String(remainder[...closing])
                remainder = remainder[remainder.index(after: closing)...]
                continue
            }

            output += String(remainder[..<opening])
            let scope = (10 ... 19).contains(surface) ? 1 : 0
            output += "\\\(scope)\\s[\(surface)]"
            remainder = remainder[remainder.index(after: closing)...]
        }

        return output + remainder
    }

    private func surfaceNumber(from value: Substring) -> Int? {
        let normalized = value.map { character -> Character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1,
                  (0xFF10 ... 0xFF19).contains(scalar.value),
                  let ascii = UnicodeScalar(scalar.value - 0xFF10 + 0x30)
            else {
                return character
            }
            return Character(ascii)
        }
        return Int(String(normalized))
    }
}

private struct Entry {
    let name: String
    var dialogueLines: [String]
    var hasUnsupportedControl: Bool
}

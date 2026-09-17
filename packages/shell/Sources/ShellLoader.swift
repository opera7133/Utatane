import Foundation
import UtataneCore

public enum ShellError: LocalizedError, Equatable {
    case missingFile(URL)
    case unsupportedTextEncoding(URL)
    case missingSurface(id: Int, directory: URL)
    case missingElement(filename: String, directory: URL)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            "必要なファイルがない: \(url.path)"
        case let .unsupportedTextEncoding(url):
            "文字コードを判定できない: \(url.path)"
        case let .missingSurface(id, directory):
            "surface\(id)が見つからない: \(directory.path)"
        case let .missingElement(filename, directory):
            "Surface要素\(filename)が見つからない: \(directory.path)"
        }
    }
}

public struct ShellLoader: Sendable {
    private static let surfaceImageExtensions = ["png", "apng", "gif", "webp"]

    private let parser = SurfacesParser()
    private let surfaceTableParser = SurfaceTableParser()

    public init() {}

    public func load(from shellDirectory: URL) throws -> ShellDefinition {
        let fileManager = FileManager.default
        let shellFiles = try fileManager.contentsOfDirectory(
            at: shellDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let surfacesURLs = shellFiles.filter {
            $0.pathExtension.lowercased() == "txt"
                && $0.lastPathComponent.lowercased().hasPrefix("surfaces")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let legacySurfaceURLs = shellFiles.compactMap { url -> (url: URL, surfaceID: Int)? in
            legacySurfaceID(from: url.lastPathComponent).map { (url, $0) }
        }.sorted {
            if $0.surfaceID != $1.surfaceID {
                return $0.surfaceID < $1.surfaceID
            }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        let existingSurfaceIDs = try Set(fileManager.contentsOfDirectory(atPath: shellDirectory.path).compactMap {
            surfaceID(fromImageFilename: $0)
        })
        guard !surfacesURLs.isEmpty || !legacySurfaceURLs.isEmpty || !existingSurfaceIDs.isEmpty else {
            throw ShellError.missingFile(
                shellDirectory.appending(path: "surfaces.txt", directoryHint: .notDirectory)
            )
        }

        var sources = try legacySurfaceURLs.map { entry in
            try "surface\(entry.surfaceID)\n{\n\(readText(from: entry.url))\n}"
        }
        try sources.append(contentsOf: surfacesURLs.map(readText(from:)))
        if surfacesURLs.isEmpty, legacySurfaceURLs.isEmpty {
            sources.append(existingSurfaceIDs.sorted().map { "surface\($0) {}" }.joined(separator: "\n"))
        }
        let aliasURL = shellDirectory.appending(path: "alias.txt", directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: aliasURL.path) {
            try sources.append(readText(from: aliasURL))
        }
        let document = parser.parseDocument(
            sources.joined(separator: "\n"),
            existingSurfaceIDs: existingSurfaceIDs
        )
        let shellMetadata = metadata(in: shellDirectory)
        let surfaceTableURL = shellDirectory.appending(path: "surfacetable.txt", directoryHint: .notDirectory)
        let surfaceTable = fileManager.fileExists(atPath: surfaceTableURL.path)
            ? try surfaceTableParser.parse(readText(from: surfaceTableURL))
            : nil
        return ShellDefinition(
            directory: shellDirectory,
            surfaces: document.surfaces,
            surfaceAliases: document.aliases,
            usesSelfAlpha: shellMetadata.usesSelfAlpha,
            usesFullSelfAlpha: shellMetadata.usesFullSelfAlpha,
            defaultBindGroups: shellMetadata.defaultBindGroups,
            bindGroups: shellMetadata.bindGroups,
            bindOptions: shellMetadata.bindOptions,
            bindMenuItems: shellMetadata.bindMenuItems,
            hiddenBindMenuScopes: shellMetadata.hiddenBindMenuScopes,
            surfaceTable: surfaceTable,
            maximumSurfaceWidth: document.maximumSurfaceWidth,
            cursorDefinitions: document.cursorDefinitions,
            tooltips: document.tooltips,
            zOrder: shellMetadata.zOrder,
            stickyWindowScopes: shellMetadata.stickyWindowScopes,
            desktopAlignment: shellMetadata.desktopAlignment,
            presentationSettings: shellMetadata.presentationSettings
        )
    }

    public func loadSurface(id: Int, from shellDirectory: URL) throws -> SurfaceAsset {
        let candidates = [
            String(format: "surface%04d", id),
            "surface\(id)"
        ]
        let fileManager = FileManager.default

        for basename in candidates {
            guard let imageURL = Self.surfaceImageExtensions
                .map({ shellDirectory.appending(path: "\(basename).\($0)", directoryHint: .notDirectory) })
                .first(where: { fileManager.fileExists(atPath: $0.path) })
            else { continue }

            let maskURL = shellDirectory.appending(path: "\(basename).pna", directoryHint: .notDirectory)
            return SurfaceAsset(
                id: id,
                imageURL: imageURL,
                alphaMaskURL: fileManager.fileExists(atPath: maskURL.path) ? maskURL : nil
            )
        }

        throw ShellError.missingSurface(id: id, directory: shellDirectory)
    }

    public func loadElement(filename: String, from shellDirectory: URL) throws -> SurfaceAsset {
        let root = shellDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var normalizedFilename = normalizeLegacyPath(filename)
        while normalizedFilename.lowercased().hasSuffix(".png.png") {
            normalizedFilename.removeLast(4)
        }
        let imageURL = shellDirectory
            .appending(path: normalizedFilename, directoryHint: .notDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard Self.surfaceImageExtensions.contains(imageURL.pathExtension.lowercased()),
              imageURL.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: imageURL.path)
        else {
            throw ShellError.missingElement(filename: filename, directory: shellDirectory)
        }

        let maskURL = imageURL.deletingPathExtension().appendingPathExtension("pna")
        return SurfaceAsset(
            id: -1,
            imageURL: imageURL,
            alphaMaskURL: FileManager.default.fileExists(atPath: maskURL.path) ? maskURL : nil
        )
    }

    public func loadAnimation(filename: String, from shellDirectory: URL) throws -> URL {
        let root = shellDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedFilename = normalizeLegacyPath(filename)
        let imageURL = shellDirectory
            .appending(path: normalizedFilename, directoryHint: .notDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard ["png", "apng", "gif", "webp"].contains(imageURL.pathExtension.lowercased()),
              imageURL.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: imageURL.path)
        else {
            throw ShellError.missingElement(filename: filename, directory: shellDirectory)
        }
        return imageURL
    }

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = LegacyTextDecoder.decode(data) else {
            throw ShellError.unsupportedTextEncoding(url)
        }
        return text
    }

    private func normalizeLegacyPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "¥", with: "/")
    }

    private func legacySurfaceID(from filename: String) -> Int? {
        let name = filename.lowercased()
        guard name.hasPrefix("surface"), name.hasSuffix(".txt") else { return nil }
        let suffixStart = name.index(name.endIndex, offsetBy: -5)
        guard ["a", "s"].contains(name[suffixStart]) else { return nil }
        let idStart = name.index(name.startIndex, offsetBy: "surface".count)
        return Int(name[idStart ..< suffixStart])
    }

    private func metadata(in shellDirectory: URL) -> (
        usesSelfAlpha: Bool,
        usesFullSelfAlpha: Bool,
        defaultBindGroups: [Int: Set<Int>],
        bindGroups: [Int: [Int: ShellBindGroup]],
        bindOptions: [Int: [String: ShellBindOptions]],
        bindMenuItems: [Int: [ShellBindMenuItem]],
        hiddenBindMenuScopes: Set<Int>,
        zOrder: [Int],
        stickyWindowScopes: [Int],
        desktopAlignment: ShellDesktopAlignment?,
        presentationSettings: [Int: ShellScopePresentationSettings]
    ) {
        let url = shellDirectory.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard let text = try? readText(from: url) else {
            return (false, false, [:], [:], [:], [:], [], [], [], nil, [:])
        }
        var usesSelfAlpha = false
        var usesFullSelfAlpha = false
        var defaultBindGroups: [Int: Set<Int>] = [:]
        var groupNames: [Int: [Int: (category: String, part: String, thumbnail: String)]] = [:]
        var groupAddIDs: [Int: [Int: Set<Int>]] = [:]
        var bindOptions: [Int: [String: ShellBindOptions]] = [:]
        var bindMenuBuilders: [Int: [Int: ShellBindMenuItem]] = [:]
        var hiddenBindMenuScopes = Set<Int>()
        var zOrder: [Int] = []
        var stickyWindowScopes: [Int] = []
        var desktopAlignment: ShellDesktopAlignment?
        var presentationBuilders: [Int: ShellScopePresentationBuilder] = [:]
        for line in text.split(whereSeparator: \ .isNewline) {
            let fields = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count == 2 else { continue }
            if fields[0].caseInsensitiveCompare("seriko.use_self_alpha") == .orderedSame {
                let value = fields[1].lowercased()
                usesSelfAlpha = value == "1" || value == "true" || value == "full"
                usesFullSelfAlpha = value == "full"
                continue
            }
            let key = fields[0].lowercased()
            if key == "seriko.zorder" {
                zOrder = integerList(fields[1])
                continue
            }
            if key == "seriko.sticky-window" {
                stickyWindowScopes = integerList(fields[1])
                continue
            }
            if key == "seriko.alignmenttodesktop" {
                desktopAlignment = ShellDesktopAlignment(rawValue: fields[1].lowercased())
                continue
            }
            if let (scope, property) = scopedKey(key) {
                var builder = presentationBuilders[scope] ?? .init()
                switch property {
                case "seriko.alignmenttodesktop":
                    builder.desktopAlignment = ShellDesktopAlignment(rawValue: fields[1].lowercased())
                case "defaultx":
                    builder.defaultX = Int(fields[1])
                case "defaulty":
                    builder.defaultY = Int(fields[1])
                case "defaultleft":
                    builder.defaultLeft = Int(fields[1])
                case "defaulttop":
                    builder.defaultTop = Int(fields[1])
                case "balloon.offsetx":
                    builder.balloonOffsetX = Int(fields[1])
                case "balloon.offsety":
                    builder.balloonOffsetY = Int(fields[1])
                case "balloon.offsetxl":
                    builder.balloonOffsetLeftX = Int(fields[1])
                case "balloon.offsetyl":
                    builder.balloonOffsetLeftY = Int(fields[1])
                case "balloon.offsetxr":
                    builder.balloonOffsetRightX = Int(fields[1])
                case "balloon.offsetyr":
                    builder.balloonOffsetRightY = Int(fields[1])
                case "balloon.alignment":
                    builder.balloonAlignment = ShellBalloonAlignment(rawValue: fields[1].lowercased())
                case "balloon.dontmove":
                    builder.preventsBalloonMovement = boolean(fields[1])
                case "balloon.syncscale":
                    builder.synchronizesBalloonScale = fields[1].caseInsensitiveCompare("true") == .orderedSame
                case "menu":
                    if fields[1].caseInsensitiveCompare("hidden") == .orderedSame {
                        hiddenBindMenuScopes.insert(scope)
                    }
                default:
                    break
                }
                presentationBuilders[scope] = builder
            }
            if let (scope, remainder) = scopedMetadataKey(key, marker: "bindgroup"),
               let separator = remainder.firstIndex(of: "."),
               let groupID = Int(remainder[..<separator])
            {
                let property = remainder[remainder.index(after: separator)...]
                if property == "default", fields[1] == "1" {
                    defaultBindGroups[scope, default: []].insert(groupID)
                } else if property == "name" {
                    let values = fields[1].split(
                        separator: ",",
                        maxSplits: 2,
                        omittingEmptySubsequences: false
                    ).map(String.init)
                    guard values.count >= 2 else { continue }
                    groupNames[scope, default: [:]][groupID] = (
                        values[0], values[1], values.count >= 3 ? values[2] : ""
                    )
                } else if property == "addid" {
                    groupAddIDs[scope, default: [:]][groupID] = Set(
                        fields[1].split(separator: ",").compactMap { Int($0) }
                    )
                }
                continue
            }
            if let (scope, indexText) = scopedMetadataKey(key, marker: "menuitemex"),
               let index = Int(indexText)
            {
                let values = fields[1].split(
                    separator: ",",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard values.count == 2, let groupID = Int(values[1]) else { continue }
                bindMenuBuilders[scope, default: [:]][index] = .group(id: groupID, title: values[0])
                continue
            }
            if let (scope, indexText) = scopedMetadataKey(key, marker: "menuitem"),
               let index = Int(indexText)
            {
                bindMenuBuilders[scope, default: [:]][index] = fields[1] == "-"
                    ? .separator
                    : Int(fields[1]).map { .group(id: $0) }
                continue
            }
            if let (scope, remainder) = scopedMetadataKey(key, marker: "bindoption"),
               remainder.hasSuffix(".group")
            {
                let values = fields[1].split(separator: ",", maxSplits: 1).map(String.init)
                guard values.count == 2 else { continue }
                let options = Set(values[1].lowercased().split(separator: "+").map(String.init))
                bindOptions[scope, default: [:]][values[0]] = ShellBindOptions(
                    mustSelect: options.contains("mustselect"),
                    multiple: options.contains("multiple")
                )
            }
        }
        var bindGroups: [Int: [Int: ShellBindGroup]] = [:]
        for (scope, scopeGroups) in groupNames {
            bindGroups[scope] = Dictionary(uniqueKeysWithValues: scopeGroups.map { id, value in
                (id, ShellBindGroup(
                    id: id,
                    category: value.category,
                    part: value.part,
                    thumbnail: value.thumbnail,
                    addIDs: groupAddIDs[scope]?[id] ?? []
                ))
            })
        }
        return (
            usesSelfAlpha,
            usesFullSelfAlpha,
            defaultBindGroups,
            bindGroups,
            bindOptions,
            bindMenuBuilders.mapValues { builder in
                builder.keys.sorted().compactMap { builder[$0] }
            },
            hiddenBindMenuScopes,
            zOrder,
            stickyWindowScopes,
            desktopAlignment,
            presentationBuilders.mapValues(\.settings)
        )
    }

    private func integerList(_ value: String) -> [Int] {
        value.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func boolean(_ value: String) -> Bool {
        ["1", "true", "on"].contains(value.lowercased())
    }

    private func scopedKey(_ key: String) -> (scope: Int, property: Substring)? {
        if key.hasPrefix("sakura.") {
            return (0, key.dropFirst("sakura.".count))
        }
        if key.hasPrefix("kero.") {
            return (1, key.dropFirst("kero.".count))
        }
        guard key.hasPrefix("char"), let separator = key.firstIndex(of: "."),
              let scope = Int(key[key.index(key.startIndex, offsetBy: 4) ..< separator])
        else { return nil }
        return (scope, key[key.index(after: separator)...])
    }

    private func scopedMetadataKey(_ key: String, marker: String) -> (Int, Substring)? {
        if key.hasPrefix("sakura.\(marker)") {
            return (0, key.dropFirst("sakura.\(marker)".count))
        }
        if key.hasPrefix("kero.\(marker)") {
            return (1, key.dropFirst("kero.\(marker)".count))
        }
        guard key.hasPrefix("char"), let separator = key.firstIndex(of: "."),
              let scope = Int(key[key.index(key.startIndex, offsetBy: 4) ..< separator])
        else { return nil }
        let prefix = ".\(marker)"
        guard key[separator...].hasPrefix(prefix) else { return nil }
        return (scope, key[key.index(separator, offsetBy: prefix.count)...])
    }

    private func surfaceID(fromImageFilename filename: String) -> Int? {
        let lowercased = filename.lowercased()
        guard lowercased.hasPrefix("surface") else { return nil }
        let extensions = Self.surfaceImageExtensions.map { ".\($0)" }
        guard let suffix = extensions.first(where: lowercased.hasSuffix) else { return nil }
        return Int(lowercased.dropFirst("surface".count).dropLast(suffix.count))
    }
}

private struct ShellScopePresentationBuilder {
    var desktopAlignment: ShellDesktopAlignment?
    var defaultX: Int?
    var defaultY: Int?
    var defaultLeft: Int?
    var defaultTop: Int?
    var balloonOffsetX: Int?
    var balloonOffsetY: Int?
    var balloonOffsetLeftX: Int?
    var balloonOffsetLeftY: Int?
    var balloonOffsetRightX: Int?
    var balloonOffsetRightY: Int?
    var balloonAlignment: ShellBalloonAlignment?
    var preventsBalloonMovement = false
    var synchronizesBalloonScale = false

    var settings: ShellScopePresentationSettings {
        ShellScopePresentationSettings(
            desktopAlignment: desktopAlignment,
            defaultX: defaultX,
            defaultY: defaultY,
            defaultLeft: defaultLeft,
            defaultTop: defaultTop,
            balloonOffsets: ShellBalloonOffsets(
                x: balloonOffsetX,
                y: balloonOffsetY,
                leftX: balloonOffsetLeftX,
                leftY: balloonOffsetLeftY,
                rightX: balloonOffsetRightX,
                rightY: balloonOffsetRightY
            ),
            balloonAlignment: balloonAlignment,
            preventsBalloonMovement: preventsBalloonMovement,
            synchronizesBalloonScale: synchronizesBalloonScale
        )
    }
}

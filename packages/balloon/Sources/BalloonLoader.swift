import Foundation
import UtataneCore

public enum BalloonError: LocalizedError, Equatable {
    case missingFile(URL)
    case unsupportedTextEncoding(URL)
    case invalidType(URL)
    case missingImage(speaker: String, style: Int, directory: URL)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            "必要なファイルがない: \(url.path)"
        case let .unsupportedTextEncoding(url):
            "文字コードを判定できない: \(url.path)"
        case let .invalidType(url):
            "バルーンではない: \(url.path)"
        case let .missingImage(speaker, style, directory):
            "\(speaker)側のballoon\(style)画像が見つからない: \(directory.path)"
        }
    }
}

public struct BalloonLoader: Sendable {
    private let parser = BalloonDescriptParser()

    public init() {}

    public func loadInstalled(from rootDirectories: [URL]) throws -> [BalloonDefinition] {
        var seenDirectoryNames = Set<String>()
        var balloons: [BalloonDefinition] = []
        for rootDirectory in rootDirectories {
            for balloon in try loadInstalled(from: rootDirectory) {
                guard seenDirectoryNames.insert(balloon.directory.lastPathComponent).inserted else { continue }
                balloons.append(balloon)
            }
        }
        return balloons.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func loadInstalled(from rootDirectory: URL) throws -> [BalloonDefinition] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? load(from: directory)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func load(from directory: URL) throws -> BalloonDefinition {
        let descriptURL = directory.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: descriptURL.path) else {
            throw BalloonError.missingFile(descriptURL)
        }

        let data = try Data(contentsOf: descriptURL)
        guard let text = LegacyTextDecoder.decode(data) else {
            throw BalloonError.unsupportedTextEncoding(descriptURL)
        }
        let values = parser.parse(text)
        guard values["type"]?.lowercased() == "balloon" else {
            throw BalloonError.invalidType(descriptURL)
        }

        return definition(in: directory, values: values)
    }

    public func effectiveDefinition(
        for balloon: BalloonDefinition,
        speaker: BalloonSpeaker,
        style: Int
    ) -> BalloonDefinition {
        let descriptURL = balloon.directory.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard let baseText = try? readText(from: descriptURL) else { return balloon }
        var values = parser.parse(baseText)
        if let overrideURL = overrideURL(speaker: speaker, style: style, in: balloon.directory),
           let overrideText = try? readText(from: overrideURL)
        {
            values.merge(parser.parse(overrideText)) { _, override in override }
        }
        return definition(in: balloon.directory, values: values)
    }

    private func definition(in directory: URL, values: [String: String]) -> BalloonDefinition {
        let isVertical = boolean("vertical", in: values)
        let validRectLeft = integer("validrect.left", in: values, default: 14)
        let validRectTop = integer("validrect.top", in: values, default: 14)
        let validRectRight = values["validrect.right"].flatMap(Int.init)
        let validRectBottom = values["validrect.bottom"].flatMap(Int.init)

        return BalloonDefinition(
            directory: directory,
            name: values["name"] ?? directory.lastPathComponent,
            originX: textOrigin(
                originKey: "origin.x",
                validRectKey: isVertical ? "validrect.right" : "validrect.left",
                in: values,
                default: 14
            ),
            originY: textOrigin(
                originKey: "origin.y",
                validRectKey: "validrect.top",
                in: values,
                default: 14
            ),
            wordWrapPointX: integer("wordwrappoint.x", in: values, default: -14),
            wordWrapPointY: integer(
                "wordwrappoint.y",
                in: values,
                default: isVertical ? (validRectBottom ?? 0) : 0
            ),
            fontHeight: integer("font.height", in: values, default: 12),
            fontColor: BalloonColor(
                red: integer("font.color.r", in: values, default: 0),
                green: integer("font.color.g", in: values, default: 0),
                blue: integer("font.color.b", in: values, default: 0)
            ),
            validRectLeft: validRectLeft,
            validRectTop: validRectTop,
            validRectRight: validRectRight,
            validRectBottom: validRectBottom,
            isVertical: isVertical,
            fontName: values["font.name"],
            fontShadowColor: color(prefix: "font.shadowcolor", in: values),
            fontShadowStyle: values["font.shadowstyle"]?.lowercased(),
            fontBold: boolean("font.bold", in: values),
            fontItalic: boolean("font.italic", in: values),
            fontUnderline: boolean("font.underline", in: values),
            fontStrike: boolean("font.strike", in: values),
            fontOutline: boolean("font.outline", in: values),
            arrow0X: integer("arrow0.x", in: values, default: 0),
            arrow0Y: integer("arrow0.y", in: values, default: 0),
            arrow1X: integer("arrow1.x", in: values, default: 0),
            arrow1Y: integer("arrow1.y", in: values, default: 0),
            clickWaitMarkerX: values["clickwaitmarker.x"].flatMap(Int.init),
            clickWaitMarkerY: values["clickwaitmarker.y"].flatMap(Int.init),
            numberFontName: values["number.font.name"],
            numberFontHeight: integer("number.font.height", in: values, default: 10),
            numberFontColor: BalloonColor(
                red: integer("number.font.color.r", in: values, default: 0),
                green: integer("number.font.color.g", in: values, default: 0),
                blue: integer("number.font.color.b", in: values, default: 0)
            ),
            numberRightX: integer("number.xr", in: values, default: -28),
            numberY: integer("number.y", in: values, default: -24),
            usesSelfAlpha: boolean("use_self_alpha", in: values),
            windowPositionX: windowPositionX(in: values),
            windowPositionY: integer("windowposition.y", in: values, default: 0),
            limitsWindowPosition: !values.keys.contains("windowposition.limit")
                || boolean("windowposition.limit", in: values),
            cursorStyle: linkAppearance(prefix: "cursor", in: values, defaultShape: .underline),
            cursorNotSelectedStyle: linkAppearance(prefix: "cursor.notselect", in: values, defaultShape: .none),
            anchorStyle: linkAppearance(prefix: "anchor", in: values, defaultShape: .underline),
            anchorNotSelectedStyle: linkAppearance(prefix: "anchor.notselect", in: values, defaultShape: .none),
            anchorVisitedStyle: linkAppearance(prefix: "anchor.visited", in: values, defaultShape: .none)
        )
    }

    public func markerImageURL(speaker: BalloonSpeaker, style: Int = 0, in balloon: BalloonDefinition) -> URL? {
        if let filename = overrideValues(speaker: speaker, style: style, in: balloon.directory)?["marker.filename"],
           let url = imageURL(filename: filename, suffix: "", in: balloon.directory)
        {
            return url
        }
        let names: [String] = switch speaker {
        case .sakura:
            ["markers.png", "marker.png"]
        case .kero:
            ["markerk.png", "marker.png"]
        case let .character(scope):
            ["markerp\(scope)def.png", "markerk.png", "marker.png"]
        }
        return names.lazy
            .map { balloon.directory.appending(path: $0, directoryHint: .notDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func arrowImageURL(
        index: Int,
        speaker: BalloonSpeaker = .sakura,
        style: Int = 0,
        in balloon: BalloonDefinition
    ) -> URL? {
        if let filename = overrideValues(speaker: speaker, style: style, in: balloon.directory)?["arrow.filename"],
           let url = imageURL(filename: filename, suffix: String(index), in: balloon.directory)
        {
            return url
        }
        let url = balloon.directory.appending(
            path: "arrow\(index).png",
            directoryHint: .notDirectory
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func clickWaitMarkerImageURL(
        speaker: BalloonSpeaker,
        style: Int,
        in balloon: BalloonDefinition
    ) -> URL? {
        guard let filename = overrideValues(
            speaker: speaker,
            style: style,
            in: balloon.directory
        )?["clickwaitmarker.filename"] else {
            return arrowImageURL(index: 1, speaker: speaker, style: style, in: balloon)
        }
        return imageURL(filename: filename, suffix: "", in: balloon.directory)
    }

    public func imageURL(
        speaker: BalloonSpeaker,
        style: Int = 0,
        in balloon: BalloonDefinition
    ) throws -> URL {
        for imageName in speaker.imageNames(style: style) {
            let url = balloon.directory.appending(path: imageName, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw BalloonError.missingImage(
            speaker: speaker.description,
            style: style,
            directory: balloon.directory
        )
    }

    private func integer(
        _ key: String,
        in values: [String: String],
        default defaultValue: Int
    ) -> Int {
        values[key].flatMap(Int.init) ?? defaultValue
    }

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = LegacyTextDecoder.decode(data) else {
            throw BalloonError.unsupportedTextEncoding(url)
        }
        return text
    }

    private func overrideURL(speaker: BalloonSpeaker, style: Int, in directory: URL) -> URL? {
        let basename = switch speaker {
        case .sakura: "balloons\(style)s"
        case .kero: "balloonk\(style)s"
        case let .character(scope): "balloonp\(scope)def\(style)s"
        }
        let url = directory.appending(path: "\(basename).txt", directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func overrideValues(
        speaker: BalloonSpeaker,
        style: Int,
        in directory: URL
    ) -> [String: String]? {
        guard let url = overrideURL(speaker: speaker, style: style, in: directory),
              let text = try? readText(from: url)
        else { return nil }
        return parser.parse(text)
    }

    private func imageURL(filename: String, suffix: String, in directory: URL) -> URL? {
        let base = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("/"), !base.contains("\\") else { return nil }
        let candidate = suffix.isEmpty ? base : base + suffix
        let name = URL(filePath: candidate).pathExtension.isEmpty ? "\(candidate).png" : candidate
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func textOrigin(
        originKey: String,
        validRectKey: String,
        in values: [String: String],
        default defaultValue: Int
    ) -> Int {
        if let origin = values[originKey].flatMap(Int.init), origin != 0 {
            return origin
        }
        return integer(validRectKey, in: values, default: defaultValue)
    }

    private func boolean(_ key: String, in values: [String: String]) -> Bool {
        guard let value = values[key]?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "on"
    }

    private func windowPositionX(in values: [String: String]) -> BalloonWindowPositionX {
        guard let value = values["windowposition.x"]?.lowercased() else { return .offset(0) }
        if value == "center" || value == "top" {
            return .center
        }
        if value == "bottom" {
            return .bottom
        }
        return .offset(Int(value) ?? 0)
    }

    private func linkAppearance(
        prefix: String,
        in values: [String: String],
        defaultShape: BalloonLinkShape
    ) -> BalloonLinkAppearance {
        BalloonLinkAppearance(
            shape: values["\(prefix).style"]
                .flatMap { BalloonLinkShape(rawValue: $0.lowercased()) } ?? defaultShape,
            fontColor: color(prefix: "\(prefix).font.color", in: values),
            penColor: color(prefix: "\(prefix).pen.color", in: values),
            brushColor: color(prefix: "\(prefix).brush.color", in: values)
        )
    }

    private func color(prefix: String, in values: [String: String]) -> BalloonColor? {
        guard let red = values["\(prefix).r"].flatMap(Int.init),
              let green = values["\(prefix).g"].flatMap(Int.init),
              let blue = values["\(prefix).b"].flatMap(Int.init)
        else { return nil }
        return BalloonColor(red: red, green: green, blue: blue)
    }
}

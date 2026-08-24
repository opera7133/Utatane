import Foundation

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
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else {
            throw BalloonError.unsupportedTextEncoding(descriptURL)
        }
        let values = parser.parse(text)
        guard values["type"]?.lowercased() == "balloon" else {
            throw BalloonError.invalidType(descriptURL)
        }

        return BalloonDefinition(
            directory: directory,
            name: values["name"] ?? directory.lastPathComponent,
            originX: textOrigin(
                originKey: "origin.x",
                validRectKey: "validrect.left",
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
            wordWrapPointY: integer("wordwrappoint.y", in: values, default: 0),
            fontHeight: integer("font.height", in: values, default: 12),
            fontColor: BalloonColor(
                red: integer("font.color.r", in: values, default: 0),
                green: integer("font.color.g", in: values, default: 0),
                blue: integer("font.color.b", in: values, default: 0)
            ),
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
            cursorStyle: linkAppearance(prefix: "cursor", in: values, defaultShape: .underline),
            cursorNotSelectedStyle: linkAppearance(prefix: "cursor.notselect", in: values, defaultShape: .none),
            anchorStyle: linkAppearance(prefix: "anchor", in: values, defaultShape: .underline),
            anchorNotSelectedStyle: linkAppearance(prefix: "anchor.notselect", in: values, defaultShape: .none)
        )
    }

    public func markerImageURL(speaker: BalloonSpeaker, in balloon: BalloonDefinition) -> URL? {
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

    public func arrowImageURL(index: Int, in balloon: BalloonDefinition) -> URL? {
        let url = balloon.directory.appending(
            path: "arrow\(index).png",
            directoryHint: .notDirectory
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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

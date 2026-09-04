import AppKit
import CNicxliveRenderer
import Foundation

public struct NijigenerateViewportConfiguration: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var contentScale: Double
    public var contentOffsetX: Double
    public var contentOffsetY: Double
    public var interactionOffsetX: Double
    public var interactionOffsetY: Double
    public var interactionScaleX: Double
    public var interactionScaleY: Double

    public init(
        width: Double = 420,
        height: Double = 720,
        contentScale: Double = 0.96,
        contentOffsetX: Double = 0,
        contentOffsetY: Double = 0,
        interactionOffsetX: Double? = nil,
        interactionOffsetY: Double? = nil,
        interactionScaleX: Double = 1,
        interactionScaleY: Double = 1
    ) {
        self.width = width
        self.height = height
        self.contentScale = contentScale
        self.contentOffsetX = contentOffsetX
        self.contentOffsetY = contentOffsetY
        self.interactionOffsetX = interactionOffsetX ?? contentOffsetX
        self.interactionOffsetY = interactionOffsetY ?? contentOffsetY
        self.interactionScaleX = interactionScaleX
        self.interactionScaleY = interactionScaleY
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case contentScale
        case contentOffsetX
        case contentOffsetY
        case interactionOffsetX
        case interactionOffsetY
        case interactionScaleX
        case interactionScaleY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 420
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 720
        contentScale = try container.decodeIfPresent(Double.self, forKey: .contentScale) ?? 0.96
        contentOffsetX = try container.decodeIfPresent(Double.self, forKey: .contentOffsetX) ?? 0
        contentOffsetY = try container.decodeIfPresent(Double.self, forKey: .contentOffsetY) ?? 0
        interactionOffsetX = try container.decodeIfPresent(Double.self, forKey: .interactionOffsetX) ?? contentOffsetX
        interactionOffsetY = try container.decodeIfPresent(Double.self, forKey: .interactionOffsetY) ?? contentOffsetY
        interactionScaleX = try container.decodeIfPresent(Double.self, forKey: .interactionScaleX) ?? 1
        interactionScaleY = try container.decodeIfPresent(Double.self, forKey: .interactionScaleY) ?? 1
    }

    var size: NSSize {
        NSSize(width: max(1, width), height: max(1, height))
    }

    var safeContentScale: CGFloat {
        max(0.01, contentScale)
    }
}

public struct NijigenerateReactionConfiguration: Codable, Sendable, Equatable {
    public var event: String
    public var region: String?
    public var button: Int?
    public var transitionMilliseconds: Int
    public var durationMilliseconds: Int
    public var restoreMilliseconds: Int
    public var parameters: [String: Double]

    public init(
        event: String,
        region: String? = nil,
        button: Int? = nil,
        transitionMilliseconds: Int = 120,
        durationMilliseconds: Int = 500,
        restoreMilliseconds: Int = 220,
        parameters: [String: Double]
    ) {
        self.event = event
        self.region = region
        self.button = button
        self.transitionMilliseconds = transitionMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.restoreMilliseconds = restoreMilliseconds
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case region
        case button
        case transitionMilliseconds
        case durationMilliseconds
        case restoreMilliseconds
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        button = try container.decodeIfPresent(Int.self, forKey: .button)
        transitionMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .transitionMilliseconds
        ) ?? 120
        durationMilliseconds = try container.decodeIfPresent(Int.self, forKey: .durationMilliseconds) ?? 500
        restoreMilliseconds = try container.decodeIfPresent(Int.self, forKey: .restoreMilliseconds) ?? 220
        parameters = try container.decode([String: Double].self, forKey: .parameters)
    }

    func matches(event: String, region: String?, button: Int) -> Bool {
        guard self.event.caseInsensitiveCompare(event) == .orderedSame else { return false }
        if let expectedRegion = self.region,
           expectedRegion.caseInsensitiveCompare(region ?? "") != .orderedSame
        {
            return false
        }
        return self.button == nil || self.button == button
    }
}

public struct NijigeneratePointerConfiguration: Codable, Sendable, Equatable {
    public var xParameter: String
    public var yParameter: String
    public var centerX: Double
    public var centerY: Double
    public var rangeX: Double
    public var rangeY: Double
    public var response: Double
    public var restoreMilliseconds: Int

    public init(
        xParameter: String = "Interaction::LookX",
        yParameter: String = "Interaction::LookY",
        centerX: Double,
        centerY: Double,
        rangeX: Double,
        rangeY: Double,
        response: Double = 0.35,
        restoreMilliseconds: Int = 180
    ) {
        self.xParameter = xParameter
        self.yParameter = yParameter
        self.centerX = centerX
        self.centerY = centerY
        self.rangeX = rangeX
        self.rangeY = rangeY
        self.response = response
        self.restoreMilliseconds = restoreMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case xParameter
        case yParameter
        case centerX
        case centerY
        case rangeX
        case rangeY
        case response
        case restoreMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xParameter = try container.decodeIfPresent(String.self, forKey: .xParameter) ?? "Interaction::LookX"
        yParameter = try container.decodeIfPresent(String.self, forKey: .yParameter) ?? "Interaction::LookY"
        centerX = try container.decode(Double.self, forKey: .centerX)
        centerY = try container.decode(Double.self, forKey: .centerY)
        rangeX = try container.decode(Double.self, forKey: .rangeX)
        rangeY = try container.decode(Double.self, forKey: .rangeY)
        response = try container.decodeIfPresent(Double.self, forKey: .response) ?? 0.35
        restoreMilliseconds = try container.decodeIfPresent(Int.self, forKey: .restoreMilliseconds) ?? 180
    }

    func values(x: Int, y: Int) -> (x: Double, y: Double) {
        let xRange = max(1, abs(rangeX))
        let yRange = max(1, abs(rangeY))
        return (
            max(-1, min(1, (Double(x) - centerX) / xRange)),
            max(-1, min(1, (centerY - Double(y)) / yRange))
        )
    }

    var safeResponse: Double {
        max(0.01, min(1, response))
    }
}

public struct NijigenerateDragConfiguration: Codable, Sendable, Equatable {
    public var region: String
    public var parameter: String
    public var rangeX: Double
    public var rangeY: Double
    public var restoreMilliseconds: Int

    public init(
        region: String,
        parameter: String,
        rangeX: Double,
        rangeY: Double,
        restoreMilliseconds: Int = 180
    ) {
        self.region = region
        self.parameter = parameter
        self.rangeX = rangeX
        self.rangeY = rangeY
        self.restoreMilliseconds = restoreMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case region
        case parameter
        case rangeX
        case rangeY
        case restoreMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = try container.decode(String.self, forKey: .region)
        parameter = try container.decode(String.self, forKey: .parameter)
        rangeX = try container.decode(Double.self, forKey: .rangeX)
        rangeY = try container.decode(Double.self, forKey: .rangeY)
        restoreMilliseconds = try container.decodeIfPresent(Int.self, forKey: .restoreMilliseconds) ?? 180
    }

    func values(deltaX: Int, deltaY: Int) -> (x: Double, y: Double) {
        (
            normalized(delta: Double(deltaX), range: rangeX),
            normalized(delta: Double(deltaY), range: rangeY)
        )
    }

    private func normalized(delta: Double, range: Double) -> Double {
        guard abs(range) >= 1 else { return 0 }
        return max(0, min(1, delta / range))
    }
}

public struct NijigenerateShellConfiguration: Codable, Sendable, Equatable {
    public var viewport: NijigenerateViewportConfiguration
    public var pointer: NijigeneratePointerConfiguration?
    public var drag: NijigenerateDragConfiguration?
    public var parameters: [String: Double]
    public var surfaces: [String: [String: Double]]
    public var reactions: [NijigenerateReactionConfiguration]

    public init(
        viewport: NijigenerateViewportConfiguration = .init(),
        pointer: NijigeneratePointerConfiguration? = nil,
        drag: NijigenerateDragConfiguration? = nil,
        parameters: [String: Double] = [:],
        surfaces: [String: [String: Double]] = [:],
        reactions: [NijigenerateReactionConfiguration] = []
    ) {
        self.viewport = viewport
        self.pointer = pointer
        self.drag = drag
        self.parameters = parameters
        self.surfaces = surfaces
        self.reactions = reactions
    }

    private enum CodingKeys: String, CodingKey {
        case viewport
        case pointer
        case drag
        case parameters
        case surfaces
        case reactions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewport = try container.decodeIfPresent(
            NijigenerateViewportConfiguration.self,
            forKey: .viewport
        ) ?? .init()
        pointer = try container.decodeIfPresent(NijigeneratePointerConfiguration.self, forKey: .pointer)
        drag = try container.decodeIfPresent(NijigenerateDragConfiguration.self, forKey: .drag)
        parameters = try container.decodeIfPresent([String: Double].self, forKey: .parameters) ?? [:]
        surfaces = try container.decodeIfPresent([String: [String: Double]].self, forKey: .surfaces) ?? [:]
        reactions = try container.decodeIfPresent(
            [NijigenerateReactionConfiguration].self,
            forKey: .reactions
        ) ?? []
    }

    func parameters(for surfaceID: Int) -> [String: Double] {
        parameters.merging(surfaces[String(surfaceID)] ?? [:]) { _, surfaceValue in
            surfaceValue
        }
    }

    static func load(from url: URL, fileManager: FileManager = .default) -> Self {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return configuration
    }
}

public struct NijigenerateShellRuntime: Sendable, Equatable {
    public let puppetURL: URL
    public let libraryURL: URL
    public let configuration: NijigenerateShellConfiguration

    public init(
        puppetURL: URL,
        libraryURL: URL,
        configuration: NijigenerateShellConfiguration = .init()
    ) {
        self.puppetURL = puppetURL
        self.libraryURL = libraryURL
        self.configuration = configuration
    }

    /// Finds the opt-in experimental renderer. A conventional `puppet.inp`
    /// keeps the shell usable by other Ukagaka implementations through its
    /// normal surfaces, while Utatane can add live rendering when available.
    public static func locate(
        shellDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> Self? {
        let puppetURL = if let path = environment["UTATANE_NIJIGENERATE_PUPPET"], !path.isEmpty {
            URL(filePath: path, directoryHint: .notDirectory)
        } else {
            shellDirectory.appending(path: "puppet.inp", directoryHint: .notDirectory)
        }
        guard fileManager.fileExists(atPath: puppetURL.path) else { return nil }

        let userRuntimeDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let libraryCandidates: [URL] = if let path = environment["UTATANE_NICXLIVE_LIBRARY"], !path.isEmpty {
            [URL(filePath: path, directoryHint: .notDirectory)]
        } else {
            [
                bundle.privateFrameworksURL?
                    .appending(path: "libnicxlive.dylib", directoryHint: .notDirectory),
                userRuntimeDirectory?
                    .appending(path: "Utatane/Runtimes/nicxlive/libnicxlive.dylib")
            ].compactMap(\.self)
        }
        guard let libraryURL = libraryCandidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else { return nil }
        let configurationURL = puppetURL.deletingLastPathComponent()
            .appending(path: "nijigenerate.json", directoryHint: .notDirectory)
        return Self(
            puppetURL: puppetURL,
            libraryURL: libraryURL,
            configuration: .load(from: configurationURL, fileManager: fileManager)
        )
    }
}

@MainActor
enum NijigenerateViewFactory {
    static func lastFrameHadVisiblePixels(_ view: NSView) -> Bool {
        UTNicxliveViewLastFrameHadVisiblePixels(view)
    }

    static func make(runtime: NijigenerateShellRuntime, size: NSSize) throws -> NSView {
        var rendererError: NSError?
        guard let view = UTCreateNicxliveView(
            NSRect(origin: .zero, size: size),
            runtime.puppetURL,
            runtime.libraryURL,
            &rendererError
        ) else {
            throw rendererError ?? NSError(
                domain: "UtataneNicxlive",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "nijigenerateレンダラーを初期化できなかった"]
            )
        }
        return view
    }

    static func setScale(_ scale: NSSize, on view: NSView?) {
        guard let view else { return }
        UTSetNicxliveViewScale(view, scale.width, scale.height)
    }

    static func setOffset(x: Double, y: Double, on view: NSView?) {
        guard let view else { return }
        UTSetNicxliveViewOffset(view, x, y)
    }

    @discardableResult
    static func setParameter(_ name: String, valueX: Double, valueY: Double = 0, on view: NSView?) -> Bool {
        guard let view else { return false }
        return UTSetNicxliveViewParameter(view, name, valueX, valueY)
    }
}

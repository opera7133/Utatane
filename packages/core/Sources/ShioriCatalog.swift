import Foundation

/// A stable identifier shared by SHIORI detection and support diagnostics.
public struct ShioriIdentifier: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct ShioriDescriptor: Hashable, Codable, Sendable, Identifiable {
    public enum Execution: String, Codable, Sendable {
        case builtIn
        case bundledNativeModule
        case externalProcess
        case dynamicLibrary
        case windowsDLL
    }

    public enum Provisioning: String, Codable, Sendable {
        /// Utatane contains everything needed for this implementation.
        case included
        /// The ghost normally supplies the module or dictionaries.
        case ghost
        /// The user must install and configure a runtime or executable.
        case user
        /// Known to the catalog, but Utatane has no dedicated implementation yet.
        case unavailable
    }

    public enum RuntimeRequirement: String, Codable, Sendable {
        case none
        case configuredExecutable
        case wine
    }

    public enum Support: String, Codable, Sendable {
        case supported
        case experimental
        case compatibilityLayer
        case knownUnavailable
    }

    public let id: ShioriIdentifier
    public let displayName: String
    public let aliases: [String]
    public let moduleFilenames: [String]
    public let execution: Execution
    public let provisioning: Provisioning
    public let runtimeRequirement: RuntimeRequirement
    public let support: Support

    public init(
        id: ShioriIdentifier,
        displayName: String,
        aliases: [String] = [],
        moduleFilenames: [String] = [],
        execution: Execution,
        provisioning: Provisioning,
        runtimeRequirement: RuntimeRequirement = .none,
        support: Support = .supported
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.moduleFilenames = moduleFilenames
        self.execution = execution
        self.provisioning = provisioning
        self.runtimeRequirement = runtimeRequirement
        self.support = support
    }
}

public enum ShioriCatalog {
    public static let descriptors: [ShioriDescriptor] = [
        .init(id: "ai-native", displayName: "Utatane AI", execution: .builtIn, provisioning: .included),
        .init(
            id: "shiolink",
            displayName: "SHIOLINK",
            aliases: ["ShiolinkJS"],
            moduleFilenames: ["shiolink.dll"],
            execution: .externalProcess,
            provisioning: .ghost,
            runtimeRequirement: .configuredExecutable
        ),
        .init(id: "yaya", displayName: "YAYA", aliases: ["AYA", "文"], moduleFilenames: ["yaya.dll", "aya.dll", "aya5.dll"], execution: .builtIn, provisioning: .included),
        .init(id: "satori", displayName: "里々", aliases: ["SATORI"], moduleFilenames: ["satori.dll"], execution: .builtIn, provisioning: .included),
        .init(id: "kawari", displayName: "華和梨", aliases: ["KAWARI"], moduleFilenames: ["kawari.dll"], execution: .builtIn, provisioning: .included),
        .init(id: "kagari", displayName: "kagari", moduleFilenames: ["kagari.dll"], execution: .bundledNativeModule, provisioning: .included),
        .init(id: "aosora", displayName: "蒼空", aliases: ["Aosora"], moduleFilenames: ["aosora.dll"], execution: .bundledNativeModule, provisioning: .user, support: .experimental),
        .init(id: "first", displayName: "FIRST", moduleFilenames: ["first.dll"], execution: .builtIn, provisioning: .included),
        .init(id: "misaka", displayName: "美坂", aliases: ["MISAKA"], moduleFilenames: ["misaka.dll"], execution: .builtIn, provisioning: .included),
        .init(id: "akari", displayName: "灯", aliases: ["AKARI"], moduleFilenames: ["akari.dll"], execution: .builtIn, provisioning: .included),
        .init(
            id: "ese-shiori",
            displayName: "ese-shiori",
            aliases: ["似非shiori"],
            moduleFilenames: ["ese-shiori.dll"],
            execution: .builtIn,
            provisioning: .included
        ),
        .init(
            id: "nise-shiori",
            displayName: "偽栞",
            aliases: ["Nise Shiori"],
            moduleFilenames: ["niseshiori.dll"],
            execution: .windowsDLL,
            provisioning: .ghost,
            runtimeRequirement: .wine,
            support: .compatibilityLayer
        ),
        .init(
            id: "external-posix-shiori",
            displayName: "外部macOS SHIORI",
            execution: .dynamicLibrary,
            provisioning: .ghost
        ),
        .init(
            id: "external-windows-shiori",
            displayName: "外部Windows SHIORI",
            execution: .windowsDLL,
            provisioning: .ghost,
            runtimeRequirement: .wine,
            support: .compatibilityLayer
        )
    ]

    public static func descriptor(id: ShioriIdentifier) -> ShioriDescriptor? {
        descriptors.first { $0.id == id }
    }

    public static func descriptor(moduleFilename: String?) -> ShioriDescriptor? {
        guard let filename = moduleFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filename.isEmpty
        else { return nil }
        return descriptors.first { descriptor in
            descriptor.moduleFilenames.contains { $0.caseInsensitiveCompare(filename) == .orderedSame }
        }
    }

    /// Identifies dictionary based engines before falling back to the declared module name.
    /// The order mirrors Utatane's runtime selection order where formats overlap.
    public static func identify(masterDirectory: URL, declaredModuleFilename: String? = nil) -> ShioriDescriptor? {
        let exists: (String) -> Bool = { filename in
            FileManager.default.fileExists(atPath: masterDirectory.appending(path: filename).path)
        }
        let detectedID: ShioriIdentifier? = if exists("ai.json") {
            "ai-native"
        } else if exists("yaya.txt") || exists("yaya_config.txt") || exists("aya5.txt") || exists("aya.txt") {
            "yaya"
        } else if exists("satori_conf.txt") {
            "satori"
        } else if exists("kawarirc.kis") || exists("kawari.ini") {
            "kawari"
        } else if exists("misaka.ini") {
            "misaka"
        } else if exists("main.amb") || exists("main.azr") || exists("akari.ini") {
            "akari"
        } else if exists("eseai.ini") {
            "ese-shiori"
        } else {
            nil
        }
        if let detected = detectedID.flatMap(descriptor(id:)) ?? descriptor(moduleFilename: declaredModuleFilename) {
            return detected
        }
        switch declaredModuleFilename.flatMap({ URL(filePath: $0).pathExtension.lowercased() }) {
        case "dylib", "so", "bundle":
            return descriptor(id: "external-posix-shiori")
        case "dll":
            return descriptor(id: "external-windows-shiori")
        default:
            return nil
        }
    }
}

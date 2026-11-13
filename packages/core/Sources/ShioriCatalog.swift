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
        .init(
            id: "rishu",
            displayName: "里珠",
            aliases: ["Rishu"],
            moduleFilenames: ["rishu_proxy.dll"],
            execution: .externalProcess,
            provisioning: .ghost,
            support: .experimental
        ),
        .init(id: "yaya", displayName: "YAYA", aliases: ["AYA", "文"], moduleFilenames: ["yaya.dll", "aya.dll", "aya5.dll", "libyaya.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "yaya-6", displayName: "YAYA 6", moduleFilenames: ["yaya-6.dll", "libyaya-6.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "satori", displayName: "里々", aliases: ["SATORI"], moduleFilenames: ["satori.dll", "libsatori.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "kawari", displayName: "華和梨", aliases: ["KAWARI"], moduleFilenames: ["kawari.dll", "libkawari.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "kagari", displayName: "kagari", moduleFilenames: ["kagari.dll", "libkagari.dylib", "libkagari.so"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "minato", displayName: "minato", aliases: ["湊"], moduleFilenames: ["minato.dll", "libminato.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "pasta", displayName: "pasta", aliases: [], moduleFilenames: ["pasta.dll", "libpasta.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "hitomi", displayName: "ひとみ。", aliases: ["Hitomi"], moduleFilenames: ["hitomi.dll", "libhitomi.dylib"], execution: .dynamicLibrary, provisioning: .user, support: .experimental),
        .init(id: "konoka", displayName: "此栞", aliases: ["Konoka", "このか"], moduleFilenames: ["konoka.dll", "libkonoka.dylib"], execution: .dynamicLibrary, provisioning: .user, support: .experimental),
        .init(id: "mae", displayName: "真絵", aliases: ["MAE"], moduleFilenames: ["mae.dll", "libmae.dylib"], execution: .dynamicLibrary, provisioning: .user, support: .experimental),
        .init(id: "dnproxy", displayName: "D.N.Proxy", moduleFilenames: ["dnproxy.dll", "dnproxy_debug.dll", "libdnproxy.dylib"], execution: .dynamicLibrary, provisioning: .user, runtimeRequirement: .configuredExecutable, support: .experimental),
        .init(id: "aosora", displayName: "蒼空", aliases: ["Aosora"], moduleFilenames: ["aosora.dll", "libaosora.dylib", "libaosora.so"], execution: .bundledNativeModule, provisioning: .user, support: .experimental),
        .init(id: "first", displayName: "FIRST", moduleFilenames: ["first.dll"], execution: .builtIn, provisioning: .included),
        .init(id: "misaka", displayName: "美坂", aliases: ["MISAKA"], moduleFilenames: ["misaka.dll", "libmisaka.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "akari", displayName: "灯", aliases: ["AKARI"], moduleFilenames: ["akari.dll", "libakari.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(
            id: "ese-shiori",
            displayName: "ese-shiori",
            aliases: ["似非shiori"],
            moduleFilenames: ["ese-shiori.dll", "libese-shiori.dylib"],
            execution: .dynamicLibrary,
            provisioning: .user
        ),
        .init(
            id: "nise-shiori",
            displayName: "偽栞",
            aliases: ["Nise Shiori"],
            moduleFilenames: ["niseshiori.dll", "libniseshiori.dylib"],
            execution: .dynamicLibrary,
            provisioning: .user
        ),
        .init(id: "shino", displayName: "忍", aliases: ["Shino"], moduleFilenames: ["shino.dll", "libshino.dylib"], execution: .dynamicLibrary, provisioning: .user),
        .init(id: "hisui", displayName: "翡翠", aliases: ["Hisui"], moduleFilenames: ["hisui.dll", "libhisui.dylib"], execution: .dynamicLibrary, provisioning: .user, support: .experimental),
        .init(
            id: "yuhna",
            displayName: "結奈",
            aliases: ["YUHNA"],
            moduleFilenames: ["yuhna.dll", "libyuhna.dylib"],
            execution: .dynamicLibrary,
            provisioning: .user,
            support: .experimental
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
        let basename = filename.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? filename
        return descriptors.first { descriptor in
            descriptor.moduleFilenames.contains { $0.caseInsensitiveCompare(basename) == .orderedSame }
        }
    }

    /// Uses an explicit engine name when recognized and dictionary signatures for generic DLL names.
    public static func identify(
        masterDirectory: URL,
        declaredModuleFilename: String? = nil,
        macOSModuleFilename: String? = nil
    ) -> ShioriDescriptor? {
        if let filename = macOSModuleFilename {
            let url = URL(filePath: filename.replacingOccurrences(of: "\\", with: "/"))
            switch url.pathExtension.lowercased() {
            case "dylib", "so", "bundle":
                return descriptor(moduleFilename: filename) ?? descriptor(id: "external-posix-shiori")
            case "dll" where url.lastPathComponent.lowercased() == "shiolink.dll":
                return descriptor(moduleFilename: "shiolink.dll")
            default:
                return nil
            }
        }
        let exists: (String) -> Bool = { filename in
            FileManager.default.fileExists(atPath: masterDirectory.appending(path: filename).path)
        }
        let declared = descriptor(moduleFilename: declaredModuleFilename)
        let detectedID: ShioriIdentifier? = if let declared {
            declared.id
        } else if exists("ai.json") {
            "ai-native"
        } else if exists("yaya.txt") || exists("yaya_config.txt") || exists("aya5.txt") || exists("aya.txt") {
            "yaya"
        } else if exists("satori_conf.txt") {
            "satori"
        } else if exists("konoka.ini") || exists("ks_cfg.txt") || hasKonokaEncryptedConfig(masterDirectory, module: declaredModuleFilename) {
            "konoka"
        } else if exists("hitomi.ini") {
            "hitomi"
        } else if exists("kawarirc.kis") || exists("kawari.ini") {
            "kawari"
        } else if exists("mae_corpus.txt") {
            "mae"
        } else if exists("dnproxy.ini") || exists("dnproxy.dll.config") {
            "dnproxy"
        } else if exists("ghost.asproj") {
            "aosora"
        } else if exists("misaka.ini") {
            "misaka"
        } else if exists("main.amb") || exists("main.azr") || exists("akari.ini") {
            "akari"
        } else if hasYuhnaDictionary(in: masterDirectory) {
            "yuhna"
        } else if exists("hisuiconf.xml") {
            "hisui"
        } else if exists("pasta.toml") {
            "pasta"
        } else if exists("config.toml"), exists("talks/main.mnt") {
            "minato"
        } else if exists("eseai.ini") {
            "ese-shiori"
        } else {
            nil
        }
        if let detected = detectedID.flatMap(descriptor(id:)) {
            return detected
        }
        if NativeShioriLibraryLocator.firstExisting(in: NativeShioriLibraryLocator.candidates(
            moduleID: nil, masterDirectory: masterDirectory, declaredFilename: declaredModuleFilename
        )) != nil {
            return descriptor(id: "external-posix-shiori")
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

    private static func hasYuhnaDictionary(in directory: URL) -> Bool {
        let url = directory.appending(path: "dic.ydf")
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let file = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? file.close() }
        return (try? file.read(upToCount: 8)) == Data("YDF/1.07".utf8)
    }

    private static func hasKonokaEncryptedConfig(_ directory: URL, module: String?) -> Bool {
        guard let module,
              let declared = NativeShioriLibraryLocator.declaredURL(module, in: directory) else { return false }
        let config = declared.deletingPathExtension().appendingPathExtension("ini")
        guard let size = try? config.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65536, let data = try? Data(contentsOf: config),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { return false }
        return text.components(separatedBy: .newlines).contains { line in
            let fields = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = fields.first, !name.hasPrefix("#"), !name.hasPrefix("//"),
                  let file = NativeShioriLibraryLocator.declaredURL(name, in: directory) else { return false }
            return ["xdc", "xdi"].contains { ext in
                let encrypted = file.deletingPathExtension().appendingPathExtension(ext)
                return FileManager.default.fileExists(atPath: encrypted.path)
            }
        }
    }
}

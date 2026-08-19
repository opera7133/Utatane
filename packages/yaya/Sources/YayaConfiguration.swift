import Foundation

public enum YayaTextEncoding: Equatable, Sendable {
    case utf8
    case shiftJIS
    case eucJP

    public init?(name: String) {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "UTF-8", "UTF8": self = .utf8
        case "SHIFT_JIS", "SHIFT-JIS", "SJIS", "CP932": self = .shiftJIS
        case "EUC-JP", "EUCJP": self = .eucJP
        default: return nil
        }
    }

    var foundationEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .shiftJIS: .shiftJIS
        case .eucJP: .japaneseEUC
        }
    }
}

public struct YayaDictionarySource: Equatable, Sendable {
    public let url: URL
    public let encoding: YayaTextEncoding
    public let isOptional: Bool

    public init(url: URL, encoding: YayaTextEncoding, isOptional: Bool) {
        self.url = url
        self.encoding = encoding
        self.isOptional = isOptional
    }
}

public struct YayaDiagnostic: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        case warning
        case error
    }

    public let severity: Severity
    public let url: URL
    public let line: Int?
    public let message: String

    public init(severity: Severity, url: URL, line: Int?, message: String) {
        self.severity = severity
        self.url = url
        self.line = line
        self.message = message
    }
}

public struct YayaConfiguration: Equatable, Sendable {
    public let rootDirectory: URL
    public let dictionaries: [YayaDictionarySource]
    public let includedConfigurationURLs: [URL]
    public let settings: [String: [String]]
    public let diagnostics: [YayaDiagnostic]

    public init(
        rootDirectory: URL,
        dictionaries: [YayaDictionarySource],
        includedConfigurationURLs: [URL],
        settings: [String: [String]],
        diagnostics: [YayaDiagnostic]
    ) {
        self.rootDirectory = rootDirectory
        self.dictionaries = dictionaries
        self.includedConfigurationURLs = includedConfigurationURLs
        self.settings = settings
        self.diagnostics = diagnostics
    }
}

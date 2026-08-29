import Foundation
import UtataneCore
import UtataneSakuraScript

public struct ParticleMakotoTranslator: SakuraScriptTranslator {
    public init() {}

    public static func supports(masterDirectoryURL: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: masterDirectoryURL,
            includingPropertiesForKeys: nil
        ),
            entries.contains(where: { $0.lastPathComponent.lowercased() == "makoto.dll" }),
            let configurationURL = entries.first(where: { $0.lastPathComponent.lowercased() == "makoto.ini" }),
            let data = try? Data(contentsOf: configurationURL),
            let configuration = LegacyTextDecoder.decode(data)
        else { return false }
        return configuration.range(
            of: #"(?im)^\s*\[ParticleMakoto\]\s*$"#,
            options: .regularExpression
        ) != nil
    }

    public func translate(_ script: SakuraScript) -> SakuraScript {
        SakuraScript(rawValue: translate(script.rawValue))
    }

    public func translate(_ source: String) -> String {
        var result = ""
        var remainder = source[...]
        while !remainder.isEmpty {
            guard let match = Self.firstMarker(in: remainder) else {
                result += remainder
                break
            }
            result += remainder[..<match.range.lowerBound]
            let hasFinalConsonant = Self.hasFinalConsonant(in: result)
            result += match.replacement(hasFinalConsonant)
            remainder = remainder[match.range.upperBound...]
        }
        return result
    }

    private struct Marker {
        let range: Range<String.Index>
        let replacement: @Sendable (Bool) -> String
    }

    private static let markers: [(String, @Sendable (Bool) -> String)] = [
        ("[은]/는", { $0 ? "은" : "는" }),
        ("[을]/를", { $0 ? "을" : "를" }),
        ("[이]/가", { $0 ? "이" : "가" }),
        ("[와]/과", { $0 ? "과" : "와" }),
        ("[으]로", { $0 ? "으로" : "로" }),
        ("[이]", { $0 ? "이" : "" })
    ]

    private static func firstMarker(in source: Substring) -> Marker? {
        markers.compactMap { marker, replacement in
            source.range(of: marker).map { Marker(range: $0, replacement: replacement) }
        }.min {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.range.upperBound > $1.range.upperBound
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }
    }

    private static func hasFinalConsonant(in source: String) -> Bool {
        guard let scalar = source.unicodeScalars.last(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return false
        }
        switch scalar.value {
        case 0xAC00 ... 0xD7AF:
            return (scalar.value - 0xAC00) % 28 != 0
        case 0x30 ... 0x39:
            return "013678".unicodeScalars.contains(scalar)
        case 0x41 ... 0x5A, 0x61 ... 0x7A:
            return "bcklmnpqx".unicodeScalars.contains(UnicodeScalar(scalar.value | 0x20)!)
        default:
            return false
        }
    }
}

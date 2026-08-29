import CoreFoundation
import Foundation

public enum LegacyTextDecoder {
    public static func decode(_ data: Data, preferredCharset: String? = nil) -> String? {
        let declaredCharset = preferredCharset ?? charsetDeclaration(in: data)
        let encodings = candidateEncodings(preferredCharset: declaredCharset)
        let wholeFileEncodings: [String.Encoding] = if declaredCharset == nil {
            [.utf8] + encodings
        } else {
            Array(encodings.prefix(1))
        }
        for encoding in wholeFileEncodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        // Some older ghosts mix encodings between lines despite declaring one charset.
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        var decodedLines: [String] = []
        decodedLines.reserveCapacity(lines.count)
        let lineEncodings = declaredCharset == nil ? [.utf8] + encodings : encodings
        for line in lines {
            guard let text = lineEncodings.lazy.compactMap({
                String(data: Data(line), encoding: $0)
            }).first else { return nil }
            decodedLines.append(text)
        }
        return decodedLines.joined(separator: "\n")
    }

    public static func encode(_ text: String, charset: String) -> Data? {
        guard let encoding = encoding(named: charset) else { return nil }
        return text.data(using: encoding)
    }

    public static func encoding(named charset: String) -> String.Encoding? {
        let normalized = charset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(normalized as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static func charsetDeclaration(in data: Data) -> String? {
        guard let bytePreservingText = String(data: data.prefix(4096), encoding: .isoLatin1) else {
            return nil
        }
        for line in bytePreservingText.components(separatedBy: .newlines) {
            let fields = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if fields.count == 2, fields[0].caseInsensitiveCompare("charset") == .orderedSame {
                return fields[1]
            }
        }
        return nil
    }

    private static func candidateEncodings(preferredCharset: String?) -> [String.Encoding] {
        let names = [preferredCharset, "Shift_JIS", "EUC-KR", "EUC-JP", "GB18030", "Big5"]
        var seen = Set<UInt>()
        return names.compactMap { name in
            guard let name, let encoding = encoding(named: name), seen.insert(encoding.rawValue).inserted else {
                return nil
            }
            return encoding
        }
    }
}

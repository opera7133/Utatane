import CoreFoundation
import Foundation
import UtataneLegacyTextCodec

public enum LegacyTextDecoder {
    public static func decode(_ data: Data, preferredCharset: String? = nil) -> String? {
        let declaredCharset = preferredCharset ?? charsetDeclaration(in: data)
        let encodings = candidateEncodings(preferredCharset: declaredCharset)
        let wholeFileEncodings: [EncodingCandidate] = if declaredCharset == nil {
            [EncodingCandidate(name: "UTF-8", encoding: .utf8)] + encodings
        } else {
            Array(encodings.prefix(1))
        }
        for candidate in wholeFileEncodings {
            if let text = decode(data, candidate: candidate) {
                return text
            }
        }

        // Some older ghosts mix encodings between lines despite declaring one charset.
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        var decodedLines: [String] = []
        decodedLines.reserveCapacity(lines.count)
        let lineEncodings = declaredCharset == nil
            ? [EncodingCandidate(name: "UTF-8", encoding: .utf8)] + encodings
            : encodings
        for line in lines {
            guard let text = lineEncodings.lazy.compactMap({ decode(Data(line), candidate: $0) }).first else {
                return nil
            }
            decodedLines.append(text)
        }
        return decodedLines.joined(separator: "\n")
    }

    public static func encode(_ text: String, charset: String) -> Data? {
        guard let encoding = encoding(named: charset) else { return nil }
        if let data = text.data(using: encoding) {
            return data
        }
        return transcode(Data(text.utf8), from: "UTF-8", to: charset)
    }

    public static func encoding(named charset: String) -> String.Encoding? {
        let normalized = charset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let charsetName = normalized.withCString({
            CFStringCreateWithCString(nil, $0, CFStringBuiltInEncodings.UTF8.rawValue)
        }) else { return nil }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charsetName)
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

    private struct EncodingCandidate {
        let name: String
        let encoding: String.Encoding
    }

    private static func candidateEncodings(preferredCharset: String?) -> [EncodingCandidate] {
        let names = [preferredCharset, "Shift_JIS", "EUC-KR", "EUC-JP", "GB18030", "Big5"]
        var seen = Set<UInt>()
        return names.compactMap { name in
            guard let name, let encoding = encoding(named: name), seen.insert(encoding.rawValue).inserted else {
                return nil
            }
            return EncodingCandidate(name: name, encoding: encoding)
        }
    }

    private static func decode(_ data: Data, candidate: EncodingCandidate) -> String? {
        if let text = String(data: data, encoding: candidate.encoding) {
            return text
        }
        guard let utf8 = transcode(data, from: candidate.name, to: "UTF-8") else { return nil }
        return String(data: utf8, encoding: .utf8)
    }

    private static func transcode(_ data: Data, from source: String, to destination: String) -> Data? {
        let capacity = max(64, data.count * 4 + 16)
        var output = Data(count: capacity)
        let written = data.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                source.withCString { sourceName in
                    destination.withCString { destinationName in
                        utatane_transcode(
                            sourceName,
                            destinationName,
                            inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                            inputBuffer.count,
                            outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                            outputBuffer.count
                        )
                    }
                }
            }
        }
        guard written >= 0, written <= capacity else { return nil }
        output.count = written
        return output
    }
}

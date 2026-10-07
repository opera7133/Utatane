import Foundation

public struct MailHeaderSummary: Sendable, Equatable {
    public let sender: String
    public let subject: String
}

public enum MailHeaderParser {
    public static func parse(lines: [String]) -> MailHeaderSummary {
        var fields: [String] = []
        for line in lines {
            if line.isEmpty {
                break
            }
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !fields.isEmpty {
                fields[fields.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                fields.append(line)
            }
        }
        func value(_ name: String) -> String {
            guard let line = fields.first(where: { $0.lowercased().hasPrefix(name + ":") }),
                  let separator = line.firstIndex(of: ":") else { return "" }
            return decodeWords(String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
        }
        return MailHeaderSummary(sender: value("from"), subject: value("subject"))
    }

    public static func decodeWords(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?]*)\?="#) else { return text }
        let source = text as NSString
        var output = ""
        var previousEnd = 0
        var previousWasEncoded = false
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let charset = source.substring(with: match.range(at: 1)).lowercased()
            let encoding = source.substring(with: match.range(at: 2)).lowercased()
            let payload = source.substring(with: match.range(at: 3))
            let data = encoding == "b" ? Data(base64Encoded: payload) : decodeQ(payload)
            let stringEncoding: String.Encoding? = switch charset {
            case "utf-8", "utf8": .utf8
            case "us-ascii", "ascii": .ascii
            case "iso-8859-1": .isoLatin1
            case "windows-1252": .windowsCP1252
            case "shift_jis", "shift-jis", "sjis", "windows-31j", "cp932": .shiftJIS
            case "iso-2022-jp": .iso2022JP
            default: nil
            }
            let decoded = data.flatMap { data in stringEncoding.flatMap { String(data: data, encoding: $0) } }
            let gap = source.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
            if !(previousWasEncoded && decoded != nil && gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                output += gap
            }
            output += decoded ?? source.substring(with: match.range)
            previousWasEncoded = decoded != nil
            previousEnd = NSMaxRange(match.range)
        }
        output += source.substring(from: previousEnd)
        return output
    }

    private static func decodeQ(_ text: String) -> Data? {
        let bytes = Array(text.utf8)
        var output = Data()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 61 {
                guard index + 2 < bytes.count,
                      let value = UInt8(String(decoding: bytes[(index + 1) ... (index + 2)], as: UTF8.self), radix: 16) else { return nil }
                output.append(value)
                index += 3
            } else {
                output.append(bytes[index] == 95 ? 32 : bytes[index])
                index += 1
            }
        }
        return output
    }
}

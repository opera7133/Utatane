import Foundation

/// Conventional httpc options. Keep the synchronous module and owning host in
/// agreement; these are the small original tag conversions, not an HTML DOM.
struct HttpcTextOptions: Sendable {
    var charset: String?
    private var erase = false
    private var translate = false

    init(arguments: inout [String]) {
        let encodings = ["euc": "EUC-JP", "jis": "ISO-2022-JP", "sjis": "CP932", "utf8": "UTF-8", "utf-8": "UTF-8", "utf-16be": "UTF-16BE", "utf-16le": "UTF-16LE"]
        while let first = arguments.first?.lowercased() {
            if let encoding = encodings[first] {
                charset = encoding
            } else if first == "erase_tag" {
                erase = true
            } else if first == "translate_tag" {
                translate = true
            } else {
                break
            }
            arguments.removeFirst()
        }
    }

    func process(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\0", with: "")
        guard erase || translate else { return clean }
        var output = "", index = clean.startIndex
        while index < clean.endIndex {
            if clean[index] == "<" {
                let start = clean.index(after: index)
                let end = clean[start...].firstIndex(of: ">") ?? clean.endIndex
                if translate {
                    output += Self.tag(String(clean[start ..< end]))
                }
                index = end == clean.endIndex ? end : clean.index(after: end)
            } else {
                output.append(clean[index]); index = clean.index(after: index)
            }
        }
        guard translate else { return output }
        for (from, to) in [("&nbsp;", ""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "\\&"), ("&copy;", "(c)")] {
            output = output.replacingOccurrences(of: from, with: to)
        }
        // Collapse adjacent SakuraScript newlines in one pass.
        var normalized = "", cursor = output.startIndex, lastNewline = false
        while cursor < output.endIndex {
            let next = output.index(after: cursor)
            if output[cursor] == "\\", next < output.endIndex, output[next] == "n" {
                if !lastNewline {
                    normalized += "\\n"
                }
                lastNewline = true; cursor = output.index(after: next)
            } else {
                normalized.append(output[cursor]); lastNewline = false; cursor = next
            }
        }
        // Original httpc truncates at 120 rows, counting 48 half-width columns
        // per row. Unicode scalars preserve its supplementary-character width.
        let scalars = Array(normalized.unicodeScalars)
        var position = 0, column = 0, row = 1
        while position < scalars.count, row < 120 {
            if scalars[position] == "\\", position + 1 < scalars.count, scalars[position + 1] == "n" {
                column = 0; row += 1; position += 2
            } else {
                column += Self.width(scalars[position].value); position += 1
                if column >= 48 {
                    column = 0; row += 1
                }
            }
        }
        return String(String.UnicodeScalarView(scalars.prefix(position)))
    }

    private static func width(_ value: UInt32) -> Int {
        if value < 0x80 {
            return 1
        }
        if value <= 0x24F {
            return [0xA7, 0xA8, 0xB0, 0xB1, 0xB4, 0xB6, 0xD7, 0xF7].contains(value) ? 2 : 1
        }
        return (0xFF61 ... 0xFF9F).contains(value) || (0xFFE8 ... 0xFFEE).contains(value) ? 1 : 2
    }

    private static func tag(_ source: String) -> String {
        let characters = Array(source)
        var index = 0
        func whitespace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }
        func word() -> String {
            whitespace()
            var value = ""
            if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                let quote = characters[index]; index += 1
                while index < characters.count, characters[index] != quote {
                    value.append(characters[index]); index += 1
                }
                if index < characters.count {
                    index += 1
                }
            } else {
                while index < characters.count, !characters[index].isWhitespace, characters[index] != "=" {
                    value.append(characters[index]); index += 1
                }
            }
            whitespace(); return value
        }
        let name = word().lowercased()
        var properties: [String: String] = [:]
        while index < characters.count {
            let before = index, key = word().lowercased()
            if index < characters.count, characters[index] == "=" {
                index += 1; properties[key] = word()
            }
            if index == before {
                index += 1
            }
        }
        switch name {
        case "/tr", "/li", "br", "p", "br/": return "\\n"
        case "hr", "hr/": return "\\n-----------------------------------------------\\n"
        case "a": return properties["href"].map { "\\_a[" + $0 + "]" } ?? ""
        case "/a": return "\\_a"
        case "img": return properties["alt"].flatMap { $0.isEmpty ? nil : "〔" + $0 + "〕" } ?? ""
        default: return ""
        }
    }
}

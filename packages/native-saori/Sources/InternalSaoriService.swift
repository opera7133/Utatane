import CryptoKit
import Foundation
import Security
import UtataneCore

/// Baseware functions shared by isolated SHIORI sessions. This is a private host
/// callback, not a TCP/HTTP or Windows WM_COPYDATA endpoint.
public struct InternalSaoriService: Sendable {
    public static let maximumBytes = 8 * 1024 * 1024
    private static let functions = [
        "internal_system": ["ListModules", "ListFunctions"],
        "internal_text": ["Normalize"],
        "internal_time": ["Format", "Add", "Diff"],
        "internal_random": ["Bytes", "Number", "UUID"],
        "internal_data": ["Convert"],
        "internal_crypto": ["Digest", "HMAC"]
    ]

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public static func moduleName(_ path: String) -> String? {
        var name = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        if name.hasSuffix(".dll") {
            name.removeLast(4)
        }
        guard name.hasPrefix("internal_"), name.utf8.allSatisfy({ (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 95 }) else { return nil }
        return name
    }

    public func response(to data: Data, validatesOnly: Bool = false) -> Data {
        var charset = "UTF-8"
        do {
            guard data.count <= Self.maximumBytes, !data.contains(0), data.suffix(4) == Data([13, 10, 13, 10]),
                  let bytes = String(data: data, encoding: .isoLatin1) else { throw Failure("invalid parameter") }
            let declarations = bytes.components(separatedBy: "\r\n").filter { $0.lowercased().hasPrefix("charset:") }
            guard declarations.count == 1, let declared = declarations.first?.split(separator: ":", maxSplits: 1).last else { throw Failure("invalid parameter") }
            switch declared.trimmingCharacters(in: .whitespaces).lowercased() {
            case "utf-8", "utf8": charset = "UTF-8"
            case "shift_jis", "shift-jis", "cp932", "windows-31j": charset = "Shift_JIS"
            default: throw Failure("invalid encoding")
            }
            let wire: String? = if charset == "UTF-8" {
                String(data: data, encoding: .utf8)
            } else {
                LegacyTextDecoder.decode(data, strictlyUsing: "CP932")
            }
            guard let wire else { throw Failure("invalid encoding") }
            var lines = wire.components(separatedBy: "\r\n")
            let method = lines.removeFirst()
            guard ["GET Version SAORI/1.0", "EXECUTE SAORI/1.0"].contains(method) else { throw Failure("invalid parameter") }
            var headers: [String: String] = [:]
            for line in lines {
                if line.isEmpty {
                    break
                }
                guard let colon = line.firstIndex(of: ":") else { throw Failure("invalid parameter") }
                let key = line[..<colon].lowercased()
                guard headers[key] == nil else { throw Failure("invalid parameter") }
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard !value.contains("\n"), !value.contains("\r") else { throw Failure("invalid parameter") }
                headers[key] = value
            }
            guard let rawModule = headers["module"], let module = Self.moduleName(rawModule) else { throw Failure("invalid parameter") }
            guard let available = Self.functions[module] else { throw Failure("unknown module") }
            if method.hasPrefix("GET Version") {
                return encode(status: 200, result: "Utatane Internal", charset: charset)
            }
            var arguments: [Int: String] = [:]
            for (key, value) in headers where key.hasPrefix("argument") {
                guard let index = Int(key.dropFirst(8)), index >= 0, index < 256,
                      String(index) == key.dropFirst(8) else { throw Failure("invalid parameter") }
                arguments[index] = value
            }
            guard let last = arguments.keys.max(), arguments.count == last + 1 else { throw Failure("invalid parameter") }
            let values = (0 ... last).map { arguments[$0]! }
            guard let function = available.first(where: { $0.caseInsensitiveCompare(values[0]) == .orderedSame }) else { throw Failure("unknown function") }
            let result = try execute(module: module, function: function, arguments: Array(values.dropFirst()), validatesOnly: validatesOnly)
            return encode(status: result.0.isEmpty ? 204 : 200, result: result.0, values: result.1, charset: charset)
        } catch let failure as InternalSaoriTime.Failure {
            return encode(status: 400, error: failure.message, charset: charset)
        } catch let failure as Failure {
            return encode(status: failure.status, error: failure.message, charset: charset)
        } catch { return encode(status: 500, error: "internal error", charset: charset) }
    }

    private struct Failure: Error {
        let message: String
        let status: Int
        init(_ message: String, status: Int = 400) {
            self.message = message; self.status = status
        }
    }

    private func encode(status: Int, result: String? = nil, values: [String] = [], error: String? = nil, charset: String) -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 500: "Internal Server Error"][status] ?? "Bad Request"
        var lines = ["SAORI/1.0 \(status) \(reason)", "Charset: \(charset)"]
        func safe(_ text: String) -> Bool {
            !text.contains("\r") && !text.contains("\n") && !text.contains("\0")
        }
        guard result.map(safe) ?? true, values.allSatisfy(safe) else { return encode(status: 400, error: "not text", charset: charset) }
        if let result {
            lines.append("Result: \(result)")
        }
        lines += values.enumerated().map { "Value\($0.offset): \($0.element)" }
        if let error {
            lines.append("ErrorDescription: \(error)")
        }
        guard let data = LegacyTextDecoder.encode(lines.joined(separator: "\r\n") + "\r\n\r\n", charset: charset) else {
            return Data("SAORI/1.0 400 Bad Request\r\nCharset: UTF-8\r\nErrorDescription: invalid encoding\r\n\r\n".utf8)
        }
        guard data.count <= Self.maximumBytes else { return encode(status: 400, error: "too large", charset: charset) }
        return data
    }

    static func positionalCount(module: String, function: String) -> Int? {
        guard let function = functions[module]?.first(where: { $0.caseInsensitiveCompare(function) == .orderedSame }) else { return nil }
        switch (module, function) {
        case ("internal_system", "ListModules"), ("internal_random", "UUID"): return 0
        case ("internal_system", "ListFunctions"), ("internal_random", "Bytes"), ("internal_data", _): return 1
        case ("internal_time", "Format"), ("internal_text", _), ("internal_random", "Number"), ("internal_crypto", "Digest"): return 2
        default: return 3
        }
    }

    private func execute(module: String, function: String, arguments: [String], validatesOnly: Bool) throws -> (String, [String]) {
        let count: Int
        let allowed: Set<String>
        switch (module, function) {
        case ("internal_system", "ListModules"): count = 0; allowed = []
        case ("internal_system", "ListFunctions"): count = 1; allowed = []
        case ("internal_time", "Format"): count = 2; allowed = ["tz"]
        case ("internal_time", _): count = 3; allowed = ["tz"]
        case ("internal_text", _): count = 2; allowed = []
        case ("internal_random", "Bytes"): count = 1; allowed = ["out"]
        case ("internal_random", "Number"): count = 2; allowed = []
        case ("internal_random", "UUID"): count = 0; allowed = ["version"]
        case ("internal_data", _): count = 1; allowed = ["in", "data-in", "out"]
        case ("internal_crypto", "Digest"): count = 2; allowed = ["data-in", "out"]
        default: count = 3; allowed = ["key-in", "data-in", "out"]
        }
        var arguments = arguments
        if module == "internal_time", function == "Format", arguments.count == 1 {
            arguments.append("")
        }
        guard arguments.count >= count else { throw Failure("invalid parameter") }
        let positional = Array(arguments.prefix(count))
        var options: [String: String] = [:]
        for value in arguments.dropFirst(count) {
            guard value.hasPrefix("--"), let separator = value.firstIndex(of: "=") else { throw Failure("invalid parameter") }
            let key = String(value[value.index(value.startIndex, offsetBy: 2) ..< separator]).lowercased()
            guard allowed.contains(key), options[key] == nil else { throw Failure("invalid parameter") }
            options[key] = String(value[value.index(after: separator)...])
        }
        if validatesOnly {
            return ("", [])
        }
        switch module {
        case "internal_time":
            return try (InternalSaoriTime.execute(function, arguments: arguments, now: now()), [])
        case "internal_system":
            let list: [String]
            if function == "ListModules" {
                list = Self.functions.keys.sorted()
            } else {
                guard let functions = Self.functions[positional[0].lowercased()] else { throw Failure("unknown module") }
                list = functions
            }
            return (list.joined(separator: ","), list)
        case "internal_text":
            let text = positional[1]
            let result: String
            switch positional[0].uppercased() {
            case "NFC": result = text.precomposedStringWithCanonicalMapping
            case "NFD": result = text.decomposedStringWithCanonicalMapping
            case "NFKC": result = text.precomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping
            case "NFKD": result = text.decomposedStringWithCompatibilityMapping
            default: throw Failure("unsupported algorithm")
            }
            return (result, [])
        case "internal_random":
            if function == "Number" {
                guard let minimum = Int64(positional[0]), let maximum = Int64(positional[1]), minimum <= maximum else { throw Failure("invalid parameter") }
                return (String(Int64.random(in: minimum ... maximum)), [])
            }
            if function == "UUID" {
                let version = options["version"] ?? "4"
                guard ["4", "7"].contains(version) else { throw Failure("unsupported algorithm") }
                var bytes = try randomBytes(16)
                if version == "7" {
                    let time = UInt64(Date().timeIntervalSince1970 * 1000)
                    for index in 0 ..< 6 {
                        bytes[index] = UInt8(truncatingIfNeeded: time >> ((5 - index) * 8))
                    }
                }
                bytes[6] = (bytes[6] & 15) | (version == "7" ? 0x70 : 0x40)
                bytes[8] = (bytes[8] & 63) | 0x80
                let text = bytes.map { String(format: "%02x", $0) }
                return ([text[0 ..< 4].joined(), text[4 ..< 6].joined(), text[6 ..< 8].joined(), text[8 ..< 10].joined(), text[10 ..< 16].joined()].joined(separator: "-"), [])
            }
            guard let size = Int(positional[0]), (1 ... 1024).contains(size) else { throw Failure("out of range") }
            return try (format(Data(randomBytes(size)), as: options["out"] ?? "hex"), [])
        case "internal_data":
            return try (format(decode(positional[0], as: options["data-in"] ?? options["in"] ?? "text"), as: options["out"] ?? "text"), [])
        default:
            let algorithm = positional[0].lowercased()
            let data = try decode(positional[function == "Digest" ? 1 : 2], as: options["data-in"] ?? "text")
            let key = function == "HMAC" ? try decode(positional[1], as: options["key-in"] ?? "text") : Data()
            let digest: Data
            switch (function, algorithm) {
            case ("Digest", "md5"): digest = Data(Insecure.MD5.hash(data: data))
            case ("Digest", "sha1"): digest = Data(Insecure.SHA1.hash(data: data))
            case ("Digest", "sha256"): digest = Data(SHA256.hash(data: data))
            case ("Digest", "sha384"): digest = Data(SHA384.hash(data: data))
            case ("Digest", "sha512"): digest = Data(SHA512.hash(data: data))
            case ("HMAC", "sha256"): digest = Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case ("HMAC", "sha384"): digest = Data(HMAC<SHA384>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            case ("HMAC", "sha512"): digest = Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key)))
            default: throw Failure("unsupported algorithm")
            }
            return try (format(digest, as: options["out"] ?? "hex"), [])
        }
    }

    private func randomBytes(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw Failure("internal error", status: 500) }
        return bytes
    }

    private func decode(_ text: String, as encoding: String) throws -> Data {
        guard text.utf8.count <= Self.maximumBytes else { throw Failure("too large") }
        switch encoding.lowercased() {
        case "text": return Data(text.utf8)
        case "hex":
            let bytes = Array(text.utf8)
            guard bytes.count % 2 == 0, bytes.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) }) else { throw Failure("invalid encoding") }
            return Data(stride(from: 0, to: bytes.count, by: 2).map { UInt8(String(decoding: bytes[$0 ..< $0 + 2], as: UTF8.self), radix: 16)! })
        case "base64", "base64url":
            var source = text
            if encoding.lowercased() == "base64url" {
                source = source.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                source += String(repeating: "=", count: (4 - source.count % 4) % 4)
            }
            guard let data = Data(base64Encoded: source) else { throw Failure("invalid encoding") }
            return data
        default: throw Failure("unsupported algorithm")
        }
    }

    private func format(_ data: Data, as encoding: String) throws -> String {
        switch encoding.lowercased() {
        case "text":
            guard let text = String(data: data, encoding: .utf8) else { throw Failure("not text") }
            return text
        case "hex": return data.map { String(format: "%02x", $0) }.joined()
        case "base64": return data.base64EncodedString()
        case "base64url": return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        default: throw Failure("unsupported algorithm")
        }
    }
}

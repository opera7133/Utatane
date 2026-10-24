import Foundation
import UtataneCore
import UtataneSakuraScript

public struct PreparedSakuraScriptHTTPRequest: @unchecked Sendable {
    public let request: URLRequest
    public let bodyFileURL: URL?
}

/// One implementation for the main and called ghosts. File bodies remain on
/// disk; the transfer delegate can reopen them if URLSession requests a replay.
public enum SakuraScriptHTTPRequestBuilder {
    public static func prepare(_ command: SakuraScriptHTTPRequest, masterDirectory: URL,
                               allowedRoots: [URL] = [], boundary: String = "Utatane-" + UUID().uuidString) throws -> PreparedSakuraScriptHTTPRequest
    {
        guard let url = URL(string: command.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = command.method
        request.timeoutInterval = min(max(command.timeoutSeconds ?? 60, 0.1), 300)
        for header in command.headers {
            guard let colon = header.firstIndex(of: ":") else { throw invalid() }
            let name = header[..<colon].trimmingCharacters(in: .whitespaces)
            let value = header[header.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.utf8.allSatisfy({ (33 ... 126).contains($0) && !"()<>@,;:\\\"/[]?={} \t".utf8.contains($0) }),
                  !value.utf8.contains(13), !value.utf8.contains(10), !value.utf8.contains(0) else { throw invalid() }
            request.setValue(value, forHTTPHeaderField: name)
        }
        func option(_ name: String) -> String? {
            command.options.last { $0.lowercased().hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
        }
        let charset = option("param-charset") ?? "UTF-8"
        guard LegacyTextDecoder.encoding(named: charset) != nil else { throw invalid() }
        func encode(_ text: String) throws -> Data {
            guard let data = LegacyTextDecoder.encode(text, charset: charset) else { throw invalid() }
            return data
        }
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? "application/x-www-form-urlencoded"
        let multipart = contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() == "multipart/form-data"
        if let input = option("param-input-file") {
            guard command.parameters.isEmpty, !input.isEmpty, !input.utf8.contains(0) else { throw invalid() }
            let normalized = input.replacingOccurrences(of: "\\", with: "/")
            let file = (normalized.hasPrefix("/") ? URL(filePath: normalized) : masterDirectory.appending(path: normalized))
                .resolvingSymlinksInPath().standardizedFileURL
            let roots = [masterDirectory] + allowedRoots
            guard roots.contains(where: {
                let root = $0.resolvingSymlinksInPath().standardizedFileURL.path
                return file.path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }) else { throw CocoaError(.fileReadNoPermission) }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let count = values.fileSize, let stream = InputStream(url: file) else { throw invalid() }
            request.httpBodyStream = stream
            request.setValue(String(count), forHTTPHeaderField: "Content-Length")
            if multipart {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                let prefix = try handle.read(upToCount: 256) ?? Data()
                guard let end = prefix.firstIndex(of: 10),
                      let first = String(data: prefix[..<end], encoding: .ascii) else { throw invalid() }
                let line = first.hasSuffix("\r") ? String(first.dropLast()) : first
                guard line.hasPrefix("--") else { throw invalid() }
                let actual = String(line.dropFirst(2))
                try validateBoundary(actual)
                if let specified = boundaryParameter(contentType), specified != actual {
                    throw invalid()
                }
                request.setValue(multipartType(contentType, boundary: actual), forHTTPHeaderField: "Content-Type")
            } else {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            return .init(request: request, bodyFileURL: file)
        }
        guard !command.parameters.isEmpty else { return .init(request: request, bodyFileURL: nil) }
        if command.method == "GET" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let query = try percentEncodedQuery(encode(command.parameters.joined(separator: "&")))
            components.percentEncodedQuery = [components.percentEncodedQuery, query].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: "&")
            guard let target = components.url else { throw URLError(.badURL) }
            request.url = target
        } else if multipart {
            try validateBoundary(boundary)
            var body = Data()
            for parameter in command.parameters {
                guard let separator = parameter.firstIndex(of: "=") else { throw invalid() }
                let name = String(parameter[..<separator])
                guard !name.utf8.contains(13), !name.utf8.contains(10), !name.utf8.contains(0) else { throw invalid() }
                let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let value = try encode(String(parameter[parameter.index(after: separator)...]))
                guard value.range(of: Data(("--" + boundary).utf8)) == nil else { throw invalid() }
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(escaped)\"\r\n\r\n".utf8))
                body.append(value)
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            request.httpBody = body
            request.setValue(multipartType(contentType, boundary: boundary), forHTTPHeaderField: "Content-Type")
        } else {
            let form = contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/x-www-form-urlencoded"
            let separator = form && command.parameters.allSatisfy { $0.contains("=") } ? "&" : "\r\n"
            request.httpBody = try encode(command.parameters.joined(separator: separator))
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return .init(request: request, bodyFileURL: nil)
    }

    public static func destination(_ command: SakuraScriptHTTPRequest, masterDirectory: URL, invocationID: UUID) -> URL? {
        guard case let .file(requested) = command.output else { return nil }
        let fallback = URL(string: command.url)?.lastPathComponent ?? ""
        let basename = URL(fileURLWithPath: requested ?? (fallback.isEmpty ? "index.html" : fallback)).lastPathComponent
        let name = requested == nil ? "http-\(invocationID.uuidString)-\(basename)" : basename
        return masterDirectory.appending(path: "var", directoryHint: .isDirectory).appending(path: name)
    }

    private static func invalid() -> CocoaError {
        CocoaError(.fileReadCorruptFile)
    }

    private static func validateBoundary(_ value: String) throws {
        guard (1 ... 70).contains(value.utf8.count), value.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) || "'()+_,-./:=? ".utf8.contains($0) }), !value.hasSuffix(" ") else { throw invalid() }
    }

    private static func boundaryParameter(_ type: String) -> String? {
        for parameter in type.split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0].lowercased() == "boundary" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    private static func multipartType(_ type: String, boundary: String) -> String {
        let parts = type.split(separator: ";").filter {
            $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased() != "boundary"
        }
        return parts.joined(separator: ";") + "; boundary=\"\(boundary)\""
    }

    private static func percentEncodedQuery(_ bytes: Data) -> String {
        let bytes = Array(bytes)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?".utf8)
        let hex = Set("0123456789abcdefABCDEF".utf8)
        var output = "", index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 37, index + 2 < bytes.count, hex.contains(bytes[index + 1]), hex.contains(bytes[index + 2]) {
                output += String(decoding: bytes[index ... index + 2], as: UTF8.self); index += 3
            } else if allowed.contains(byte) {
                output.append(Character(UnicodeScalar(byte))); index += 1
            } else {
                output += String(format: "%%%02X", byte); index += 1
            }
        }
        return output
    }
}

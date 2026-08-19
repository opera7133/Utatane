import Foundation

public enum ShioriParseError: Error, Equatable, Sendable {
    case emptyMessage
    case invalidRequestLine(String)
    case invalidResponseLine(String)
    case invalidStatusCode(String)
    case invalidHeader(String)
}

public enum ShioriMessageParser {
    public static func parseRequest(_ message: String) throws -> ShioriRequest {
        var lines = messageLines(message)
        guard let startLine = lines.first, !startLine.isEmpty else {
            throw ShioriParseError.emptyMessage
        }
        lines.removeFirst()

        let parts = startLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2 else {
            throw ShioriParseError.invalidRequestLine(startLine)
        }

        return try ShioriRequest(
            method: String(parts[0]),
            version: String(parts[1]),
            headers: parseHeaders(lines)
        )
    }

    public static func parseResponse(_ message: String) throws -> ShioriResponse {
        var lines = messageLines(message)
        guard let startLine = lines.first, !startLine.isEmpty else {
            throw ShioriParseError.emptyMessage
        }
        lines.removeFirst()

        let parts = startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            throw ShioriParseError.invalidResponseLine(startLine)
        }
        guard let statusCode = Int(parts[1]) else {
            throw ShioriParseError.invalidStatusCode(String(parts[1]))
        }

        return try ShioriResponse(
            version: String(parts[0]),
            statusCode: statusCode,
            reasonPhrase: parts.count == 3 ? String(parts[2]) : "",
            headers: parseHeaders(lines)
        )
    }

    private static func messageLines(_ message: String) -> [String] {
        message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func parseHeaders(_ lines: [String]) throws -> ShioriHeaders {
        var headers = ShioriHeaders()
        for line in lines {
            guard !line.isEmpty else { break }
            guard let separator = line.firstIndex(of: ":") else {
                throw ShioriParseError.invalidHeader(line)
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separator)
            let value = line[valueStart...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                throw ShioriParseError.invalidHeader(line)
            }
            headers.append(name: name, value: value)
        }
        return headers
    }
}

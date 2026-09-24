import Foundation
import UtataneCore
import UtatanePlatformMacOS
import UtataneSakuraScript

enum SakuraScriptHTTPEventSupport {
    static func progressEvent(
        command: SakuraScriptHTTPRequest,
        data: Data,
        response: HTTPURLResponse,
        masterDirectory: URL
    ) -> GhostEvent? {
        guard let eventID = command.eventID else { return nil }
        return .shiori(
            id: eventID.hasPrefix("On")
                ? "\(eventID)Progress"
                : (command.isCalendar ? "OnExecuteICalProgress" : "OnExecuteHTTPProgress"),
            references: resultReferences(
                command: command,
                data: data,
                response: response,
                masterDirectory: masterDirectory,
                resultCode: String(response.statusCode)
            )
        )
    }

    static func streamingEvent(
        command: SakuraScriptHTTPRequest,
        value: String,
        response: HTTPURLResponse,
        masterDirectory: URL
    ) -> GhostEvent? {
        guard let eventID = command.eventID else { return nil }
        var references = resultReferences(
            command: command,
            data: Data(),
            response: response,
            masterDirectory: masterDirectory,
            resultCode: value.replacingOccurrences(of: "\n", with: "\u{1}")
        )
        references[4] = value.replacingOccurrences(of: "\n", with: "\u{1}")
        return .shiori(
            id: eventID.hasPrefix("On") ? "\(eventID)Streaming" : "OnExecuteHTTPStreaming",
            references: references
        )
    }

    static func tlsEvent(
        command: SakuraScriptHTTPRequest,
        response: HTTPURLResponse,
        info: HTTPTransferTLSInfo
    ) -> GhostEvent? {
        guard let eventID = command.eventID else { return nil }
        return .notification(
            id: command.isFeed
                ? "OnExecuteRSS_SSLInfo"
                : (command.isCalendar ? "OnExecuteICal_SSLInfo" : "OnExecuteHTTPSSLInfo"),
            references: [
                0: eventID,
                1: command.url,
                2: String(response.statusCode),
                3: info.protocolVersion,
                4: info.cipherSuite,
                5: info.subject,
                6: "",
                7: "",
                8: info.issuer,
                9: info.chainCommonNames.joined(separator: ",")
            ]
        )
    }

    private static func resultReferences(
        command: SakuraScriptHTTPRequest,
        data: Data,
        response: HTTPURLResponse,
        masterDirectory: URL,
        resultCode: String
    ) -> [Int: String] {
        [
            0: command.method.lowercased(),
            1: command.eventID ?? "",
            2: command.url,
            3: outputValue(command: command, data: data, masterDirectory: masterDirectory),
            4: resultCode,
            5: response.value(forHTTPHeaderField: "Set-Cookie") ?? "",
            6: response.allHeaderFields.map { "\($0.key): \($0.value)" }
                .sorted().joined(separator: "\u{1}")
        ]
    }

    private static func outputValue(
        command: SakuraScriptHTTPRequest,
        data: Data,
        masterDirectory: URL
    ) -> String {
        switch command.output {
        case let .file(requestedName):
            let fallback = URL(string: command.url)?.lastPathComponent ?? "index.html"
            let filename = URL(fileURLWithPath: requestedName ?? (fallback.isEmpty ? "index.html" : fallback))
                .lastPathComponent
            return masterDirectory.appending(path: "var/\(filename)").path
        case let .memory(characterEncoding):
            let encoding: String.Encoding = switch characterEncoding?.lowercased() {
            case "shift_jis", "shift-jis", "sjis": .shiftJIS
            case "euc_jp", "euc-jp": .japaneseEUC
            case "utf_16", "utf-16": .unicode
            default: .utf8
            }
            return (String(data: data.prefix(128 * 1024), encoding: encoding) ?? "")
                .replacingOccurrences(of: "\r\n", with: "\u{1}")
                .replacingOccurrences(of: "\r", with: "\u{1}")
                .replacingOccurrences(of: "\n", with: "\u{1}")
        }
    }
}

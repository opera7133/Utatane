import Foundation

public enum Shiori2Compatibility {
    /// Converts a SHIORI/3 event request to the SHIORI/2.6 event form used by old engines.
    public static func eventRequest(from request: ShioriRequest) -> ShioriRequest? {
        guard request.method.caseInsensitiveCompare("GET") == .orderedSame,
              let id = request.id
        else { return nil }

        var headers = ShioriHeaders()
        for header in request.headers.entries
            where header.name.caseInsensitiveCompare("ID") != .orderedSame
            && !(header.name.lowercased().hasPrefix("reference") && header.value.isEmpty)
        {
            headers.append(name: header.name, value: header.value)
        }
        let legacyEvent = id.caseInsensitiveCompare("OnAITalk") == .orderedSame
            ? "OnRandomTalk"
            : id
        headers.append(name: "Event", value: legacyEvent)
        return ShioriRequest(method: "GET Sentence", version: "SHIORI/2.6", headers: headers)
    }

    public static func shouldRetry(_ response: ShioriResponse) -> Bool {
        response.statusCode == 400 && response.version.uppercased().hasPrefix("SHIORI/2.")
    }
}

import Foundation

/// Calling conventions shared by dispatch, async argument separation and Describe.
/// Candidates are canonical names; aliases accepted by implementations need not
/// be advertised. Wire/data encodings and time format names are not candidates.
enum InternalSaoriCatalog {
    struct Function: Sendable {
        let name: String
        let maximum: Int
        let required: Int
        let variable: Bool
        let options: [String]
        let candidates: [String]

        init(_ name: String, _ maximum: Int, required: Int? = nil, variable: Bool = false,
             options: [String] = [], candidates: [String] = [])
        {
            self.name = name; self.maximum = maximum
            self.required = required ?? maximum; self.variable = variable
            self.options = options; self.candidates = candidates
        }

        func positionalCount(arguments: [String]) -> Int {
            // Variadic keys start after the first (file path) argument; a --
            // token ends that list even when a required key is still missing.
            variable ? min(1, arguments.count) + arguments.dropFirst().prefix(while: { !$0.hasPrefix("--") }).count : maximum
        }

        var descriptionValues: [String] {
            [String(maximum), String(required), variable ? "1" : "0", (options + ["async"]).joined(separator: ",")] + candidates
        }
    }

    static let modules: [String: [Function]] = [
        "internal_system": [Function("ListModules", 0), Function("ListFunctions", 1), Function("Describe", 2)],
        "internal_text": [Function("Normalize", 2, candidates: ["Argument1=NFC|NFD|NFKC|NFKD"])],
        "internal_time": [
            Function("Format", 2, required: 1, options: ["tz"]),
            Function("Add", 3, options: ["tz"], candidates: ["Argument3=second|minute|hour|day|week|month|year"]),
            Function("Diff", 3, options: ["tz"], candidates: ["Argument3=second|minute|hour|day|week|month|year"])
        ],
        "internal_random": [
            Function("Bytes", 1, options: ["out"]), Function("Number", 2),
            Function("UUID", 0, options: ["version"], candidates: ["--version=4|7"])
        ],
        "internal_data": [
            Function("Convert", 1, options: ["data-in", "in", "out", "charset", "hrp"]),
            Function("Compress", 2, options: ["data-in", "in", "out", "charset", "level"], candidates: ["Argument1=gzip|zlib|deflate"]),
            Function("Decompress", 2, options: ["data-in", "in", "out", "charset"], candidates: ["Argument1=gzip|zlib|deflate"])
        ],
        "internal_crypto": [
            Function("Digest", 2, options: ["data-in", "out", "charset"], candidates: ["Argument1=md5|sha1|sha256|sha384|sha512|crc32|adler32"]),
            Function("HMAC", 3, options: ["key-in", "data-in", "out", "charset"], candidates: ["Argument1=sha256|sha384|sha512"]),
            Function("Compare", 2, options: ["a-in", "b-in", "charset"])
        ],
        "internal_file": [
            Function("MediaInfo", 12, required: 2, variable: true),
            Function("ImageInfo", 12, required: 2, variable: true),
            Function("IsImageLoadable", 1), Function("IsMediaLoadable", 1)
        ]
    ]

    static func function(module: String, name: String) -> Function? {
        modules[module.lowercased()]?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

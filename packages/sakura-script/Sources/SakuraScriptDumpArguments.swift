import Foundation

private struct DumpArguments {
    let positional: [String]
    let options: [String: String]

    init(_ arguments: [String]) {
        positional = arguments.filter { !$0.hasPrefix("--") }
        options = arguments.filter { $0.hasPrefix("--") }.reduce(into: [:]) { result, argument in
            guard let equal = argument.firstIndex(of: "=") else { return }
            result[String(argument[..<equal]).lowercased()] = String(argument[argument.index(after: equal)...])
        }
    }

    func value(_ name: String, position: Int) -> String? {
        let value = options["--" + name] ?? (positional.indices.contains(position) ? positional[position] : nil)
        return value?.isEmpty == false ? value : nil
    }
}

public extension SakuraScriptDumpSurfaceCommand {
    init(arguments: [String]) {
        let values = DumpArguments(arguments)
        self.init(
            directoryPath: values.value("dir", position: 0),
            scope: values.value("scope", position: 1).flatMap(Int.init) ?? 0,
            surfaceList: values.value("surface", position: 2),
            prefix: values.value("prefix", position: 3) ?? "surface",
            eventID: values.options["--event"] ?? values.options["--async"] ?? values.value("event", position: 4),
            cropsFromZero: ["1", "true", "yes"].contains(values.value("fromzero", position: 5)?.lowercased() ?? ""),
            animationID: values.value("animation", position: 6)
        )
    }
}

public struct SakuraScriptDumpBalloonCommand: Sendable, Equatable {
    public let directoryPath: String?
    public let scope: Int
    public let prefix: String
    public let eventID: String?
    public let hiddenItems: Set<String>

    public init(arguments: [String]) {
        let values = DumpArguments(arguments)
        directoryPath = values.value("dir", position: 0)
        scope = values.value("scope", position: 1).flatMap(Int.init) ?? 0
        prefix = values.value("prefix", position: 2) ?? "balloon"
        eventID = values.options["--event"] ?? values.options["--async"] ?? values.value("event", position: 3)
        hiddenItems = Set((values.options["--hide"] ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }
}

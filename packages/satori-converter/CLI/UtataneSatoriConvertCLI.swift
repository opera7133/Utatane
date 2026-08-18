import Foundation
import UtataneSatoriConverter

@main
enum UtataneSatoriConvertCLI {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("使い方: utatane-satori-convert <ghost/master> <output.json>\n".utf8)
            )
            Foundation.exit(64)
        }

        let masterDirectory = URL(filePath: arguments[0], directoryHint: .isDirectory)
        let outputURL = URL(filePath: arguments[1], directoryHint: .notDirectory)
        let result = try SatoriDictionaryConverter().convert(masterDirectory: masterDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result.catalog)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        print("\(result.sourceFileCount) files / \(result.convertedEntryCount) converted / \(result.skippedEntryCount) skipped")
        print(outputURL.path)
    }
}

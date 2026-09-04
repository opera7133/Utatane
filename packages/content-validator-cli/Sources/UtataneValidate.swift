import Foundation
import UtataneContentValidator

@main
struct UtataneValidate {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let outputsJSON = arguments.firstIndex(of: "--json").map { index in
            arguments.remove(at: index)
            return true
        } ?? false
        guard arguments.count == 1, !arguments[0].hasPrefix("-") else {
            FileHandle.standardError.write(Data("使い方: utatane-validate [--json] <ghost-directory>\n".utf8))
            exit(64)
        }

        let report = ContentValidator().validate(ghostRoot: URL(filePath: arguments[0], directoryHint: .isDirectory))
        if outputsJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(report) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } else {
            print("\(report.ghostName ?? "ゴーストを読み込めなかった") — errors: \(report.errorCount), warnings: \(report.warningCount)")
            if let shiori = report.shiori {
                print("SHIORI: \(shiori)")
            }
            for item in report.diagnostics {
                let location = item.line.map { "\(item.path):\($0)" } ?? item.path
                print("\(item.severity.rawValue): \(location): [\(item.code)] \(item.message)")
            }
        }
        exit(report.errorCount == 0 ? 0 : 1)
    }
}

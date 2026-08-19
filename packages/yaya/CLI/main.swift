import Foundation
import UtataneYaya

var positionalArguments: [String] = []
var entryPoints: [String] = []
var index = 1
while index < CommandLine.arguments.count {
    if CommandLine.arguments[index] == "--entry", index + 1 < CommandLine.arguments.count {
        entryPoints.append(CommandLine.arguments[index + 1])
        index += 2
    } else {
        positionalArguments.append(CommandLine.arguments[index])
        index += 1
    }
}

guard positionalArguments.count == 1 || positionalArguments.count == 2 else {
    FileHandle.standardError.write(Data(
        "Usage: utatane-yaya-audit <master-directory> [settings-file] [--entry function]\n".utf8
    ))
    exit(2)
}

let masterDirectory = URL(fileURLWithPath: positionalArguments[0], isDirectory: true)
let settingsFileName = positionalArguments.count == 2 ? positionalArguments[1] : "yaya.txt"

do {
    let configuration = try YayaConfigurationLoader().load(
        masterDirectory: masterDirectory,
        settingsFileName: settingsFileName
    )
    let report = YayaCompatibilityAuditor().audit(configuration: configuration)
    for issue in report.issues {
        let location = [issue.line, issue.column]
            .compactMap { $0.map(String.init) }
            .joined(separator: ":")
        let suffix = location.isEmpty ? "" : ":\(location)"
        print("\(issue.sourceURL.path)\(suffix): \(issue.message)")
    }
    print("Parsed \(report.parsedDictionaryCount)/\(report.dictionaryCount) dictionaries; \(report.issues.count) issues")
    if !report.runtime.unsupportedFunctions.isEmpty {
        print(
            "Unsupported runtime functions: \(report.runtime.unsupportedFunctions.count) names, " +
                "\(report.runtime.unsupportedFunctionCallCount) calls"
        )
        for function in report.runtime.unsupportedFunctions {
            let first = function.locations[0]
            let additional = function.referenceCount > 1 ? " (+\(function.referenceCount - 1) more)" : ""
            print(
                "  \(function.name): \(first.sourceURL.lastPathComponent):" +
                    "\(first.line):\(first.column) in \(first.functionName)\(additional)"
            )
        }
    } else {
        print(
            "Runtime calls: \(report.runtime.functionCallCount); " +
                "all statically named functions are available"
        )
    }
    if !entryPoints.isEmpty {
        let program = try YayaProgramLoader().load(configuration: configuration)
        let saveFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("utatane-yaya-audit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: saveFileURL) }
        let environment = YayaNativeRuntimeEnvironment(
            rootDirectory: configuration.rootDirectory,
            saveFileURL: saveFileURL,
            settings: configuration.settings.compactMapValues { $0.last }.mapValues(YayaValue.string)
        )
        var evaluator = YayaEvaluator(
            program: program,
            globals: ["reference": .array(Array(repeating: .void, count: 8))],
            environment: environment
        )
        for entryPoint in entryPoints {
            let arguments: [YayaValue] = entryPoint == "load" ? [.string(masterDirectory.path)] : []
            let value = try evaluator.call(entryPoint, arguments: arguments)
            print("Entry \(entryPoint): \(String(reflecting: value))")
        }
    }
    if !report.issues.isEmpty || (entryPoints.isEmpty && !report.runtime.unsupportedFunctions.isEmpty) {
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("YAYA audit failed: \(error)\n".utf8))
    exit(1)
}

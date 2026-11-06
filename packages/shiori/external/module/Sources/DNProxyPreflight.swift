import Darwin
import Foundation

public struct DNProxyDiagnostic: LocalizedError, Sendable {
    public enum Status: String, Sendable {
        case ready, missingModule, missingHost, invalidConfiguration, unsupportedConfiguration
        case missingDotnet, dotnetFailed, missingRuntime, missingSDK, sdkSelectionFailed
    }

    public let status: Status
    public let dotnetURL: URL?
    public let architecture: String?
    public let sdkVersion: String?
    public let requiresSDK: Bool
    public let detail: String

    public var summary: String {
        switch status {
        case .ready: "DNProxy: 実行準備OK（起動成功の保証ではない）"
        case .missingModule: "DNProxy: モジュール未導入"
        case .missingHost: "DNProxy: モジュールのbinが不足"
        case .invalidConfiguration: "DNProxy: 設定を読み取れない"
        case .unsupportedConfiguration: "DNProxy: 非対応の設定"
        case .missingDotnet: "DNProxy: dotnetが見つからない"
        case .dotnetFailed: "DNProxy: 選択したdotnetを実行できない"
        case .missingRuntime: "DNProxy: .NET 10ランタイムが不足"
        case .missingSDK: "DNProxy: .NET 10に対応したSDKが不足"
        case .sdkSelectionFailed: "DNProxy: .NET 10対応SDKを選択できない"
        }
    }

    public var report: String {
        [summary, "dotnet: \(dotnetURL?.path ?? "(not selected)")", "dotnet CPU: \(architecture ?? "(not checked)")",
         "SDK selected: \(sdkVersion ?? "(not checked / not required)")",
         "SDK required: \(requiresSDK ? "yes (dnproxy.ini)" : "no (precompiled assembly)")", detail,
         "修正・導入後は「再診断」を押し、ゴーストを再読み込みしてください。", "https://dotnet.microsoft.com/download/dotnet/10.0"].joined(separator: "\n")
    }

    public var errorDescription: String? {
        report
    }
}

/// Reads configuration and queries the selected dotnet. Never compiles or loads ghost code.
public struct DNProxyPreflight: Sendable {
    typealias Runner = @Sendable (URL, [String], [String: String]) throws -> String
    private let environment: [String: String]
    private let runner: Runner

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(environment: environment, runner: Self.run)
    }

    init(environment: [String: String], runner: @escaping Runner) {
        self.environment = environment
        self.runner = runner
    }

    public func inspect(directoryURL: URL, moduleURL: URL?) -> DNProxyDiagnostic {
        let manager = FileManager.default
        let needsSDK = manager.fileExists(atPath: directoryURL.appending(path: "dnproxy.ini").path)
        var selected: URL?
        var architecture: String?
        var sdkVersion: String?
        func result(_ status: DNProxyDiagnostic.Status, _ detail: String) -> DNProxyDiagnostic {
            .init(status: status, dotnetURL: selected, architecture: architecture, sdkVersion: sdkVersion, requiresSDK: needsSDK, detail: detail)
        }
        guard let moduleURL, Self.isFile(moduleURL), moduleURL.pathExtension.lowercased() != "dll" else {
            return result(.missingModule, "モジュールカタログからD.N.Proxyを導入してください。")
        }
        let host = environment["UTATANE_DNPROXY_HOST"].map { URL(fileURLWithPath: $0) }
            ?? moduleURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "bin/DnProxyHost.dll")
        if let override = environment["UTATANE_DNPROXY_HOST"], !override.hasPrefix("/") || override.contains("\0") {
            return result(.missingHost, "UTATANE_DNPROXY_HOSTにはホストDLLの絶対パスを指定してください。")
        }
        let hostFiles = [host, host.deletingPathExtension().appendingPathExtension("runtimeconfig.json"),
                         host.deletingPathExtension().appendingPathExtension("deps.json"),
                         host.deletingLastPathComponent().appending(path: "Ukagaka.NET.Interfaces.dll")]
        guard hostFiles.allSatisfy(Self.isFile) else {
            return result(.missingHost, "dylibだけでなく同じModulesパッケージのbin/も保持してください。不足: " + hostFiles.filter { !Self.isFile($0) }.map(\.path).joined(separator: ", "))
        }
        do { try Self.validateConfiguration(directoryURL, requiresSDK: needsSDK) }
        catch let failure as ConfigurationFailure {
            return result(failure.unsupported ? .unsupportedConfiguration : .invalidConfiguration, failure.message)
        } catch { return result(.invalidConfiguration, error.localizedDescription) }
        let candidates: [String]
        if let explicit = environment["UTATANE_DOTNET"] {
            if explicit.hasPrefix("/"), !explicit.contains("\0") {
                selected = URL(fileURLWithPath: explicit)
            }
            candidates = [explicit] // An explicit choice must not silently fall back to another installation.
        } else {
            candidates = ["/usr/local/share/dotnet/dotnet", "/opt/homebrew/bin/dotnet"]
                + (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/dotnet" }
        }
        guard let path = candidates.first(where: { $0.hasPrefix("/") && !$0.contains("\0") && manager.isExecutableFile(atPath: $0) }) else {
            return result(.missingDotnet, "macOS用.NET 10を導入するか、UTATANE_DOTNETにdotnetの実行可能な絶対パスを指定してください。")
        }
        selected = URL(fileURLWithPath: path)
        do {
            let info = try runner(selected!, ["--info"], environment)
            let hostInfo = info.components(separatedBy: "Host:").last ?? ""
            architecture = hostInfo.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Architecture:") })?
                .components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            guard architecture == "arm64" || architecture == "x64" else {
                return result(.dotnetFailed, "dotnet --infoでmacOS用CPUを確認できません。アプリと別CPUのdotnetも、実行可能なら利用できます。")
            }
            let runtimes = try runner(selected!, ["--list-runtimes"], environment)
            guard runtimes.components(separatedBy: .newlines).contains(where: {
                let parts = $0.split(whereSeparator: \.isWhitespace)
                return parts.count >= 2 && parts[0] == "Microsoft.NETCore.App" && Self.isVersion10(String(parts[1]))
            }) else {
                return result(.missingRuntime, "選択したdotnetのCPU向け.NET 10ランタイムを導入してください。他のCPU・別のdotnetに入れたランタイムは判定に使いません。")
            }
            if needsSDK {
                let sdks = try runner(selected!, ["--list-sdks"], environment)
                guard sdks.components(separatedBy: .newlines).contains(where: { Self.isCompatibleSDK(String($0.split(whereSeparator: \.isWhitespace).first ?? "")) }) else {
                    return result(.missingSDK, "dnproxy.iniがあるため.NET 10 SDKが必要です。コンパイル済みDLLだけならSDKは不要です。SDKにはランタイムも含まれます。")
                }
                do {
                    // Build creates its scratch project under the same temporary directory.
                    // global.json may select an older/missing SDK despite --list-sdks reporting a suitable one.
                    let activeSDK = try runner(selected!, ["--version"], environment).trimmingCharacters(in: .whitespacesAndNewlines)
                    sdkVersion = activeSDK
                    guard Self.isCompatibleSDK(activeSDK) else {
                        return result(.sdkSelectionFailed, "dotnetが選択したSDK: \(activeSDK)。global.json等のSDK選択を.NET 10対応の安定版へ変更してください。")
                    }
                } catch {
                    return result(.sdkSelectionFailed, "SDKはインストールされていますが選択に失敗しました。global.json等を確認してください。\(error.localizedDescription)")
                }
            }
            return result(.ready, "このdotnetを起動時にも使用します。設定検査とランタイムの照会のみ完了。C#のコンパイル、型の解決、ユーザーコードのloadは起動時に別途確認します。")
        } catch { return result(.dotnetFailed, "CPU不一致・起動失敗・時間切れ等を確認してください。\(error.localizedDescription)") }
    }

    private static func isFile(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
    }

    private static func isVersion10(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "10" && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func isCompatibleSDK(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { Int($0) != nil } && (Int(parts[0]) ?? 0) >= 10
    }

    private struct ConfigurationFailure: Error {
        let message: String
        var unsupported = false
    }

    private static func read(_ url: URL) throws -> String {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else {
            throw ConfigurationFailure(message: "設定は通常のファイルにしてください: \(url.lastPathComponent)")
        }
        let data = try handle.read(upToCount: 256 * 1024 + 1) ?? Data()
        guard data.count <= 256 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw ConfigurationFailure(message: "設定は256KiB以内のUTF-8にしてください: \(url.lastPathComponent)")
        }
        return text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
    }

    private static func validateConfiguration(_ directory: URL, requiresSDK: Bool) throws {
        let xml = try read(directory.appending(path: "dnproxy.dll.config"))
        guard !xml.localizedCaseInsensitiveContains("<!DOCTYPE") else { throw ConfigurationFailure(message: "DOCTYPEを含む設定は使えません。") }
        let delegate = SettingsParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw ConfigurationFailure(message: "dnproxy.dll.configのXMLを読み取れません。") }
        guard delegate.settings["Protocol"] == "SHIORI/3.0" else { throw ConfigurationFailure(message: "ProtocolはSHIORI/3.0にしてください。", unsupported: true) }
        if requiresSDK {
            let ini = try read(directory.appending(path: "dnproxy.ini"))
            var values: [String: [String]] = [:]
            var key: String?
            for original in ini.components(separatedBy: .newlines) {
                var line = original.components(separatedBy: "//")[0].trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                if let colon = line.firstIndex(of: ":") {
                    key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                    line = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                if let key, !line.isEmpty {
                    values[key, default: []].append(line)
                }
            }
            let supported: Set = ["language", "sourcefiles", "mainclass", "outputassembly", "referencedassemblies", "generateexecutable"]
            if let unknown = values.keys.sorted().first(where: { !supported.contains($0) }) {
                throw ConfigurationFailure(message: "非対応のdnproxy.ini設定: \(unknown)", unsupported: true)
            }
            if !["C#", "CSharp", "csharp"].contains(values["language"]?.last ?? "C#") || (values["generateexecutable"]?.last ?? "0") != "0" {
                throw ConfigurationFailure(message: "Portable C#のライブラリ出力のみ対応しています。VB/JScriptや実行ファイル出力は使えません。", unsupported: true)
            }
            guard values["sourcefiles"]?.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) == true else {
                throw ConfigurationFailure(message: "dnproxy.iniにSourceFilesを指定してください。")
            }
        } else {
            let name = delegate.settings["AssemblyName"] ?? "user.dll"
            let path = name.replacingOccurrences(of: "\\", with: "/")
            let assembly = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appending(path: path)
            guard isFile(assembly) else { throw ConfigurationFailure(message: "コンパイル済みDLLが見つかりません: \(assembly.path)") }
        }
    }

    private final class SettingsParser: NSObject, XMLParserDelegate {
        var settings: [String: String] = [:]
        var key: String?
        var value = ""
        var inValue = false
        func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes: [String: String]) {
            if name == "setting" {
                key = attributes["name"]
            }
            if name == "value" {
                value = ""; inValue = true
            }
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            if inValue {
                value += string
            }
        }

        func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
            if name == "value" {
                if let key, settings[key] == nil {
                    settings[key] = value
                }
                inValue = false
            }
            if name == "setting" {
                key = nil
            }
        }
    }

    private struct CommandFailure: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    /// Nonblocking output reads prevent full pipes or inherited handles from hanging diagnosis.
    static func run(_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws -> String {
        let process = Process(), output = Pipe(), exited = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = environment.merging(["DOTNET_CLI_UI_LANGUAGE": "en", "DOTNET_NOLOGO": "1", "DOTNET_CLI_TELEMETRY_OPTOUT": "1"]) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        try output.fileHandleForWriting.close()
        let fd = output.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else { throw CocoaError(.fileReadUnknown) }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0, errno == EINTR {
                continue
            }
            guard ready >= 0 else { throw CocoaError(.fileReadUnknown) }
            if ready > 0 {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0 {
                    data.append(contentsOf: buffer.prefix(count))
                    guard data.count <= 64 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                } else if count == 0 {
                    let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                    guard exited.wait(timeout: .now() + remaining) == .success else { throw NativeShioriProcessError.timeout }
                    guard process.terminationStatus == 0 else {
                        throw CommandFailure(message: "dotnet \(arguments.joined(separator: " ")): exit \(process.terminationStatus)")
                    }
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw CommandFailure(message: "dotnet returned non-UTF-8 output")
                    }
                    return text
                } else if errno != EAGAIN, errno != EINTR {
                    throw CocoaError(.fileReadUnknown)
                }
            }
        }
        throw NativeShioriProcessError.timeout
    }
}

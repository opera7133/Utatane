import AppKit
import SwiftUI

public struct SHIORIModuleChoice: Identifiable, Sendable {
    public var id: String {
        path
    }

    public let path: String
    public let kind: String
    public init(path: String, kind: String) {
        self.path = path; self.kind = kind
    }
}

public struct SHIORIDiagnosticTarget: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let selectedFilename: String?
    public let macOSOverride: String?
    public let moduleURL: URL?
    public let additionalInspection: (@Sendable () -> String)?
    public let runtimeResult: String
    public let selectionPath: String?
    public let selectionKind: String?
    public let availableModules: [SHIORIModuleChoice]
    public let kindIDs: [String]
    public let moduleRequirementsReport: String

    public init(
        id: String, name: String, selectedFilename: String?, macOSOverride: String?,
        moduleURL: URL?, runtimeResult: String,
        selectionPath: String? = nil, selectionKind: String? = nil,
        availableModules: [SHIORIModuleChoice] = [], kindIDs: [String] = [], moduleRequirementsReport: String = "", additionalInspection: (@Sendable () -> String)? = nil
    ) {
        self.selectionPath = selectionPath
        self.selectionKind = selectionKind
        self.availableModules = availableModules
        self.kindIDs = kindIDs
        self.additionalInspection = additionalInspection
        self.id = id
        self.name = name
        self.selectedFilename = selectedFilename
        self.macOSOverride = macOSOverride
        self.moduleURL = moduleURL
        self.runtimeResult = runtimeResult
        self.moduleRequirementsReport = moduleRequirementsReport
    }
}

public enum SHIORIModuleInspector {
    public static func inspect(_ target: SHIORIDiagnosticTarget) async -> String {
        await Task.detached(priority: .utility) { report(target) }.value
    }

    private static func report(_ target: SHIORIDiagnosticTarget) -> String {
        #if arch(arm64)
            let architecture = "arm64"
        #else
            let architecture = "x86_64"
        #endif
        var lines = [
            "SHIORI: \(target.name)",
            "Ghost: \(target.id)",
            "Selected: \(target.selectedFilename ?? "(none)")",
            "User selection: \(target.selectionPath ?? "(automatic)") [\(target.selectionKind ?? "detect ABI")]",
            "shiori.macos: \(target.macOSOverride ?? "(none; automatic selection)")",
            "App CPU: \(architecture)",
            "Last load / initialization: \(target.runtimeResult)",
            target.moduleRequirementsReport,
            ""
        ]
        if let inspection = target.additionalInspection {
            lines += [inspection(), ""]
        }
        guard let url = target.moduleURL else {
            lines.append("No external module path resolved. Built-in engines / SHIOLINK do not require a generic dylib; configured native modules may be unavailable. See the initialization result above.")
            return lines.joined(separator: "\n")
        }
        lines.append("Module: \(url.path)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            lines.append("ERROR: Module file does not exist.")
            return lines.joined(separator: "\n")
        }
        lines += ["", "File format:", run("/usr/bin/file", [url.path])]
        guard ["dylib", "so", "bundle"].contains(url.pathExtension.lowercased()) else {
            lines.append("Windows DLL execution requires Wine and its DLL host; this is not a macOS dylib.")
            return lines.joined(separator: "\n")
        }
        let architectures = run("/usr/bin/lipo", ["-archs", url.path])
        lines += ["", "Architectures:", architectures]
        if !architectures.split(whereSeparator: \.isWhitespace).contains(Substring(architecture)) {
            lines.append("WARNING: The current app CPU was not found in the architecture list.")
        }
        let symbols = run("/usr/bin/nm", ["-gU", url.path])
        let names = Set(symbols.components(separatedBy: .newlines).compactMap { $0.split(whereSeparator: \.isWhitespace).last.map(String.init) })
        lines += ["", "Generic ABI exports:"]
        for name in ["loadu", "load", "request", "unload"] {
            lines.append("\(name): \(names.contains("_" + name) ? "present" : "not found")")
        }
        lines += [
            "(kagari / Aosora use dedicated exports; generic exports are not required for those paths.)",
            "", "Linked libraries:", run("/usr/bin/otool", ["-L", url.path]),
            "", "Static inspection does not call load/request/unload. The last initialization result above comes from an actual startup attempt."
        ]
        return lines.joined(separator: "\n")
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: output.prefix(65536), as: UTF8.self)
            return process.terminationStatus == 0 ? text : "Inspection failed (\(process.terminationStatus)):\n\(text)"
        } catch {
            return "Inspection failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
public final class SHIORIDiagnosticsWindowController: NSWindowController {
    public init(targets: [SHIORIDiagnosticTarget], selectedID: String?,
                saveSelection: @escaping (String, String?, String?) throws -> Void = { _, _, _ in },
                reloadSelection: @escaping (String) async -> Void = { _ in },
                refresh: @escaping () async -> [SHIORIDiagnosticTarget])
    {
        let view = SHIORIDiagnosticsView(targets: targets, selectedID: selectedID ?? targets.first?.id ?? "",
                                         saveSelection: saveSelection, reloadSelection: reloadSelection, refresh: refresh)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = String(localized: "SHIORI読み込み診断")
        window.contentView = NSHostingView(rootView: view)
        window.minSize = NSSize(width: 800, height: 600)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct SHIORIDiagnosticsView: View {
    @State var targets: [SHIORIDiagnosticTarget]
    @State var selectedID: String
    let saveSelection: (String, String?, String?) throws -> Void
    let reloadSelection: (String) async -> Void
    let refresh: () async -> [SHIORIDiagnosticTarget]
    @State private var path = ""
    @State private var kind = ""
    @State private var errorMessage = ""
    @State private var busy = false
    @State private var report = ""
    @State private var revision = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("ゴースト", selection: $selectedID) {
                    ForEach(targets) { target in Text(verbatim: target.name).tag(target.id) }
                }
                Button("再診断") {
                    Task {
                        targets = await refresh()
                        revision += 1
                    }
                }
                Button("コピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                .disabled(report.isEmpty)
            }
            if let target = targets.first(where: { $0.id == selectedID }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("選択順：アプリの明示指定 → ゴーストのshiori.macos → 自動判定（同梱 → 共通導入版）")
                        .font(.caption)
                    HStack {
                        TextField("macOS用SHIORIの絶対パス", text: $path)
                        Button("ファイルを選ぶ…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                path = url.path; kind = ""
                            }
                        }
                        Menu("共通導入版") {
                            ForEach(target.availableModules) { choice in
                                Button(choice.kind) { path = choice.path; kind = choice.kind }
                            }
                        }.disabled(target.availableModules.isEmpty)
                    }
                    HStack {
                        Picker("SHIORIの種類", selection: $kind) {
                            Text("ファイル名から判定").tag("")
                            ForEach(target.kindIDs, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                        Button("選択を保存") { save(path: path, kind: kind.isEmpty ? nil : kind) }
                            .disabled(path.isEmpty)
                        Button("自動選択に戻す") { save(path: nil, kind: nil) }
                        Button("SHIORIを再読み込み") {
                            busy = true
                            Task {
                                await reloadSelection(selectedID)
                                targets = await refresh(); revision += 1; busy = false
                            }
                        }
                    }
                    Text("保存した選択は次回の読み込みから適用する。指定先の消失・CPU不一致・起動失敗は下の診断で確認できる。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("YAYA 6の初回読み込み前に変数をバックアップする。6系で保存した変数を5系へ戻す場合は、切り替え前のバックアップを復元してから起動する。復元時の進行状況はバックアップ時点になる。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !errorMessage.isEmpty {
                        Text(verbatim: errorMessage).foregroundStyle(.red)
                    }
                }
            }
            ScrollView {
                Text(verbatim: report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .disabled(busy)
        .task(id: "\(selectedID):\(revision)") {
            report = "…"
            guard let target = targets.first(where: { $0.id == selectedID }) else { report = ""; return }
            path = target.selectionPath ?? ""
            kind = target.selectionKind ?? ""
            let result = await SHIORIModuleInspector.inspect(target)
            guard !Task.isCancelled else { return }
            report = result
        }
    }

    private func save(path: String?, kind: String?) {
        do {
            try saveSelection(selectedID, path, kind)
            errorMessage = ""
            busy = true
            Task { targets = await refresh(); revision += 1; busy = false }
        } catch { errorMessage = error.localizedDescription }
    }
}

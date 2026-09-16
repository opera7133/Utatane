import AppKit
import SwiftUI

public struct SHIORIDiagnosticTarget: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let selectedFilename: String?
    public let macOSOverride: String?
    public let moduleURL: URL?
    public let runtimeResult: String

    public init(
        id: String, name: String, selectedFilename: String?, macOSOverride: String?,
        moduleURL: URL?, runtimeResult: String
    ) {
        self.id = id
        self.name = name
        self.selectedFilename = selectedFilename
        self.macOSOverride = macOSOverride
        self.moduleURL = moduleURL
        self.runtimeResult = runtimeResult
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
            "shiori.macos: \(target.macOSOverride ?? "(none; automatic selection)")",
            "App CPU: \(architecture)",
            "Last load / initialization: \(target.runtimeResult)",
            ""
        ]
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
    public init(targets: [SHIORIDiagnosticTarget], selectedID: String?, refresh: @escaping () -> [SHIORIDiagnosticTarget]) {
        let view = SHIORIDiagnosticsView(targets: targets, selectedID: selectedID ?? targets.first?.id ?? "", refresh: refresh)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = String(localized: "SHIORI読み込み診断")
        window.contentView = NSHostingView(rootView: view)
        window.minSize = NSSize(width: 520, height: 360)
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
    let refresh: () -> [SHIORIDiagnosticTarget]
    @State private var report = ""
    @State private var revision = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("ゴースト", selection: $selectedID) {
                    ForEach(targets) { target in Text(verbatim: target.name).tag(target.id) }
                }
                Button("再診断") {
                    targets = refresh()
                    revision += 1
                }
                Button("コピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                .disabled(report.isEmpty)
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
        .task(id: "\(selectedID):\(revision)") {
            report = "…"
            guard let target = targets.first(where: { $0.id == selectedID }) else { report = ""; return }
            let result = await SHIORIModuleInspector.inspect(target)
            guard !Task.isCancelled else { return }
            report = result
        }
    }
}

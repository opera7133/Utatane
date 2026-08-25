import AppKit
import UniformTypeIdentifiers
import UtataneSakuraScript

public struct SystemDialogResult: Sendable, Equatable {
    public let kind: SakuraScriptSystemDialogCommand.Kind
    public let id: String
    public let value: String?

    public init(kind: SakuraScriptSystemDialogCommand.Kind, id: String, value: String?) {
        self.kind = kind
        self.id = id
        self.value = value
    }
}

@MainActor
public final class SystemDialogController {
    private var panels: [String: NSWindow] = [:]

    public init() {}

    public func show(_ command: SakuraScriptSystemDialogCommand) -> SystemDialogResult {
        switch command.kind {
        case .open, .save, .folder:
            showFilePanel(command)
        case .color:
            showColorPanel(command)
        }
    }

    public func close(id: String) {
        if id.caseInsensitiveCompare("__SYSTEM_ALL_DIALOG__") == .orderedSame {
            for panel in panels.values {
                panel.performClose(nil)
            }
            return
        }
        panels[id]?.performClose(nil)
    }

    private func showFilePanel(_ command: SakuraScriptSystemDialogCommand) -> SystemDialogResult {
        let panel: NSSavePanel
        if command.kind == .save {
            panel = NSSavePanel()
        } else {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = command.kind == .open
            openPanel.canChooseDirectories = command.kind == .folder
            openPanel.allowsMultipleSelection = false
            panel = openPanel
        }
        panel.title = command.title ?? ""
        panel.directoryURL = directoryURL(command.directory)
        panel.allowedContentTypes = allowedContentTypes(from: command.filter)
        if let name = command.name, !name.isEmpty {
            let suffix = command.fileExtension.map { ".\($0.trimmingCharacters(in: CharacterSet(charactersIn: ".")))" } ?? ""
            panel.nameFieldStringValue = name.hasSuffix(suffix) ? name : name + suffix
        }
        panels[command.id] = panel
        defer { panels[command.id] = nil }
        let response = panel.runModal()
        return SystemDialogResult(
            kind: command.kind,
            id: command.id,
            value: response == .OK ? panel.url?.path : nil
        )
    }

    private func showColorPanel(_ command: SakuraScriptSystemDialogCommand) -> SystemDialogResult {
        let alert = NSAlert()
        alert.messageText = command.title ?? String(localized: "色を選択")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "キャンセル"))
        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        colorWell.color = color(from: command.color) ?? .white
        alert.accessoryView = colorWell
        panels[command.id] = alert.window
        defer { panels[command.id] = nil }
        guard alert.runModal() == .alertFirstButtonReturn,
              let color = colorWell.color.usingColorSpace(.deviceRGB)
        else {
            return SystemDialogResult(kind: .color, id: command.id, value: nil)
        }
        let components = [color.redComponent, color.greenComponent, color.blueComponent].map {
            String(Int(($0 * 255).rounded()))
        }
        return SystemDialogResult(kind: .color, id: command.id, value: components.joined(separator: ","))
    }

    private func directoryURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value == "__system_mydocument__" {
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        return URL(filePath: NSString(string: value).expandingTildeInPath, directoryHint: .isDirectory)
    }

    private func allowedContentTypes(from filter: String?) -> [UTType] {
        guard let filter else { return [] }
        var identifiers = Set<String>()
        return filter
            .split(separator: "|")
            .flatMap { $0.split(separator: ";") }
            .compactMap { component -> UTType? in
                let pattern = component.trimmingCharacters(in: .whitespacesAndNewlines)
                guard pattern.hasPrefix("*."), pattern != "*.*" else { return nil }
                let fileExtension = String(pattern.dropFirst(2))
                guard !fileExtension.isEmpty,
                      let type = UTType(filenameExtension: fileExtension),
                      identifiers.insert(type.identifier).inserted
                else { return nil }
                return type
            }
    }

    private func color(from value: String?) -> NSColor? {
        guard let components = value?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) }),
              components.count >= 3
        else { return nil }
        return NSColor(
            red: min(max(components[0], 0), 255) / 255,
            green: min(max(components[1], 0), 255) / 255,
            blue: min(max(components[2], 0), 255) / 255,
            alpha: 1
        )
    }
}

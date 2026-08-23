import AppKit
import SwiftUI

@MainActor
public final class ContentPickerWindowController: NSObject, NSWindowDelegate {
    public struct Entry: Identifiable, Sendable {
        public let id: URL
        public let name: String

        public init(id: URL, name: String) {
            self.id = id
            self.name = name
        }
    }

    private var window: NSWindow?

    override public init() {
        super.init()
    }

    public func show(
        title: String,
        entries: [Entry],
        selectedID: URL?,
        actionTitle: String,
        allowsCancel: Bool = true,
        onSelect: @escaping @MainActor @Sendable (URL) -> Void
    ) {
        window?.close()
        let picker = ContentPickerView(
            title: title,
            entries: entries,
            selectedID: selectedID,
            actionTitle: actionTitle,
            allowsCancel: allowsCancel,
            onSelect: { [weak self] id in
                self?.window?.close()
                onSelect(id)
            },
            onCancel: { [weak self] in self?.window?.close() }
        )
        let styleMask: NSWindow.StyleMask = allowsCancel
            ? [.titled, .closable]
            : [.titled]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentViewController = NSHostingController(rootView: picker)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = panel
    }

    public func windowWillClose(_: Notification) {
        window = nil
    }
}

private struct ContentPickerView: View {
    let title: String
    let entries: [ContentPickerWindowController.Entry]
    @State private var selection: URL?
    let actionTitle: String
    let allowsCancel: Bool
    let onSelect: (URL) -> Void
    let onCancel: () -> Void

    init(
        title: String,
        entries: [ContentPickerWindowController.Entry],
        selectedID: URL?,
        actionTitle: String,
        allowsCancel: Bool,
        onSelect: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.entries = entries
        _selection = State(initialValue: selectedID)
        self.actionTitle = actionTitle
        self.allowsCancel = allowsCancel
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            List(entries, selection: $selection) { entry in
                Text(entry.name).tag(entry.id)
            }
            HStack {
                if allowsCancel {
                    Button(String(localized: "キャンセル"), action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(actionTitle) {
                    guard let selection else { return }
                    onSelect(selection)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 420, height: 360)
    }
}

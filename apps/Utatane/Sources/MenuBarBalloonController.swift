import AppKit
import SwiftUI
import UtataneSakuraScript

@MainActor
final class MenuBarBalloonController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var timeoutTask: Task<Void, Never>?
    private var onClick: (() -> Void)?
    private var onTimeout: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Utatane")
            button.toolTip = "Utatane"
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        popover.behavior = .applicationDefined
    }

    deinit {
        MainActor.assumeIsolated {
            timeoutTask?.cancel()
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func show(
        _ command: SakuraScriptTrayBalloon,
        onClick: @escaping () -> Void,
        onTimeout: @escaping () -> Void
    ) {
        dismiss(notifyingTimeout: false)
        self.onClick = onClick
        self.onTimeout = onTimeout
        popover.contentViewController = NSHostingController(rootView: MenuBarBalloonView(
            title: command.title,
            text: command.text,
            icon: command.icon,
            onOpen: { [weak self] in self?.dismissAsClick() }
        ))
        popover.contentSize = NSSize(width: 320, height: command.title.isEmpty ? 112 : 140)
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(command.timeoutSeconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(notifyingTimeout: true)
        }
    }

    @objc private func statusItemClicked() {
        guard onClick != nil else { return }
        dismissAsClick()
    }

    private func dismissAsClick() {
        let callback = onClick
        dismiss(notifyingTimeout: false)
        callback?()
    }

    private func dismiss(notifyingTimeout: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        popover.close()
        let callback = notifyingTimeout ? onTimeout : nil
        onClick = nil
        onTimeout = nil
        callback?()
    }
}

private struct MenuBarBalloonView: View {
    let title: String
    let text: String
    let icon: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.title2)
                    .foregroundStyle(icon == "error" ? .red : .primary)
                VStack(alignment: .leading, spacing: 5) {
                    if !title.isEmpty {
                        Text(title).font(.headline)
                    }
                    Text(text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.isEmpty ? text : "\(title)、\(text)")
    }

    private var systemImageName: String {
        switch icon.lowercased() {
        case "error": "xmark.octagon.fill"
        case "warning": "exclamationmark.triangle.fill"
        case "info": "info.circle.fill"
        default: "moon.stars"
        }
    }
}

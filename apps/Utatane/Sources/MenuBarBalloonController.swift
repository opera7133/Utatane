import AppKit
import SwiftUI
import UtataneSakuraScript

@MainActor
final class MenuBarBalloonController: NSObject {
    struct MenuActions {
        let currentGhostName: () -> String?
        let playRandomTalk: () -> Void
        let changeGhost: () -> Void
        let restoreSurfaces: () -> Void
        let showSpeechHistory: () -> Void
        let showSettings: () -> Void
        let showHelp: () -> Void
        let quit: () -> Void
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var timeoutTask: Task<Void, Never>?
    private var onClick: (() -> Void)?
    private var onTimeout: (() -> Void)?
    private var menuActions: MenuActions?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Utatane")
            button.toolTip = "Utatane"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .applicationDefined
    }

    deinit {
        MainActor.assumeIsolated {
            timeoutTask?.cancel()
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func configureMenu(actions: MenuActions) {
        menuActions = actions
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
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if onClick != nil {
            dismissAsClick()
        } else {
            showMenu()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button, let actions = menuActions else { return }
        let menu = NSMenu()
        let ghostName = actions.currentGhostName()
        let hasGhost = ghostName?.isEmpty == false
        if let ghostName, !ghostName.isEmpty {
            let item = NSMenuItem(title: ghostName, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let randomTalkItem = menuItem("ランダムトーク", action: #selector(playRandomTalk))
        randomTalkItem.isEnabled = hasGhost
        menu.addItem(randomTalkItem)
        menu.addItem(menuItem("ゴーストを変更…", action: #selector(changeGhost)))
        let restoreSurfacesItem = menuItem("Surfaceを再表示", action: #selector(restoreSurfaces))
        restoreSurfacesItem.isEnabled = hasGhost
        menu.addItem(restoreSurfacesItem)
        let speechHistoryItem = menuItem("発話履歴", action: #selector(showSpeechHistory))
        speechHistoryItem.isEnabled = hasGhost
        menu.addItem(speechHistoryItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("本体設定", action: #selector(showSettings)))
        menu.addItem(menuItem("Utataneヘルプ", action: #selector(showHelp)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Utataneを終了", action: #selector(quit)))
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: LocalizedStringResource, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func playRandomTalk() {
        menuActions?.playRandomTalk()
    }

    @objc private func changeGhost() {
        menuActions?.changeGhost()
    }

    @objc private func restoreSurfaces() {
        menuActions?.restoreSurfaces()
    }

    @objc private func showSpeechHistory() {
        menuActions?.showSpeechHistory()
    }

    @objc private func showSettings() {
        menuActions?.showSettings()
    }

    @objc private func showHelp() {
        menuActions?.showHelp()
    }

    @objc private func quit() {
        menuActions?.quit()
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

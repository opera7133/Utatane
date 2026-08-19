import AppKit

@MainActor
public enum SurfaceContextMenuItem {
    case action(
        title: String,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        handler: @MainActor () -> Void
    )
    case submenu(title: String, items: [SurfaceContextMenuItem])
    case separator
}

@MainActor
final class SurfaceContextMenuBuilder {
    func build(from definitions: [SurfaceContextMenuItem]) -> NSMenu {
        let menu = ActionMenu()
        append(definitions, to: menu)
        return menu
    }

    private func append(_ definitions: [SurfaceContextMenuItem], to menu: ActionMenu) {
        for definition in definitions {
            switch definition {
            case let .action(title, isSelected, isEnabled, handler):
                let target = MenuActionTarget(handler: handler)
                let item = NSMenuItem(
                    title: title,
                    action: #selector(MenuActionTarget.invoke),
                    keyEquivalent: ""
                )
                item.target = target
                item.state = isSelected ? NSControl.StateValue.on : NSControl.StateValue.off
                item.isEnabled = isEnabled
                menu.targets.append(target)
                menu.addItem(item)
            case let .submenu(title, items):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = ActionMenu(title: title)
                append(items, to: submenu)
                menu.targets.append(contentsOf: submenu.targets)
                item.submenu = submenu
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            }
        }
    }
}

private final class ActionMenu: NSMenu {
    var targets: [MenuActionTarget] = []
}

@MainActor
private final class MenuActionTarget: NSObject {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

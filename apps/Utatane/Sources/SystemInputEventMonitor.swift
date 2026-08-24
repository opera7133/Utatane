import AppKit
import Foundation

@MainActor
final class SystemInputEventMonitor {
    var onEvent: ((String, [Int: String]) -> Void)?

    private var keyMonitor: Any?
    private var screenSaverObservers: [NSObjectProtocol] = []

    func start() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in self?.sendKey(event) }
                return event
            }
        }
        guard screenSaverObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        screenSaverObservers = [
            center.addObserver(
                forName: Notification.Name("com.apple.screensaver.didstart"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.sendScreenSaver("OnScreenSaverStart") }
            },
            center.addObserver(
                forName: Notification.Name("com.apple.screensaver.didstop"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.sendScreenSaver("OnScreenSaverEnd") }
            }
        ]
    }

    private func sendKey(_ event: NSEvent) {
        let modifiers = [
            event.modifierFlags.contains(.control) ? "ctrl" : nil,
            event.modifierFlags.contains(.option) ? "alt" : nil,
            event.modifierFlags.contains(.shift) ? "shift" : nil,
            event.modifierFlags.contains(.command) ? "win" : nil
        ].compactMap(\.self).joined(separator: ",")
        onEvent?("OnKeyPress", [
            0: event.charactersIgnoringModifiers ?? "",
            1: String(event.keyCode),
            2: event.isARepeat ? "1" : "0",
            3: "0",
            4: modifiers
        ])
    }

    private func sendScreenSaver(_ id: String) {
        onEvent?(id, [0: "macOS Screen Saver", 1: "", 2: ""])
    }
}

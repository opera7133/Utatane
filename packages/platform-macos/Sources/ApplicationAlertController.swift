import AppKit

@MainActor
public final class ApplicationAlertController {
    private var displayedMessages: Set<String> = []
    private var lastDisplayedAt: [String: Date] = [:]

    public init() {}

    public func showError(_ message: String) {
        let now = Date()
        if let lastDisplayedAt = lastDisplayedAt[message], now.timeIntervalSince(lastDisplayedAt) < 5 {
            return
        }
        guard displayedMessages.insert(message).inserted else { return }
        defer { displayedMessages.remove(message) }
        lastDisplayedAt[message] = now
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSApplication.shared.applicationIconImage
        alert.messageText = "エラー"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

import AppKit

@MainActor
public final class ApplicationAlertController {
    private var displayedMessages: Set<String> = []
    private var lastDisplayedAt: [String: Date] = [:]

    public init() {}

    public func showError(_ message: String) {
        let presentation = ApplicationErrorPresentation(message: message)
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
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func confirmContentRemoval(name: String, kind: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSApplication.shared.applicationIconImage
        alert.messageText = String(localized: "コンテンツを削除しますか？")
        alert.informativeText = String(
            format: String(localized: "「%@」をmacOSのゴミ箱へ移動します。あとから戻すこともできます。"),
            name
        ) + "\n\n\(String(localized: "種類")): \(kind)"
        alert.addButton(withTitle: String(localized: "ゴミ箱へ移動"))
        alert.addButton(withTitle: String(localized: "キャンセル"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

public struct ApplicationErrorPresentation: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(message: String) {
        self.message = message
        if message.contains("SHIORIにはまだ対応していない") {
            title = "このゴーストはまだ起動できない"
        } else if message.contains("ネイティブSHIORIが見つからない") {
            title = "ネイティブSHIORIが見つからない"
        } else if message.contains("Wine") || message.contains("Windows SHIORI") {
            title = "Windows互換機能を起動できない"
        } else if ["YAYA", "SATORI", "KAWARI", "SHIORI"].contains(where: message.contains) {
            title = "ゴーストの人格を起動できない"
        } else {
            title = "エラー"
        }
    }
}

import AppKit
import SwiftUI

@MainActor
public final class TextInputWindowController: NSObject, NSWindowDelegate {
    public struct Request: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let prompt: String?
        public let initialValue: String
        public let placeholder: String?
        public let actionTitle: String
        public let allowsCancel: Bool
        public let onCommit: @MainActor @Sendable (String) -> Void
        public let onCancel: (@MainActor @Sendable () -> Void)?

        public init(
            id: String = UUID().uuidString,
            title: String,
            prompt: String? = nil,
            initialValue: String = "",
            placeholder: String? = nil,
            actionTitle: String = String(localized: "OK"),
            allowsCancel: Bool = true,
            onCommit: @escaping @MainActor @Sendable (String) -> Void,
            onCancel: (@MainActor @Sendable () -> Void)? = nil
        ) {
            self.id = id
            self.title = title
            self.prompt = prompt
            self.initialValue = initialValue
            self.placeholder = placeholder
            self.actionTitle = actionTitle
            self.allowsCancel = allowsCancel
            self.onCommit = onCommit
            self.onCancel = onCancel
        }
    }

    private var window: NSWindow?
    private var currentRequest: Request?

    override public init() {
        super.init()
    }

    public func show(_ request: Request) {
        closeCurrentWindow(invokeCancel: true)
        currentRequest = request

        let view = TextInputDialogView(
            request: request,
            onCommit: { [weak self] text in
                guard let self else { return }
                let req = currentRequest
                closeCurrentWindow(invokeCancel: false)
                req?.onCommit(text)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                let req = currentRequest
                closeCurrentWindow(invokeCancel: false)
                req?.onCancel?()
            }
        )

        let styleMask: NSWindow.StyleMask = request.allowsCancel
            ? [.titled, .closable]
            : [.titled]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = request.title
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = panel
    }

    public func showPrompt(
        id: String = UUID().uuidString,
        title: String,
        prompt: String? = nil,
        initialValue: String = "",
        placeholder: String? = nil,
        actionTitle: String = String(localized: "OK"),
        allowsCancel: Bool = true
    ) async -> String? {
        await withCheckedContinuation { continuation in
            show(Request(
                id: id,
                title: title,
                prompt: prompt,
                initialValue: initialValue,
                placeholder: placeholder,
                actionTitle: actionTitle,
                allowsCancel: allowsCancel,
                onCommit: { text in
                    continuation.resume(returning: text)
                },
                onCancel: {
                    continuation.resume(returning: nil)
                }
            ))
        }
    }

    public func close(id: String? = nil) {
        if let id {
            if currentRequest?.id == id || id == "__SYSTEM_ALL_INPUT__" {
                closeCurrentWindow(invokeCancel: true)
            }
        } else {
            closeCurrentWindow(invokeCancel: true)
        }
    }

    private func closeCurrentWindow(invokeCancel: Bool) {
        let request = currentRequest
        currentRequest = nil
        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }
        if invokeCancel {
            request?.onCancel?()
        }
    }

    public func windowWillClose(_: Notification) {
        if let request = currentRequest {
            currentRequest = nil
            window = nil
            request.onCancel?()
        }
    }
}

private struct TextInputDialogView: View {
    let request: TextInputWindowController.Request
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        request: TextInputWindowController.Request,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: request.initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let prompt = request.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            TextField(
                request.placeholder ?? "",
                text: $text
            )
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                onCommit(text)
            }
            HStack {
                if request.allowsCancel {
                    Button(String(localized: "キャンセル"), action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(request.actionTitle) {
                    onCommit(text)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            isFocused = true
        }
    }
}

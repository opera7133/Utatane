import AppKit
import SwiftUI

@MainActor
public final class TextInputWindowController: NSObject, NSWindowDelegate {
    public struct Request: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let prompt: String?
        public let initialValue: String
        public let autocompleteValues: [String]
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
            autocompleteValues: [String] = [],
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
            self.autocompleteValues = autocompleteValues
            self.placeholder = placeholder
            self.actionTitle = actionTitle
            self.allowsCancel = allowsCancel
            self.onCommit = onCommit
            self.onCancel = onCancel
        }
    }

    private var window: NSWindow?
    private var currentRequest: Request?
    private var timeoutTask: Task<Void, Never>?

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
        autocompleteValues: [String] = [],
        placeholder: String? = nil,
        actionTitle: String = String(localized: "OK"),
        allowsCancel: Bool = true,
        timeoutMilliseconds: Int? = nil
    ) async -> String? {
        await withCheckedContinuation { continuation in
            show(Request(
                id: id,
                title: title,
                prompt: prompt,
                initialValue: initialValue,
                autocompleteValues: autocompleteValues,
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
            if let timeoutMilliseconds, timeoutMilliseconds > 0 {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                    guard !Task.isCancelled else { return }
                    self?.closeCurrentWindow(invokeCancel: true)
                }
            }
        }
    }

    public static func autocompleteValues(from value: String?) -> [String] {
        guard let value else { return [] }
        var seen = Set<String>()
        return value
            .split(separator: "\u{1}", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
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
        timeoutTask?.cancel()
        timeoutTask = nil
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
            if request.autocompleteValues.isEmpty {
                TextField(
                    request.placeholder ?? "",
                    text: $text
                )
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    onCommit(text)
                }
            } else {
                AutocompleteTextField(
                    text: $text,
                    placeholder: request.placeholder ?? "",
                    values: request.autocompleteValues,
                    onCommit: onCommit
                )
                .frame(height: 24)
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

private struct AutocompleteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let values: [String]
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.completes = true
        comboBox.placeholderString = placeholder
        comboBox.addItems(withObjectValues: values)
        comboBox.stringValue = text
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        let currentValues = comboBox.objectValues.compactMap { $0 as? String }
        if currentValues != values {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: values)
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
        private var text: Binding<String>
        private let onCommit: (String) -> Void

        init(text: Binding<String>, onCommit: @escaping (String) -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox,
                  notification.userInfo?["NSTextMovement"] as? Int == NSReturnTextMovement
            else { return }
            onCommit(comboBox.stringValue)
        }
    }
}

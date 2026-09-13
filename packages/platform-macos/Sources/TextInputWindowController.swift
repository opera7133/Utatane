import AppKit
import SwiftUI
import UtataneBalloon

@MainActor
public final class TextInputWindowController: NSObject, NSWindowDelegate {
    public struct Appearance: Sendable, Equatable {
        public let fontName: String?
        public let fontHeight: Int
        public let fontColor: BalloonColor
        public let backgroundColor: BalloonColor?
        public let inputX: Int
        public let inputY: Int
        public let inputWidth: Int?
        public let inputHeight: Int?
        public let backgroundImageURL: URL?

        public init(balloon: BalloonDefinition, backgroundImageURL: URL?) {
            fontName = balloon.communicateBoxFontName
            fontHeight = balloon.communicateBoxFontHeight
            fontColor = balloon.communicateBoxFontColor
            backgroundColor = balloon.communicateBoxBackgroundColor
            inputX = balloon.communicateBoxX
            inputY = balloon.communicateBoxY
            inputWidth = balloon.communicateBoxWidth
            inputHeight = balloon.communicateBoxHeight
            self.backgroundImageURL = backgroundImageURL
        }
    }

    public struct Request: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let prompt: String?
        public let initialValue: String
        public let autocompleteValues: [String]
        public let placeholder: String?
        public let actionTitle: String
        public let allowsCancel: Bool
        public let appearance: Appearance?
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
            appearance: Appearance? = nil,
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
            self.appearance = appearance
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

        let backgroundImageSize = request.appearance?.backgroundImageURL
            .flatMap { NSImage(contentsOf: $0)?.size }
        let panelSize = Self.panelSize(for: request.appearance, backgroundImageSize: backgroundImageSize)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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
        appearance: Appearance? = nil,
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
                appearance: appearance,
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

    static func panelSize(for appearance: Appearance?, backgroundImageSize: NSSize?) -> NSSize {
        guard let appearance else { return NSSize(width: 380, height: 160) }
        let inputWidth = CGFloat(max(appearance.inputWidth ?? 340, 120))
        let inputHeight = CGFloat(max(appearance.inputHeight ?? 24, 22))
        let contentWidth = CGFloat(max(appearance.inputX, 20)) + inputWidth + 20
        let contentHeight = CGFloat(max(appearance.inputY, 20)) + inputHeight + 84
        return NSSize(
            width: max(380, contentWidth, backgroundImageSize?.width ?? 0),
            height: max(160, contentHeight, backgroundImageSize?.height ?? 0)
        )
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
        ZStack(alignment: .topLeading) {
            inputBackground
            VStack(alignment: .leading, spacing: 14) {
                if let prompt = request.prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Group {
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
                            fontName: request.appearance?.fontName,
                            fontHeight: CGFloat(max(request.appearance?.fontHeight ?? 13, 1)),
                            fontColor: nsColor(
                                request.appearance?.fontColor ?? BalloonColor(red: 0, green: 0, blue: 0)
                            ),
                            backgroundColor: request.appearance?.backgroundColor.map(nsColor),
                            onCommit: onCommit
                        )
                    }
                }
                .font(inputFont)
                .foregroundStyle(inputForegroundColor)
                .frame(width: inputWidth, height: inputHeight)
                .background(inputBackgroundColor, in: RoundedRectangle(cornerRadius: 5))
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
            .padding(.leading, inputOriginX)
            .padding(.top, inputOriginY)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            isFocused = true
        }
    }

    @ViewBuilder
    private var inputBackground: some View {
        if let url = request.appearance?.backgroundImageURL,
           let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color(NSColor.windowBackgroundColor)
        }
    }

    private var inputOriginX: CGFloat {
        CGFloat(max(request.appearance?.inputX ?? 20, 0))
    }

    private var inputOriginY: CGFloat {
        CGFloat(max(request.appearance?.inputY ?? 20, 0))
    }

    private var inputWidth: CGFloat {
        CGFloat(max(request.appearance?.inputWidth ?? 340, 120))
    }

    private var inputHeight: CGFloat {
        CGFloat(max(request.appearance?.inputHeight ?? 24, 22))
    }

    private var inputFont: Font {
        let height = CGFloat(max(request.appearance?.fontHeight ?? 13, 1))
        guard let name = request.appearance?.fontName?.split(separator: ",").first else {
            return .system(size: height)
        }
        return .custom(name.trimmingCharacters(in: .whitespacesAndNewlines), size: height)
    }

    private var inputForegroundColor: Color {
        color(request.appearance?.fontColor ?? BalloonColor(red: 0, green: 0, blue: 0))
    }

    private var inputBackgroundColor: Color {
        guard let backgroundColor = request.appearance?.backgroundColor else {
            return Color(NSColor.textBackgroundColor)
        }
        return color(backgroundColor)
    }

    private func color(_ value: BalloonColor) -> Color {
        Color(
            red: Double(value.red) / 255,
            green: Double(value.green) / 255,
            blue: Double(value.blue) / 255
        )
    }

    private func nsColor(_ value: BalloonColor) -> NSColor {
        NSColor(
            red: CGFloat(value.red) / 255,
            green: CGFloat(value.green) / 255,
            blue: CGFloat(value.blue) / 255,
            alpha: 1
        )
    }
}

private struct AutocompleteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let values: [String]
    let fontName: String?
    let fontHeight: CGFloat
    let fontColor: NSColor
    let backgroundColor: NSColor?
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
        applyAppearance(to: comboBox)
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
        applyAppearance(to: comboBox)
    }

    private func applyAppearance(to comboBox: NSComboBox) {
        let names = fontName?.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        comboBox.font = names.lazy.compactMap { NSFont(name: $0, size: fontHeight) }.first
            ?? NSFont.systemFont(ofSize: fontHeight)
        comboBox.textColor = fontColor
        if let backgroundColor {
            comboBox.backgroundColor = backgroundColor
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
